# frozen_string_literal: true

# Customer-facing Meetings Center (AMP-136)
# Provides read-only meeting list with outcome setting for organization users.
class MeetingsController < ApplicationController
  include CustomerLeadModalSerialization

  before_action :set_meeting,
                only: %i[
                  assign mark_completed mark_no_show reschedule set_outcome request_removal lead_modal update_notes
                ]

  PER_PAGE = 25
  CUSTOMER_MANAGEABLE_STATUSES = %w[scheduled scheduling rescheduled].freeze
  LEAD_SEARCH_LIMIT = 20
  LEAD_SEARCH_COLUMNS = %w[email first_name last_name company].freeze
  LEAD_SEARCH_TERM_LIMIT = 16

  def index
    meetings = scoped_meetings.includes(:lead, :agent, :sender, :assigned_to_account).order(created_at: :desc,
                                                                                            scheduled_at: :desc, id: :desc)
    meetings = apply_filters(meetings)

    page = (params[:page] || 1).to_i
    total_count = meetings.count
    total_pages = (total_count.to_f / PER_PAGE).ceil
    meetings = meetings.offset((page - 1) * PER_PAGE).limit(PER_PAGE)

    base_meetings = scoped_meetings
    tab_counts = {
      all: base_meetings.count,
      positive: filtered_meetings_for(base_meetings, 'positive').count,
      neutral: filtered_meetings_for(base_meetings, 'neutral').count,
      scheduling: filtered_meetings_for(base_meetings, 'scheduling').count,
      scheduled: filtered_meetings_for(base_meetings, 'scheduled').count,
      no_show: filtered_meetings_for(base_meetings, 'no_show').count
    }

    render inertia: 'Meetings/Index', props: {
      meetings: serialize_meetings(meetings),
      assignable_users: serialize_assignable_users,
      agents: serialize_agents,
      filters: current_filters,
      tab_counts: tab_counts,
      pagination: {
        current_page: page,
        total_pages: total_pages,
        total_count: total_count,
        per_page: PER_PAGE
      }
    }
  end

  def search_leads
    authorize Meeting, :index?, policy_class: MeetingPolicy

    offset = [params[:offset].to_i, 0].max
    lead_scope = current_organization.leads.includes(:agent_leads).order(:email)
    query = params[:q].to_s.strip[0, 100]

    if query.present?
      conditions, bind_values = lead_search_conditions(query)
      lead_scope = current_organization.leads
                                       .includes(:agent_leads)
                                       .where(
                                         conditions,
                                         bind_values
                                       )
                                       .order(:email)
    end

    leads = lead_scope.offset(offset).limit(LEAD_SEARCH_LIMIT + 1).to_a
    has_more = leads.length > LEAD_SEARCH_LIMIT

    render json: {
      leads: leads.first(LEAD_SEARCH_LIMIT).map { |lead| serialize_lead_option(lead) },
      has_more: has_more
    }, status: :ok
  end

  def create
    authorize Meeting, :create?, policy_class: MeetingPolicy

    agent = policy_scope(Agent).where(organization_id: current_organization.id).find(manual_meeting_params[:agent_id])
    lead = resolve_manual_meeting_lead
    agent_lead = AgentLead.find_or_create_by!(agent: agent, lead: lead)
    scheduled_at = parse_customer_scheduled_at(manual_meeting_params[:scheduled_at])

    meeting = agent_lead.schedule_meeting!(
      scheduled_at: scheduled_at,
      notes: manual_meeting_params[:notes].presence,
      status: scheduled_at.present? ? 'scheduled' : 'scheduling'
    )

    render json: { success: true, meeting: serialize_meeting(meeting.reload) }, status: :created
  rescue ActiveRecord::RecordNotFound
    render json: { success: false, error: 'Lead or agent not found' }, status: :not_found
  rescue ActiveRecord::RecordInvalid => e
    render json: { success: false, error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
  rescue ArgumentError => e
    render json: { success: false, error: e.message }, status: :unprocessable_entity
  end

  def assign
    authorize @meeting, :assign?, policy_class: MeetingPolicy

    assigned_to_account = assignable_account_from_params

    @meeting.assign_to!(assigned_to_account)

    if @meeting.saved_change_to_assigned_to_account_id? && @meeting.assigned_to_account.present?
      MeetingAssignmentMailer.with(
        meeting: @meeting,
        assignee: @meeting.assigned_to_account,
        assigned_by: current_account
      ).assignment_notification.deliver_later
    end

    render json: { success: true, meeting: serialize_meeting(@meeting.reload) }, status: :ok
  rescue ActiveRecord::RecordNotFound
    render json: { success: false, error: 'Assignee not found' }, status: :not_found
  rescue ActiveRecord::RecordInvalid => e
    render json: { success: false, error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
  end

  def set_outcome
    authorize @meeting

    outcome = params[:outcome]
    unless %w[positive neutral no_show].include?(outcome)
      render json: { success: false, error: 'Invalid outcome' }, status: :unprocessable_entity
      return
    end

    unless customer_markable?(@meeting)
      render json: { success: false, error: 'Meeting outcome can only be set after its scheduled time has passed' },
             status: :unprocessable_entity
      return
    end

    case outcome
    when 'positive'
      @meeting.mark_positive!(outcome_notes_text: @meeting.outcome_notes)
    when 'neutral'
      @meeting.mark_neutral!(outcome_notes_text: @meeting.outcome_notes)
    else
      @meeting.mark_no_show!
    end

    render json: { success: true, meeting: serialize_meeting(@meeting.reload) }
  end

  def mark_completed
    authorize @meeting

    unless customer_markable?(@meeting)
      render json: { success: false, error: 'Meeting can only be marked done after its scheduled time has passed' },
             status: :unprocessable_entity
      return
    end

    @meeting.mark_completed!(outcome_value: @meeting.outcome, outcome_notes_text: @meeting.outcome_notes)

    render json: { success: true, meeting: serialize_meeting(@meeting.reload) }, status: :ok
  end

  def mark_no_show
    authorize @meeting

    unless customer_markable?(@meeting)
      render json: { success: false, error: 'Meeting can only be marked no show after its scheduled time has passed' },
             status: :unprocessable_entity
      return
    end

    @meeting.mark_no_show!

    render json: { success: true, meeting: serialize_meeting(@meeting.reload) }, status: :ok
  end

  def reschedule
    authorize @meeting

    new_time = parse_customer_scheduled_at(params[:scheduled_at])
    if new_time.nil?
      render json: { success: false, error: 'Meeting time is invalid' }, status: :unprocessable_entity
      return
    end

    if @meeting.status == 'scheduling'
      @meeting.update!(status: 'scheduled', scheduled_at: new_time)
    elsif @meeting.status.in?(%w[scheduled rescheduled])
      @meeting.reschedule!(new_time)
    else
      @meeting.update!(scheduled_at: new_time)
    end

    render json: { success: true, meeting: serialize_meeting(@meeting.reload) }, status: :ok
  end

  def update_notes
    authorize @meeting, :update_notes?, policy_class: MeetingPolicy

    @meeting.update!(notes: params[:notes].to_s.presence)

    render json: { success: true, meeting: serialize_meeting(@meeting.reload) }, status: :ok
  rescue ActiveRecord::RecordInvalid => e
    render json: { success: false, error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
  end

  def request_removal
    authorize @meeting, :request_removal?, policy_class: MeetingPolicy

    unless @meeting.removal_requestable?
      render json: { success: false, error: 'Meeting cannot be marked for removal from its current status' },
             status: :unprocessable_entity
      return
    end

    @meeting.mark_pending_removal!(comment_body: params[:comment])

    render json: { success: true, meeting: serialize_meeting(@meeting.reload) }, status: :ok
  rescue ActiveRecord::RecordInvalid => e
    render json: { success: false, error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
  end

  def lead_modal
    authorize @meeting, :show?, policy_class: MeetingPolicy

    if @meeting.lead.blank?
      render json: { error: 'Lead not found' }, status: :not_found
      return
    end

    render json: serialize_lead_for_modal(@meeting.lead).merge(
      meeting_declined_comments: serialize_meeting_declined_comments(@meeting)
    )
  end

  private

  def current_organization
    Current.organization
  end

  def scoped_meetings
    policy_scope(Meeting).where(organization_id: current_organization.id)
  end

  def set_meeting
    @meeting = scoped_meetings.find(params[:id])
  end

  def apply_filters(meetings)
    meetings = filtered_meetings_for(meetings, params[:status_filter]) if params[:status_filter].present?

    search_query = params[:search].to_s.strip
    if search_query.present?
      conditions, bind_values = lead_search_conditions(search_query)
      meetings = meetings.joins(:lead).where(
        conditions,
        bind_values
      )
    end

    meetings
  end

  def current_filters
    {
      status_filter: params[:status_filter],
      search: params[:search]
    }
  end

  def serialize_meetings(meetings)
    meetings.map { |m| serialize_meeting(m) }
  end

  def serialize_meeting(meeting)
    {
      id: meeting.id,
      status: meeting.customer_display_status,
      meeting_type: meeting.meeting_type,
      scheduled_at: meeting.scheduled_at,
      duration_minutes: meeting.duration_minutes,
      location: meeting.location,
      notes: meeting.notes,
      outcome: meeting.outcome,
      source: meeting.source,
      created_at: meeting.created_at,
      lead: {
        id: meeting.lead&.id,
        first_name: meeting.lead&.first_name,
        last_name: meeting.lead&.last_name,
        full_name: meeting.lead&.full_name,
        email: meeting.lead&.email,
        job_title: meeting.lead&.job_title,
        company: meeting.lead&.company
      },
      agent: {
        id: meeting.agent&.id,
        name: meeting.agent&.name
      },
      assigned_to_account: serialize_account(meeting.assigned_to_account),
      removal_comment: meeting.removal_comment
    }
  end

  def serialize_account(account)
    return nil unless account

    {
      id: account.id,
      full_name: account.full_name,
      email: account.email,
      role: account.role
    }
  end

  def serialize_assignable_users
    current_organization.all_users.active.where(status: Account.statuses[:verified]).order(:first_name,
                                                                                           :last_name).map do |account|
      serialize_account(account)
    end
  end

  def serialize_agents
    policy_scope(Agent)
      .where(organization_id: current_organization.id)
      .order(:name)
      .map { |agent| { id: agent.id, name: agent.name } }
  end

  def serialize_lead_option(lead)
    {
      id: lead.id,
      first_name: lead.first_name,
      last_name: lead.last_name,
      full_name: lead.full_name,
      email: lead.email,
      job_title: lead.job_title,
      company: lead.company,
      assigned_agent_ids: lead.agent_leads
                              .sort_by { |agent_lead| [agent_lead.created_at || Time.zone.at(0), agent_lead.id || 0] }
                              .map(&:agent_id)
    }
  end

  def lead_search_conditions(value)
    bind_values = {}
    conditions = lead_search_terms(value).each_with_index.flat_map do |term, index|
      bind_key = "term_#{index}".to_sym
      bind_values[bind_key] = "%#{ActiveRecord::Base.sanitize_sql_like(term)}%"

      LEAD_SEARCH_COLUMNS.map { |column| "leads.#{column} ILIKE :#{bind_key}" }
    end

    [conditions.join(' OR '), bind_values]
  end

  def lead_search_terms(value)
    query = value.to_s.strip[0, 100]
    transliterated_query = I18n.transliterate(query)

    ([query, transliterated_query] + german_search_variants(query) + german_search_variants(transliterated_query))
      .map(&:presence)
      .compact
      .uniq
      .first(LEAD_SEARCH_TERM_LIMIT)
  end

  def german_search_variants(value)
    variants = [value.to_s.tr('ß', 'ss'), value.to_s.gsub(/ss/i, 'ß')]

    value.to_s.each_char.reduce(['']) do |current_variants, character|
      options = case character
                when 'a', 'A' then [character, character == 'A' ? 'Ä' : 'ä']
                when 'o', 'O' then [character, character == 'O' ? 'Ö' : 'ö']
                when 'u', 'U' then [character, character == 'U' ? 'Ü' : 'ü']
                else [character]
                end

      current_variants.flat_map { |prefix| options.map { |option| "#{prefix}#{option}" } }
                      .first(LEAD_SEARCH_TERM_LIMIT)
    end + variants
  end

  def serialize_meeting_declined_comments(meeting)
    meeting.meeting_declined_comments.includes(:account).chronological.map do |comment|
      {
        id: comment.id,
        body: comment.body,
        created_at: comment.created_at,
        account: {
          id: comment.account_id,
          full_name: comment.author_name
        }
      }
    end
  end

  def filtered_meetings_for(meetings, filter)
    case filter
    when 'positive'
      meetings.where(status: 'positive').or(meetings.where(status: 'completed', outcome: 'positive'))
    when 'neutral'
      meetings.where(status: 'neutral').or(meetings.where(status: 'completed', outcome: 'neutral'))
    when 'scheduled'
      meetings.where(status: %w[scheduled rescheduled])
    when 'scheduling', 'no_show'
      meetings.where(status: filter)
    else
      meetings
    end
  end

  def customer_markable?(meeting)
    meeting.status.in?(CUSTOMER_MANAGEABLE_STATUSES + %w[completed positive neutral no_show]) &&
      (meeting.scheduled_at.blank? || meeting.scheduled_at <= Time.current || meeting.outcome.present?)
  end

  def parse_customer_scheduled_at(value)
    return if value.blank?

    Time.zone.parse(value.to_s)
  end

  def manual_meeting_params
    params.permit(
      :agent_id,
      :lead_id,
      :scheduled_at,
      :notes,
      lead: %i[name email company role]
    )
  end

  def resolve_manual_meeting_lead
    lead_id = manual_meeting_params[:lead_id].presence
    return current_organization.leads.find(lead_id) if lead_id.present?

    lead_attributes = manual_meeting_params.fetch(:lead, {})
    email = lead_attributes[:email].to_s.strip
    raise ArgumentError, 'Lead email is required' if email.blank?

    Lead.find_or_create_with_person!(
      organization: current_organization,
      email: email,
      attributes: skeleton_lead_attributes(lead_attributes)
    )
  end

  def skeleton_lead_attributes(lead_attributes)
    name_parts = lead_attributes[:name].to_s.strip.split(/\s+/, 2)

    {
      first_name: name_parts[0],
      last_name: name_parts[1],
      full_name: lead_attributes[:name].to_s.strip.presence,
      company: lead_attributes[:company].to_s.strip.presence,
      job_title: lead_attributes[:role].to_s.strip.presence
    }.compact
  end

  def assignable_account_from_params
    assigned_to_account_id = params[:assigned_to_account_id].presence
    return nil if assigned_to_account_id.blank?

    current_organization.all_users.active.where(status: Account.statuses[:verified]).find(assigned_to_account_id)
  end
end
