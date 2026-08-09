# frozen_string_literal: true

require 'csv'

# Customer interface for viewing agents (campaigns) - READ-ONLY access
# Customers can see their organization's agents and campaign statistics
# but cannot create, update, or delete agents (admin-only operations)
# Week 5 adds sample message review and approval functionality
class Customer::AgentsController < ApplicationController
  include CustomerLeadModalSerialization

  before_action :ensure_customer
  before_action :set_agent, only: %i[show pause_campaign resume_campaign]
  before_action :set_modal_lead, only: %i[lead_modal update_interest_status open_reply_conversation]
  before_action :set_modal_company, only: %i[company_modal]

  PER_PAGE = 25
  DEFAULT_STATUS_SORT_SQL = "CASE WHEN agent_leads.delivery_status = 'in_sequence' THEN 0 ELSE 1 END"
  ENRICHMENT_SCORE_SQL = <<~SQL.squish.freeze
    (
      (CASE WHEN people.linkedin_scraped_at IS NOT NULL THEN 1 ELSE 0 END) +
      (CASE WHEN people.disc_profile_assessed_at IS NOT NULL THEN 1 ELSE 0 END) +
      (CASE WHEN people.company_website_scraped_at IS NOT NULL THEN 1 ELSE 0 END) +
      (CASE WHEN people.linkedin_posts_scraped_at IS NOT NULL THEN 1 ELSE 0 END)
    )
  SQL
  ENRICHMENT_SORT_SQL = "#{ENRICHMENT_SCORE_SQL} DESC".freeze

  def index
    filtered_agent_leads = filtered_agent_leads_scope
    status_counts = filtered_agent_leads_scope(include_status: false).group(:delivery_status).count
    total_count = filtered_agent_leads.count

    agent_leads = filtered_agent_leads
                  .includes(:agent, :assigned_mailbox,
                            generated_messages: [], lead: :person)
                  .left_joins(lead: :person)

    has_in_sequence_leads = status_counts['in_sequence'].to_i.positive?
    agent_leads = if has_in_sequence_leads
                    agent_leads.order(Arel.sql(DEFAULT_STATUS_SORT_SQL), created_at: :desc)
                  else
                    agent_leads.order(Arel.sql(ENRICHMENT_SORT_SQL), created_at: :desc)
                  end

    page = (params[:page] || 1).to_i
    total_pages = (total_count.to_f / PER_PAGE).ceil
    agent_leads = agent_leads.offset((page - 1) * PER_PAGE).limit(PER_PAGE)

    agents = policy_scope(Agent).includes(:playbook).order(:name).map do |agent|
      {
        id: agent.id,
        name: agent.name,
        playbook_id: agent.playbook_id,
        status: agent.status,
        playbook_approved: agent.playbook&.approved? || false
      }
    end

    render inertia: 'Customer/Agents/Index', props: {
      can_manage_campaigns: Current.organization_membership&.customer_admin? || false,
      agent_leads: serialize_agent_leads(agent_leads),
      agents: agents,
      downloadable_agents: serialize_downloadable_agents(policy_scope(Agent).order(:name)),
      status_options: AgentLead::DELIVERY_STATUSES,
      status_counts: status_counts,
      sent_today_count: sent_today_count,
      filters: {
        agent_id: params[:agent_id],
        status: params[:status],
        search: params[:search]
      },
      pagination: {
        current_page: page,
        total_pages: total_pages,
        total_count: total_count,
        per_page: PER_PAGE
      }
    }
  end

  def companies
    authorize AgentLead, :index?

    filtered_scope = filtered_company_agent_leads_scope
    status_counts = company_status_counts
    company_ids = filtered_scope.distinct.pluck('people.current_company_id')
    total_count = company_ids.size

    page = (params[:page] || 1).to_i
    total_pages = (total_count.to_f / PER_PAGE).ceil
    companies = Company
                .where(id: company_ids)
                .order(:name)
                .offset((page - 1) * PER_PAGE)
                .limit(PER_PAGE)

    agents = policy_scope(Agent).includes(:playbook).order(:name).map do |agent|
      {
        id: agent.id,
        name: agent.name,
        playbook_id: agent.playbook_id,
        status: agent.status,
        playbook_approved: agent.playbook&.approved? || false
      }
    end

    render inertia: 'Customer/Agents/Companies', props: {
      companies: serialize_company_rows(companies, filtered_scope),
      agents: agents,
      status_options: AgentLead::DELIVERY_STATUSES,
      status_counts: status_counts,
      filters: {
        agent_id: params[:agent_id],
        status: params[:status],
        search: params[:search]
      },
      pagination: {
        current_page: page,
        total_pages: total_pages,
        total_count: total_count,
        per_page: PER_PAGE
      }
    }
  end

  def company_modal
    authorize AgentLead, :index?

    render json: serialize_company_for_modal(@modal_company)
  end

  def lead_modal
    authorize @modal_lead, :show?

    render json: serialize_lead_for_modal(@modal_lead)
  end

  def update_interest_status
    authorize @modal_lead, :show?

    conversation = resolve_modal_conversation_for_interest_update
    result = ConversationInterestStatusUpdater.new(
      conversation: conversation,
      target_status: params[:interest_status],
      actor: current_account,
      reason_context: :manual
    ).call

    if result.success?
      render json: {
        success: true,
        conversation_id: conversation.id,
        interest_status: conversation.reload.interest_status,
        mailbox: {
          id: conversation.mailbox.id,
          email: conversation.mailbox.email
        }
      }, status: :ok
    else
      render json: { error: result.error }, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Lead context not found' }, status: :not_found
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def open_reply_conversation
    authorize @modal_lead, :show?

    conversation = resolve_modal_conversation_for_interest_update(require_matching_mailbox: false)
    inherit_modal_lead_interest_status!(conversation)
    return_to = sanitized_return_to_path

    render json: {
      success: true,
      conversation_id: conversation.id,
      redirect_url: replies_path(selected_id: conversation.id, compose: 1, return_to: return_to)
    }, status: :ok
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Lead context not found' }, status: :not_found
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def show
    authorize @agent

    # Paginate leads for this agent
    leads_page = (params[:leads_page] || 1).to_i
    leads_per_page = 25
    leads = visible_leads_for(@agent).includes(:organization).order(created_at: :desc)
    leads_total_count = leads.count
    leads_total_pages = (leads_total_count.to_f / leads_per_page).ceil
    leads = leads.offset((leads_page - 1) * leads_per_page).limit(leads_per_page)

    render inertia: 'Customer/Agents/Show', props: {
      agent: serialize_agent_full(@agent),
      leads: serialize_leads(leads),
      leads_pagination: {
        current_page: leads_page,
        total_pages: leads_total_pages,
        total_count: leads_total_count,
        per_page: leads_per_page
      },
      mailboxes: serialize_mailboxes(@agent.mailboxes)
    }
  end

  def download
    authorize Agent, :index?

    agent = policy_scope(Agent).find_by(id: params[:agent_id])
    return head :not_found unless agent

    authorize agent, :show?

    csv_data = CSV.generate do |csv|
      csv << ColumnMappingService::MAPPABLE_FIELDS

      agent.leads.visible_in_customer_agents.order(:email).each do |lead|
        csv << [
          lead.email,
          lead.first_name,
          lead.last_name,
          lead.full_name,
          lead.job_title,
          lead.company,
          lead.company_website,
          lead.linkedin_url,
          lead.location
        ]
      end
    end

    filename = "#{agent.name.parameterize.presence || 'agent'}_leads_#{Date.current.iso8601}.csv"

    send_data(
      csv_data,
      type: 'text/csv; charset=utf-8',
      disposition: 'attachment',
      filename: filename
    )
  end

  def pause_campaign
    authorize @agent, :pause_campaign?

    unless @agent.can_pause?
      redirect_to customer_agents_path(agent_id: @agent.id), alert: t('customer.agents.campaign_controls.cannot_pause')
      return
    end

    @agent.pause!

    redirect_to customer_agents_path(agent_id: @agent.id), notice: t('customer.agents.campaign_controls.pause_success')
  end

  def resume_campaign
    authorize @agent, :resume_campaign?

    unless @agent.can_resume?
      redirect_to customer_agents_path(agent_id: @agent.id), alert: t('customer.agents.campaign_controls.cannot_resume')
      return
    end

    @agent.resume!

    redirect_to customer_agents_path(agent_id: @agent.id), notice: t('customer.agents.campaign_controls.resume_success')
  end

  private

  def sent_today_count
    policy_scope(GeneratedMessage)
      .where(status: %w[sent replied bounced])
      .where(sent_at: Time.current.beginning_of_day..Time.current.end_of_day)
      .count
  end

  def set_agent
    @agent = policy_scope(Agent).find_by(id: params[:id])
    return if @agent

    render json: { error: 'Agent not found' }, status: :not_found
  end

  def set_modal_lead
    @modal_lead = visible_leads_scope.find_by(id: params[:id])
    return if @modal_lead

    render json: { error: 'Lead not found' }, status: :not_found
  end

  def set_modal_company
    @modal_company = Company.find_by(id: params[:id])
    visible = @modal_company &&
              base_company_agent_leads_scope.where(people: { current_company_id: @modal_company.id }).exists?
    return if visible

    render json: { error: 'Company not found' }, status: :not_found
  end

  def ensure_customer
    return unless current_account.amplifa_admin?

    redirect_to admin_agents_path
  end

  def serialize_agents(agents)
    agents.map do |agent|
      agent.as_json(
        only: %i[id name status total_leads_count contacted_count replied_count
                 meetings_booked_count created_at],
        include: {
          organization: { only: %i[id name] }
        },
        methods: %i[reply_rate meeting_rate samples_generated? launched?]
      ).merge(
        'playbook' => serialize_agent_playbook(agent.playbook)
      )
    end
  end

  def serialize_agent_leads(agent_leads)
    agent_leads.map do |al|
      sent_messages = al.generated_messages.select { |m| m.status == 'sent' }
      replied_message = al.generated_messages.find { |m| m.replied_at.present? }

      {
        id: al.id,
        delivery_status: al.delivery_status,
        sequence_position: al.sequence_position,
        total_messages_sent: sent_messages.count,
        last_sent_at: al.last_sent_at,
        next_send_at: al.next_send_at,
        replied_at: replied_message&.replied_at,
        meeting_booked_at: al.meeting_booked_at,
        **out_of_office_props(al),
        created_at: al.created_at,
        agent: {
          id: al.agent.id,
          name: al.agent.name,
          playbook_id: al.agent.playbook_id
        },
        buying_signals_relevance_rating: nil,
        lead: {
          id: al.lead.id,
          email: al.lead.email,
          first_name: al.lead.first_name,
          last_name: al.lead.last_name,
          full_name: al.lead.full_name,
          display_name: al.lead.display_name,
          company: al.lead.company,
          job_title: al.lead.job_title,
          blacklisted: al.lead.blacklisted,
          blacklist_reason_category: al.lead.blacklist_reason_category,
          interest_tag: customer_interest_tag_for(al.lead)
        },
        assigned_mailbox: if al.assigned_mailbox
                            {
                              id: al.assigned_mailbox.id,
                              email: al.assigned_mailbox.email
                            }
                          end
      }
    end
  end

  def out_of_office_props(agent_lead)
    return_date = agent_lead.lead.out_of_office_return_date
    {
      ooo_return_date: return_date,
      currently_out_of_office: return_date.present? && return_date >= Date.current,
      out_of_office_return_date: return_date
    }
  end

  def serialize_company_rows(companies, filtered_scope)
    company_ids = companies.map(&:id)
    agent_leads_by_company_id = filtered_scope
                                .where(people: { current_company_id: company_ids })
                                .includes(:agent, lead: :person)
                                 .to_a
                                 .group_by { |agent_lead| agent_lead.lead.person.current_company_id }
    companies.map do |company|
      agent_leads = agent_leads_by_company_id[company.id] || []
      unique_leads = agent_leads.map(&:lead).uniq(&:id)
      unique_agents = agent_leads.map(&:agent).uniq(&:id).sort_by(&:name)
      delivery_statuses = agent_leads.map(&:delivery_status).uniq.sort_by do |status|
        AgentLead::DELIVERY_STATUSES.index(status) || AgentLead::DELIVERY_STATUSES.length
      end

      {
        id: company.id,
        name: company.name,
        domain: company.domain,
        website_url: company.website_url,
        summary_available: false,
        leads_count: unique_leads.size,
        agents: unique_agents.map do |agent|
          {
            id: agent.id,
            name: agent.name,
            playbook_id: agent.playbook_id,
            status: agent.status
          }
        end,
        buying_signals_relevance_rating: nil,
        delivery_statuses: delivery_statuses,
        latest_activity_at: agent_leads.filter_map(&:last_sent_at).max,
        created_at: agent_leads.map(&:created_at).compact.min
      }
    end
  end

  def serialize_company_for_modal(company)
    agent_leads = base_company_agent_leads_scope
                  .where(people: { current_company_id: company.id })
                  .includes(:agent, lead: :person)
                  .to_a

    agents = agent_leads.map(&:agent).uniq(&:id).sort_by(&:name)

    {
      id: company.id,
      name: company.name,
      domain: company.domain,
      website_url: company.website_url,
      summary: nil,
      summary_generated_at: nil,
      leads: serialize_company_modal_leads(agent_leads),
      buying_signals_summaries: agents.map do |agent|
        {
          agent: {
            id: agent.id,
            name: agent.name,
            playbook_id: agent.playbook_id,
            status: agent.status
          },
          status: nil,
          markdown: '',
          highlights: [],
          relevance_rating: nil,
          generated_at: nil
        }
      end
    }
  end

  def serialize_company_modal_leads(agent_leads)
    agent_leads
      .map(&:lead)
      .uniq(&:id)
      .sort_by { |lead| lead.display_name.to_s.downcase }
      .map do |lead|
        lead_agent_leads = agent_leads.select { |agent_lead| agent_lead.lead_id == lead.id }
        {
          id: lead.id,
          email: lead.email,
          display_name: lead.display_name,
          job_title: lead.job_title,
          company: lead.company,
          linkedin_url: lead.linkedin_url,
          location: lead.location,
          blacklisted: lead.blacklisted,
          interest_tag: customer_interest_tag_for(lead),
          agents: lead_agent_leads.map do |agent_lead|
            {
              id: agent_lead.agent.id,
              name: agent_lead.agent.name,
              playbook_id: agent_lead.agent.playbook_id,
              delivery_status: agent_lead.delivery_status,
              last_sent_at: agent_lead.last_sent_at
            }
          end
        }
      end
  end

  def serialize_agent_full(agent)
    agent.as_json(
      only: %i[id name description status total_leads_count contacted_count
               replied_count meetings_booked_count created_at updated_at
               sample_count samples_generated_at samples_approved_at default_timezone],
      include: {
        organization: { only: %i[id name] },
        created_by: { only: %i[id first_name last_name], methods: [:full_name] },
        samples_approved_by: { only: %i[id first_name last_name], methods: [:full_name] }
      },
      methods: %i[reply_rate meeting_rate can_launch? samples_generated? samples_approved?]
    ).merge(
      'playbook' => serialize_agent_playbook(agent.playbook)
    ).merge(agent_delivery_stats(agent))
  end

  def agent_delivery_stats(agent)
    messages = agent.generated_messages.where(status: %w[sent bounced replied])
    sent_count = messages.count
    replies_count = messages.where(status: 'replied').count
    meetings_count = agent.meetings_count

    {
      'contacted_count' => sent_count,
      'replied_count' => replies_count,
      'meetings_booked_count' => meetings_count,
      'reply_rate' => sent_count.zero? ? 0.0 : (replies_count.to_f / sent_count * 100).round(1),
      'meeting_rate' => sent_count.zero? ? 0.0 : (meetings_count.to_f / sent_count * 100).round(1)
    }
  end

  def serialize_leads(leads)
    leads.as_json(
      only: %i[id email first_name last_name full_name job_title
               company blacklisted created_at],
      methods: [:display_name]
    )
  end

  def serialize_mailboxes(mailboxes)
    mailboxes.as_json(
      only: %i[id email display_name status daily_send_limit],
      methods: %i[warmup_days_remaining warmup_complete? warmup_progress_percentage]
    )
  end

  def customer_interest_tag_for(lead)
    case lead.blacklist_reason_category
    when 'reply_interested'
      meeting_request_reasons = [
        Blacklist.reply_interest_reason('meeting_request'),
        Blacklist.reply_interest_reason('meeting_request', manual: true)
      ]
      return 'meeting_request' if lead.blacklist_reason.in?(meeting_request_reasons)

      'interested'
    when 'reply_not_interested'
      'not_interested'
    when 'reply_wrong_person'
      'wrong_person'
    end
  end

  def inherit_modal_lead_interest_status!(conversation)
    return if conversation.interest_status.present?

    inherited_status = customer_interest_tag_for(@modal_lead)
    return if inherited_status.blank?

    conversation.update!(interest_status: inherited_status)
  end

  def serialize_downloadable_agents(agents)
    agents.map do |agent|
      {
        id: agent.id,
        name: agent.name
      }
    end
  end

  def serialize_agent_playbook(playbook)
    return nil unless playbook

    {
      'id' => playbook.id,
      'product_name' => playbook.product_name
    }
  end

  def filtered_agent_leads_scope(include_status: true)
    scope = policy_scope(AgentLead)
            .joins(:agent)
            .merge(Agent.not_deleted)
            .joins(:lead)
            .merge(Lead.visible_in_customer_agents)

    scope = scope.where(agent_id: params[:agent_id]) if params[:agent_id].present?
    scope = scope.where(delivery_status: params[:status]) if include_status && params[:status].present?
    apply_lead_search(scope)
  end

  def base_company_agent_leads_scope
    policy_scope(AgentLead)
      .joins(:agent)
      .merge(Agent.not_deleted)
      .joins(lead: { person: :current_company })
      .merge(Lead.visible_in_customer_agents)
      .where.not(people: { current_company_id: nil })
  end

  def filtered_company_agent_leads_scope(include_status: true)
    scope = base_company_agent_leads_scope
    scope = scope.where(agent_id: params[:agent_id]) if params[:agent_id].present?
    scope = scope.where(delivery_status: params[:status]) if include_status && params[:status].present?
    apply_company_search(scope)
  end

  def company_status_counts
    filtered_company_agent_leads_scope(include_status: false)
      .group(:delivery_status)
      .distinct
      .count('people.current_company_id')
  end

  def apply_company_search(scope)
    return scope unless params[:search].present?

    search_term = "%#{params[:search]}%"
    scope.where(
      'companies.name ILIKE :q OR companies.domain ILIKE :q OR companies.website_url ILIKE :q OR ' \
      'leads.email ILIKE :q OR leads.first_name ILIKE :q OR leads.last_name ILIKE :q',
      q: search_term
    )
  end

  def apply_lead_search(scope)
    return scope unless params[:search].present?

    search_term = "%#{params[:search]}%"
    scope.where(
      'leads.email ILIKE :q OR leads.first_name ILIKE :q OR leads.last_name ILIKE :q OR leads.company ILIKE :q',
      q: search_term
    )
  end

  def visible_leads_scope
    policy_scope(Lead).visible_in_customer_agents
  end

  def visible_leads_for(agent)
    agent.leads.visible_in_customer_agents
  end

  def resolve_modal_conversation_for_interest_update(require_matching_mailbox: true)
    if params[:agent_lead_id].present?
      agent_lead = policy_scope(AgentLead)
                   .includes(:assigned_mailbox, :generated_messages, agent: :mailboxes)
                   .find_by!(id: params[:agent_lead_id], lead_id: @modal_lead.id)
      mailbox = mailbox_for_manual_interest(agent_lead)

      if params[:conversation_id].present?
        conversation = policy_scope(Conversation).find_by!(id: params[:conversation_id], lead_id: @modal_lead.id)
        if require_matching_mailbox && mailbox.present? && conversation.mailbox_id != mailbox.id
          raise ArgumentError, 'Selected campaign does not match the existing conversation mailbox.'
        end

        return conversation
      end

      raise ArgumentError, 'No mailbox available for this lead.' if mailbox.blank?

      return ConversationService.find_or_create_for_lead_and_mailbox(
        lead: @modal_lead,
        mailbox: mailbox,
        agent: agent_lead.agent
      )
    end

    policy_scope(Conversation).find_by!(id: params[:conversation_id], lead_id: @modal_lead.id)
  end

  def mailbox_for_manual_interest(agent_lead)
    return agent_lead.assigned_mailbox if agent_lead.assigned_mailbox.present?

    generated_message_mailbox = agent_lead.generated_messages
                                          .select { |message| message.mailbox.present? }
                                          .max_by do |message|
      [message.sent_at || Time.at(0),
       message.created_at || Time.at(0), message.id]
    end
                                          &.mailbox
    return generated_message_mailbox if generated_message_mailbox.present?

    agent_lead.agent.mailboxes.active.order(:id).first
  end

  def sanitized_return_to_path
    value = params[:return_to].to_s
    return nil if value.blank?
    return nil unless value.start_with?('/')

    value
  end
end
