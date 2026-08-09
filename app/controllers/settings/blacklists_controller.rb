# frozen_string_literal: true

require 'csv'

# Customer-facing controller for managing organization-specific blacklist entries.
# Customers can view their blacklist, add new entries (single or bulk), and remove entries.
# Global blacklist entries are visible but cannot be modified by customers.
class Settings::BlacklistsController < ApplicationController
  # Rails 8.1 raises an error if a callback's :only/:except option references a non-existent action.
  # Since ApplicationController defines callbacks with show/edit/update in only:/except: options,
  # we must skip those callbacks and handle authorization manually.
  skip_after_action :verify_policy_scoped
  skip_after_action :verify_authorized

  before_action :load_organization
  before_action :redirect_amplifa_admin
  before_action :authorize_add, only: %i[create import]
  before_action :authorize_remove, only: [:destroy]
  before_action :set_blacklist, only: [:destroy]

  PER_PAGE = 25

  def index
    skip_policy_scope

    render inertia: 'Customer/Settings/Blacklists/Index', props: base_props.merge(index_props)
  end

  def create
    skip_policy_scope

    @blacklist = Blacklist.new(blacklist_params)
    @blacklist.organization = @organization
    @blacklist.created_by = current_account
    @blacklist.source = 'manual'

    if @blacklist.save
      log_activity('blacklist_create', {
                     blacklist_id: @blacklist.id,
                     value: @blacklist.value,
                     value_type: @blacklist.value_type
                   })

      redirect_to settings_blacklists_path, notice: I18n.t('settings.blacklists.created')
    else
      # Re-render index with errors for inline form
      render inertia: 'Customer/Settings/Blacklists/Index', props: base_props.merge(index_props).merge({
                                                                                                         errors: @blacklist.errors.full_messages,
                                                                                                         form_values: {
                                                                                                           value: @blacklist.value,
                                                                                                           value_type: @blacklist.value_type
                                                                                                         }
                                                                                                       })
    end
  end

  def import
    skip_policy_scope

    service = BlacklistImportService.new(
      organization: @organization,
      created_by: current_account,
      source: 'import'
    )
    results = service.call(params[:input])

    log_activity('blacklist_import', {
                   organization_id: @organization.id,
                   created_count: results[:created_count],
                   skipped_count: results[:skipped_count],
                   invalid_count: results[:invalid_count]
                 })

    redirect_to settings_blacklists_path, notice: I18n.t('settings.blacklists.imported',
                                                         created: results[:created_count],
                                                         skipped: results[:skipped_count])
  end

  def export
    skip_policy_scope

    csv = CSV.generate(headers: true) do |rows|
      rows << %w[value type reason]

      base_scope.reorder(:value_type, :value).each do |blacklist|
        rows << [blacklist.value, blacklist.value_type, blacklist.reason]
      end
    end

    send_data(
      csv,
      type: 'text/csv; charset=utf-8',
      disposition: 'attachment',
      filename: "#{@organization.name.parameterize}_blacklist_#{Date.current.iso8601}.csv"
    )
  end

  def destroy
    skip_policy_scope

    # Prevent deletion of global entries
    if @blacklist.global?
      redirect_to settings_blacklists_path, alert: I18n.t('settings.blacklists.cannot_delete_global')
      return
    end

    # Ensure the entry belongs to this organization
    unless @blacklist.organization_id == @organization.id
      redirect_to settings_blacklists_path, alert: I18n.t('settings.blacklists.not_found')
      return
    end

    value = @blacklist.value
    value_type = @blacklist.value_type

    if @blacklist.destroy
      log_activity('blacklist_delete', {
                     value: value,
                     value_type: value_type
                   })

      redirect_to settings_blacklists_path, notice: I18n.t('settings.blacklists.deleted')
    else
      redirect_to settings_blacklists_path, alert: I18n.t('settings.blacklists.delete_failed')
    end
  end

  private

  def authorize_add
    return if current_customer_admin?

    redirect_to settings_blacklists_path, alert: I18n.t('pundit.not_authorized')
    nil
  end

  def load_organization
    @organization = Current.organization
  end

  def redirect_amplifa_admin
    return unless current_account.amplifa_admin?

    skip_policy_scope
    redirect_to admin_blacklists_path and return
  end

  def authorize_remove
    return if current_customer_admin?

    redirect_to settings_blacklists_path, alert: I18n.t('pundit.not_authorized')
    nil
  end

  def set_blacklist
    @blacklist = Blacklist.find_by(id: params[:id])

    return if @blacklist

    redirect_to settings_blacklists_path, alert: I18n.t('settings.blacklists.not_found')
    nil
  end

  def blacklist_params
    params.require(:blacklist).permit(:value, :value_type)
  end

  def base_props
    {
      canManage: current_customer_admin?,
      canAdd: current_customer_admin?,
      canRemove: current_customer_admin?,
      value_types: Blacklist::VALUE_TYPES
    }
  end

  def index_props
    email_search = params[:email_search].to_s
    domain_search = params[:domain_search].to_s
    email_total_count = base_scope.where(value_type: 'email').count
    domain_total_count = base_scope.where(value_type: 'domain').count

    email_scope = apply_search(base_scope.where(value_type: 'email'), email_search)
    domain_scope = apply_search(base_scope.where(value_type: 'domain'), domain_search)

    email_entries, email_pagination = paginate(email_scope, params[:email_page])
    domain_entries, domain_pagination = paginate(domain_scope, params[:domain_page])

    {
      email_blacklists: serialize_blacklists(email_entries),
      domain_blacklists: serialize_blacklists(domain_entries),
      filters: {
        email_search: email_search,
        domain_search: domain_search
      },
      pagination: {
        emails: email_pagination,
        domains: domain_pagination
      },
      totals: {
        emails: email_total_count,
        domains: domain_total_count
      }
    }
  end

  def base_scope
    # Only org-specific entries, not global entries
    Blacklist.where(organization_id: @organization.id)
             .includes(:created_by)
             .order(created_at: :desc)
  end

  def apply_search(scope, search)
    return scope unless search.present?

    scope.where('LOWER(blacklists.value) LIKE ?', "%#{search.strip.downcase}%")
  end

  def paginate(scope, page_param)
    page = [page_param.to_i, 1].max
    total_count = scope.count
    total_pages = (total_count.to_f / PER_PAGE).ceil
    records = scope.offset((page - 1) * PER_PAGE).limit(PER_PAGE)

    [records, {
      current_page: page,
      total_pages: total_pages,
      total_count: total_count,
      per_page: PER_PAGE
    }]
  end

  def serialize_blacklists(blacklists)
    blacklists.map do |blacklist|
      {
        id: blacklist.id,
        value: blacklist.value,
        value_type: blacklist.value_type,
        source: blacklist.source,
        reason: blacklist.reason,
        is_global: blacklist.global?,
        can_delete: !blacklist.global? && current_customer_admin?,
        created_at: blacklist.created_at.iso8601,
        created_by: blacklist.created_by&.full_name
      }
    end
  end

  def log_activity(action, details)
    AdminActivity.create!(
      account: current_account,
      organization: @organization,
      action: action,
      details: details,
      ip_address: request.remote_ip,
      user_agent: request.user_agent
    )
  end

  def current_customer_admin?
    Current.organization_membership&.customer_admin? || false
  end
end
