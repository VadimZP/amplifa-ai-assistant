class DashboardController < ApplicationController
  BLACKLISTS_PER_PAGE = 10
  MAX_DOMAINS = 5

  def index
    # WHY: Authorize using DashboardPolicy to ensure only authenticated users can access
    authorize :dashboard, :index?

    if current_account.amplifa_admin?
      # WHY: Skip policy scope verification for admins since they are being redirected
      # to the admin dashboard and don't need customer data scoping.
      skip_policy_scope
      redirect_to admin_dashboard_path
    else
      # WHY: Use the selected workspace, not the account's legacy primary organization.
      organization = Current.organization

      # WHY: Redirect workspace-less customers instead of dereferencing a nil organization.
      if organization.nil?
        skip_policy_scope
        redirect_to no_workspace_path
        return
      end

      # WHY: Load all data needed for the customer home page sections
      domains = organization.email_domains.not_deleted
                            .order(created_at: :desc)
      senders = organization.senders
                            .includes(:mailboxes)
                            .order(:first_name, :last_name)
      mailboxes = organization.mailboxes.not_deleted
                              .includes(:email_domain, :sender)
                              .order(:email)
      blacklist_scope = organization.blacklists
                                    .includes(:created_by)
                                    .order(created_at: :desc)
      blacklist_total_entries = blacklist_scope.count

      if params[:blacklist_search].present?
        search_term = "%#{params[:blacklist_search].strip.downcase}%"
        blacklist_scope = blacklist_scope.where('LOWER(blacklists.value) LIKE ?', search_term)
      end

      blacklist_page = [params[:blacklist_page].to_i, 1].max
      blacklist_total_count = blacklist_scope.count
      blacklist_total_pages = (blacklist_total_count.to_f / BLACKLISTS_PER_PAGE).ceil
      blacklists = blacklist_scope.offset((blacklist_page - 1) * BLACKLISTS_PER_PAGE).limit(BLACKLISTS_PER_PAGE)

      render inertia: 'Customer/Home/Index', props: {
        organization: organization.as_json(
          only: %i[id name website industry average_contract_value status onboarded]
        ),
        domains: domains.map { |d| serialize_domain(d) },
        domains_count: domains.count,
        max_domains: MAX_DOMAINS,
        senders: senders.map { |s| serialize_sender(s) },
        mailboxes: mailboxes.map { |m| serialize_mailbox(m) },
        blacklists: serialize_blacklists(blacklists),
        blacklist_count: blacklist_total_count,
        blacklist_total_entries: blacklist_total_entries,
        blacklist_filters: {
          search: params[:blacklist_search].to_s
        },
        blacklist_pagination: {
          current_page: blacklist_page,
          total_pages: blacklist_total_pages,
          total_count: blacklist_total_count,
          per_page: BLACKLISTS_PER_PAGE
        },
        can_edit: Current.organization_membership&.customer_admin? || false,
        user_count: policy_scope(Account).count
      }
    end
  end

  private

  def serialize_domain(domain)
    {
      id: domain.id,
      domain: domain.domain,
      provider_type: domain.provider_type,
      status: domain.status,
      customer_requested: domain.customer_requested,
      last_verified_at: domain.last_verified_at&.iso8601,
      mailbox_count: domain.mailboxes.not_deleted.count
    }
  end

  def serialize_sender(sender)
    {
      id: sender.id,
      first_name: sender.first_name,
      last_name: sender.last_name,
      full_name: sender.full_name,
      email: sender.email,
      job_title: sender.job_title,
      status: sender.status,
      mailbox_count: sender.mailboxes.not_deleted.count,
      active_mailbox_count: sender.mailboxes.not_deleted.select(&:active?).count,
      mailboxes: sender.mailboxes.not_deleted.map do |m|
        { id: m.id, email: m.email, status: m.status }
      end
    }
  end

  def serialize_mailbox(mailbox)
    {
      id: mailbox.id,
      email: mailbox.email,
      status: mailbox.status,
      daily_send_limit: mailbox.daily_send_limit,
      domain: mailbox.email_domain&.domain,
      sender_name: mailbox.sender&.full_name,
      warmup_complete: mailbox.warmup_complete?,
      warmup_progress: mailbox.warmup_progress_percentage
    }
  end

  def serialize_blacklists(blacklists)
    blacklists.map do |bl|
      {
        id: bl.id,
        value: bl.value,
        value_type: bl.value_type,
        source: bl.source,
        reason: bl.reason,
        is_global: bl.global?,
        can_delete: !bl.global? && (Current.organization_membership&.customer_admin? || false),
        created_at: bl.created_at.iso8601,
        created_by: bl.created_by&.full_name
      }
    end
  end
end
