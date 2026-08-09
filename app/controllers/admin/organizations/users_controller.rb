# frozen_string_literal: true

class Admin::Organizations::UsersController < Admin::Organizations::BaseController
  before_action :set_account, only: %i[show edit update destroy send_reset_password_email set_password]

  PER_PAGE = 25

  def index
    memberships = @organization.organization_memberships.active.includes(:account).order(created_at: :desc)
    memberships = memberships.where(role: params[:role]) if params[:role].present?

    page = (params[:page] || 1).to_i
    total_count = memberships.count
    total_pages = (total_count.to_f / PER_PAGE).ceil
    memberships = memberships.offset((page - 1) * PER_PAGE).limit(PER_PAGE)

    render inertia: 'Admin/Organizations/Users/Index', props: common_props.merge(
      users: serialize_memberships(memberships),
      role_options: %w[customer_admin customer_user],
      filters: { role: params[:role] },
      pagination: {
        current_page: page,
        total_pages: total_pages,
        total_count: total_count,
        per_page: PER_PAGE
      }
    )
  end

  def show
    render_show
  end

  def send_reset_password_email
    rodauth_auth = RodauthApp.rodauth.allocate
    rodauth_auth.account_from_id(@account.id)

    if !rodauth_auth.send(:open_account?) || rodauth_auth.reset_password_email_recently_sent?
      redirect_to admin_organization_user_path(@organization, @account),
                  alert: t('admin.users.password.reset_email_failed')
      return
    end

    rodauth_auth.send(:generate_reset_password_key_value)
    rodauth_auth.send(:transaction) do
      rodauth_auth.create_reset_password_key
      rodauth_auth.send_reset_password_email
    end

    log_admin_activity('organization_user_password_reset_email_sent', {
                         account_id: @account.id,
                         email: @account.email
                       })

    redirect_to edit_admin_organization_user_path(@organization, @account),
                notice: t('admin.users.password.reset_email_sent')
  end

  def set_password
    errors = password_validation_errors

    if errors.any?
      render_edit(password_errors: errors, status: :unprocessable_entity)
      return
    end

    @account.update_columns(
      password_hash: RodauthApp.rodauth.allocate.password_hash(password_params[:new_password])
    )

    log_admin_activity('organization_user_password_set_by_admin', {
                         account_id: @account.id,
                         email: @account.email
                       })

    redirect_to edit_admin_organization_user_path(@organization, @account),
                notice: t('admin.users.password.set_success')
  end

  def new
    render inertia: 'Admin/Organizations/Users/New', props: common_props.merge(
      role_options: %w[customer_admin customer_user]
    )
  end

  def create
    attributes = account_params.to_h.symbolize_keys
    password = attributes.delete(:password).presence || SecureRandom.hex(16)
    @account = Account.new(attributes.merge(organization: @organization, status: :verified))
    @account.password_hash = RodauthApp.rodauth.allocate.password_hash(password)

    if @account.save
      log_admin_activity('organization_user_created', {
                           account_id: @account.id,
                           email: @account.email,
                           role: @account.role
                         })

      redirect_to admin_organization_user_path(@organization, @account),
                  notice: t('admin.users.created')
    else
      render inertia: 'Admin/Organizations/Users/New', props: common_props.merge(
        user: @account.attributes.slice('email', 'first_name', 'last_name', 'role'),
        errors: @account.errors.messages,
        role_options: %w[customer_admin customer_user]
      )
    end
  end

  def edit
    render_edit
  end

  def update
    permitted_params = account_params

    return render_amplifa_admin_promotion_error if permitted_params[:role] == 'amplifa_admin'

    if update_account_and_membership(permitted_params)
      redirect_after_successful_update
    else
      render_edit(errors: @account.errors.messages)
    end
  end

  def destroy
    email = @account.email

    if @account.destroy
      log_admin_activity('organization_user_deleted', { email: email })
      redirect_to admin_organization_users_path(@organization),
                  notice: t('admin.users.deleted')
    else
      redirect_to admin_organization_user_path(@organization, @account),
                  alert: t('admin.users.delete_failed')
    end
  end

  private

  def set_account
    @membership = @organization.organization_memberships.active.find_by!(account_id: params[:id])
    @account = @membership.account
  end

  def account_params
    source = params[:account].presence || params[:user].presence || params

    source.permit(:email, :first_name, :last_name, :role, :password)
  end

  def render_amplifa_admin_promotion_error
    render_edit(errors: { role: [t('admin.users.organization_scope_amplifa_admin_forbidden')] },
                status: :unprocessable_entity)
  end

  def redirect_after_successful_update
    log_admin_activity('organization_user_updated', {
                         account_id: @account.id,
                         changes: @account.previous_changes.except(:updated_at, :password_hash)
                       })

    redirect_to admin_organization_user_path(@organization, @account),
                notice: t('admin.users.updated')
  end

  def update_account_and_membership(permitted_params)
    ActiveRecord::Base.transaction do
      account_attributes = permitted_params.except(:role)
      @account.update!(account_attributes)

      if permitted_params[:role].present?
        @membership.update!(role: permitted_params[:role], status: 'active', deactivated_at: nil)
      end
    end
    true
  rescue ActiveRecord::RecordInvalid => e
    e.record.errors.each do |error|
      @account.errors.add(error.attribute, error.message)
    end
    false
  end

  def password_params
    params.require(:password).permit(:new_password, :new_password_confirmation)
  end

  def password_validation_errors
    errors = {}

    if password_params[:new_password].blank?
      errors[:new_password] = [t('admin.users.password.new_password_required')]
    elsif password_params[:new_password].length < 8
      errors[:new_password] = [t('admin.users.password.new_password_too_short')]
    end

    if password_params[:new_password_confirmation].blank?
      errors[:new_password_confirmation] = [t('admin.users.password.confirmation_required')]
    elsif password_params[:new_password_confirmation] != password_params[:new_password]
      errors[:new_password_confirmation] = [t('admin.users.password.confirmation_mismatch')]
    end

    errors
  end

  def serialize_memberships(memberships)
    memberships.map do |membership|
      account = membership.account
      account.as_json(only: %i[id email first_name last_name created_at deactivated_at]).merge(
        'full_name' => account.full_name,
        'role' => membership.role
      )
    end
  end

  def serialize_account_full(account)
    account.as_json(only: %i[
                      id email first_name last_name status created_at updated_at
                    ]).merge(
                      'full_name' => account.full_name,
                      'role' => @membership&.role || account.role
                    )
  end

  def serialize_account_for_edit(account)
    account.as_json(only: %i[id email first_name last_name]).merge('role' => @membership&.role || account.role)
  end

  def render_show(password_errors: nil, status: :ok)
    render inertia: 'Admin/Organizations/Users/Show', props: common_props.merge(
      account: serialize_account_full(@account),
      password_errors: password_errors
    ), status: status
  end

  def render_edit(errors: nil, password_errors: nil, status: :ok)
    render inertia: 'Admin/Organizations/Users/Edit', props: common_props.merge(
      account: serialize_account_for_edit(@account),
      errors: errors,
      roles: %w[customer_admin customer_user],
      password_errors: password_errors
    ), status: status
  end

  def log_admin_activity(action, details)
    AdminActivity.create!(
      account: current_account,
      organization: @organization,
      action: action,
      details: details,
      ip_address: request.remote_ip,
      user_agent: request.user_agent
    )
  end
end
