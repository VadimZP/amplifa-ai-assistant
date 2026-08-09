class Admin::OrganizationsController < Admin::BaseController
  before_action :set_organization, except: %i[index new create]

  PER_PAGE = 100

  def index
    organizations = Organization.all

    filter = params[:status].presence
    organizations = case filter
                    when 'archived'
                      organizations.where.not(archived_at: nil)
                    when 'deactivated'
                      organizations.where.not(deactivated_at: nil).not_archived
                    else
                      organizations.active.not_archived
                    end

    if params[:search].present?
      organizations = organizations.where('organizations.name ILIKE ?', "%#{params[:search]}%")
    end

    page = (params[:page] || 1).to_i
    total_count = organizations.count
    total_pages = (total_count.to_f / PER_PAGE).ceil

    organizations = organizations.order(created_at: :desc)
                                 .offset((page - 1) * PER_PAGE)
                                 .limit(PER_PAGE)
                                 .to_a
    card_stats = load_card_stats(organizations.map(&:id))

    render inertia: 'Admin/Organizations/Index', props: {
      organizations: organizations.map { |org| serialize_organization_card(org, stats: card_stats[org.id]) },
      pagination: {
        current_page: page,
        total_pages: total_pages,
        total_count: total_count,
        per_page: PER_PAGE
      },
      filters: {
        search: params[:search],
        status: filter
      }
    }
  end

  def show
    stats = organization_stats(@organization)
    activities = recent_activities(@organization)

    render inertia: 'Admin/Organizations/Show', props: {
      organization: serialize_organization_detail(@organization),
      stats: stats,
      agents: agent_sequence_summaries_by_org_id([@organization.id]).fetch(@organization.id, []),
      recent_activities: activities,
      current_tab: 'overview'
    }
  end

  def new
    # WHY: Amplifa admins need to create organizations to onboard new customers.
    # This action renders the form for creating a new organization.
    # We pass the same dropdown options as the edit form so admins can set all fields during creation.
    render inertia: 'Admin/Organizations/New', props: {
      size_options: ['1-10', '11-50', '51-200', '201-1000', '1000+'],
      locale_options: SupportedLocale::ALL,
      currency_options: %w[EUR USD GBP CHF],
      plan_options: AppSetting.current.normalized_billing_plans
    }
  end

  def create
    # WHY: This action handles the actual creation of a new organization.
    # Organizations are created with minimal required info (name) and can be
    # updated later with additional details. Status defaults to 'onboarding'.
    @organization = Organization.new(organization_params)
    # WHY: Set defaults for required fields that admin doesn't need to specify
    @organization.status ||= 'onboarding'
    @organization.locale ||= 'en'
    @organization.currency ||= 'EUR'

    if @organization.save
      # WHY: Log the admin activity for audit trail
      AdminActivity.create!(
        account: current_account,
        action: 'organization_created',
        details: {
          organization_id: @organization.id,
          organization_name: @organization.name,
          industry: @organization.industry,
          size: @organization.size
        },
        ip_address: request.remote_ip,
        user_agent: request.user_agent
      )

      redirect_to admin_organizations_path, notice: 'Organization created successfully'
    else
      # WHY: Re-render the form with errors so admin can correct the issues.
      # Include all entered values and dropdown options so admin can fix just the errors.
      render inertia: 'Admin/Organizations/New', props: {
        organization: @organization.as_json(only: %i[
                                              name industry size onboarded two_factor_authentication_required
                                              website average_contract_value meeting_price monthly_subscription
                                              calendly_url locale currency plan_tier monthly_meeting_limit
                                            ]),
        errors: @organization.errors.messages,
        size_options: ['1-10', '11-50', '51-200', '201-1000', '1000+'],
        locale_options: SupportedLocale::ALL,
        currency_options: %w[EUR USD GBP CHF],
        plan_options: AppSetting.current.normalized_billing_plans
      }
    end
  end

  def edit
    render inertia: 'Admin/Organizations/Edit', props: {
      organization: @organization.as_json(
        only: %i[
          id name industry size onboarded deactivated_at
          two_factor_authentication_required
          website average_contract_value meeting_price monthly_subscription
          calendly_url locale currency billing_cycle_started_on
          plan_tier monthly_meeting_limit
        ],
        include: {
          accounts: { only: %i[id email first_name last_name role] }
        }
      ),
      size_options: ['1-10', '11-50', '51-200', '201-1000', '1000+'],
      locale_options: SupportedLocale::ALL,
      currency_options: %w[EUR USD GBP CHF],
      plan_options: AppSetting.current.normalized_billing_plans
    }
  end

  def update
    if @organization.update(organization_params)
      redirect_to admin_organization_path(@organization), notice: 'Organization updated successfully'
    else
      redirect_to edit_admin_organization_path(@organization), alert: @organization.errors.full_messages.join(', ')
    end
  end

  def destroy
    if @organization.deactivate!
      redirect_to admin_organizations_path, notice: 'Organization deactivated successfully'
    else
      redirect_to admin_organizations_path, alert: 'Failed to deactivate organization'
    end
  end

  def archive
    if @organization.archived?
      redirect_to admin_organizations_path, alert: 'Organization is already archived'
      return
    end

    unless @organization.deactivated_at.present?
      redirect_to admin_organization_path(@organization), alert: 'Only deactivated organizations can be archived'
      return
    end

    @organization.archive!

    AdminActivity.create!(
      account: current_account,
      organization: @organization,
      action: 'organization_archived',
      details: {
        organization_id: @organization.id,
        organization_name: @organization.name
      },
      ip_address: request.remote_ip,
      user_agent: request.user_agent
    )

    redirect_to admin_organizations_path, notice: 'Organization archived successfully'
  end

  private

  def set_organization
    @organization = Organization.find(params[:id])
  end

  def organization_params
    params.require(:organization).permit(
      :name, :industry, :size, :onboarded, :two_factor_authentication_required,
      :website, :average_contract_value, :meeting_price, :monthly_subscription,
      :calendly_url, :locale, :currency, :billing_cycle_started_on,
      :plan_tier, :monthly_meeting_limit
    )
  end

  def load_card_stats(org_ids)
    default_stats = default_card_stats
    return {} if org_ids.empty?

    stats_by_org_id = org_ids.index_with { default_stats.dup }

    merge_count_stat(stats_by_org_id, Agent.not_deleted.where(organization_id: org_ids).group(:organization_id).count, :agents_count)
    merge_count_stat(stats_by_org_id, Playbook.where(organization_id: org_ids).group(:organization_id).count, :playbooks_count)
    merge_count_stat(stats_by_org_id, Sender.where(organization_id: org_ids).group(:organization_id).count, :senders_count)
    merge_count_stat(stats_by_org_id, Mailbox.not_deleted.where(organization_id: org_ids).group(:organization_id).count,
                     :mailboxes_count)
    merge_count_stat(stats_by_org_id, daily_sending_capacity_by_org_id(org_ids), :daily_sending_capacity)

    stats_by_org_id
  end

  def default_card_stats
    {
      agents_count: 0,
      playbooks_count: 0,
      senders_count: 0,
      mailboxes_count: 0,
      daily_sending_capacity: 0,
      messages_sent_today: 0,
      messages_sent_previous_sending_day: 0
    }
  end

  def merge_count_stat(stats_by_org_id, values_by_org_id, stat_key)
    values_by_org_id.each do |org_id, value|
      stats_by_org_id[org_id.to_i][stat_key] = value.to_i
    end
  end

  def daily_sending_capacity_by_org_id(org_ids)
    Mailbox.where(organization_id: org_ids, status: 'active')
           .where('warmup_started_at IS NULL OR warmup_started_at <= ?', Mailbox::WARMUP_DAYS.days.ago)
           .where.not(sender_id: nil)
           .group(:organization_id)
           .sum(:daily_send_limit)
  end

  def serialize_organization_card(org, stats: nil)
    stats ||= default_card_stats

    {
      id: org.id,
      name: org.name,
      industry: org.industry,
      size: org.size,
      onboarded: org.onboarded,
      deactivated_at: org.deactivated_at,
      archived_at: org.archived_at,
      created_at: org.created_at,
      active: org.active?,
      agents_count: stats[:agents_count].to_i,
      playbooks_count: stats[:playbooks_count].to_i,
      senders_count: stats[:senders_count].to_i,
      mailboxes_count: stats[:mailboxes_count].to_i,
      card_sending_stats: {
        daily_sending_capacity: stats[:daily_sending_capacity].to_i,
        messages_sent_today: stats[:messages_sent_today].to_i,
        messages_sent_previous_sending_day: stats[:messages_sent_previous_sending_day].to_i
      },
      ai_reply_agent_enabled: org.ai_reply_agent_enabled
    }
  end

  def average_per_day(total, days_in_window)
    return 0.0 if days_in_window <= 0

    (total.to_f / days_in_window).round(1)
  end

  def percentage(numerator, denominator)
    return 0.0 if denominator.zero?

    (numerator.to_f / denominator * 100).round(1)
  end

  def serialize_organization_detail(org)
    current_plan = AppSetting.current.billing_plan(org.plan_tier)

    org.as_json(
      only: %i[
        id name industry size onboarded status deactivated_at two_factor_authentication_required
        archived_at
        website calendly_url locale currency created_at
        plan_tier monthly_subscription monthly_meeting_limit billing_cycle_started_on
      ]
    ).merge(
      'active' => org.active?,
      'current_plan' => current_plan&.slice('identifier', 'name', 'monthly_meeting_limit', 'monthly_price')
    )
  end

  def organization_stats(org)
    {
      agents_count: org.agents.not_deleted.count,
      playbooks_count: org.playbooks.count,
      senders_count: org.senders.count,
      mailboxes_count: org.mailboxes.not_deleted.count,
      leads_count: org.leads.count,
      emails_sent_count: GeneratedMessage.joins(agent_lead: :agent)
                                         .where(agents: { organization_id: org.id }, status: 'sent')
                                         .count,
      meetings_count: org.meetings.count
    }
  end

  def recent_activities(org)
    AdminActivity.where(organization_id: org.id)
                 .includes(:account)
                 .order(created_at: :desc)
                 .limit(10)
                 .map do |activity|
      {
        id: activity.id,
        action: activity.action,
        details: activity.details,
        created_at: activity.created_at,
        account: if activity.account
                   {
                     id: activity.account.id,
                     full_name: activity.account.full_name,
                     email: activity.account.email
                   }
                 end
      }
    end
  end
end
