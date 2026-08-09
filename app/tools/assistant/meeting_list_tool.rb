# frozen_string_literal: true

# Lists and searches meetings for the assistant. Mirrors the filters the Meetings Center UI
# offers (MeetingsController#apply_filters) so the assistant can answer the same questions the
# user could answer on the Meetings page.
module Assistant
  class MeetingListTool < BaseTool
    include MeetingTimeParsing

    DEFAULT_LIMIT = 20
    MAX_LIMIT = 50
    MAX_OFFSET = 1_000

    # Tab-style filters from the Meetings page plus any raw Meeting status for precise queries.
    STATUS_FILTERS = (
      %w[positive neutral scheduling scheduled no_show] + Meeting::STATUSES
    ).uniq.freeze

    description 'Lists and searches meetings in this workspace, newest first. Returns matching ' \
                'rows plus total_count and status_counts. Call this before answering any meeting ' \
                'question — never claim a meeting does not exist without calling this tool first. ' \
                'For one meeting\'s full details use meeting_read. Read-only.'

    param :status,
          desc: "Filter by status or Meetings-page tab. One of: #{STATUS_FILTERS.join(', ')}",
          required: false
    param :search, desc: 'Free-text search over lead first name, last name, email and company',
                   required: false
    param :agent_id, type: :integer,
          desc: 'Filter to one agent. Find ids with agent_list first — never guess an id.',
          required: false
    param :lead_id, type: :integer,
          desc: 'Filter to one lead. Find ids with lead_search first — never guess an id.',
          required: false
    param :scheduled_after,
          desc: 'ISO 8601 date or datetime — only meetings scheduled at or after this moment',
          required: false
    param :scheduled_before,
          desc: 'ISO 8601 date or datetime — only meetings scheduled at or before this moment',
          required: false
    param :upcoming_only, type: :boolean,
          desc: 'Only meetings with a future scheduled_at and in-flight status (scheduling, scheduled, rescheduled)',
          required: false
    param :limit, type: :integer, desc: "Rows to return (default #{DEFAULT_LIMIT}, max #{MAX_LIMIT})",
                  required: false
    param :offset, type: :integer, desc: 'Rows to skip, for paging through more results', required: false

    def execute(status: nil, search: nil, agent_id: nil, lead_id: nil, scheduled_after: nil,
                scheduled_before: nil, upcoming_only: nil, limit: DEFAULT_LIMIT, offset: 0)
      if status.present? && STATUS_FILTERS.exclude?(status.to_s)
        return invalid_enum('status', status, STATUS_FILTERS)
      end

      after = parse_time(scheduled_after)
      return invalid_time('scheduled_after', scheduled_after) if scheduled_after.present? && after.nil?

      before = parse_time(scheduled_before)
      return invalid_time('scheduled_before', scheduled_before) if scheduled_before.present? && before.nil?

      if agent_id.present?
        agent = scoped(Agent).find_by(id: agent_id)
        return { error: 'Agent not found.' } unless agent
      end

      if lead_id.present?
        lead = scoped(Lead).find_by(id: lead_id)
        return { error: 'Lead not found.' } unless lead
      end

      base_scope = scoped(Meeting).includes(:lead, :agent, :assigned_to_account)
      scope = filtered_scope(base_scope, status:, search:, agent_id:, lead_id:, after:, before:,
                             upcoming_only:)

      total = scope.count
      rows = scope.order(created_at: :desc, scheduled_at: :desc, id: :desc)
                  .offset(offset.to_i.clamp(0, MAX_OFFSET))
                  .limit(limit.to_i.clamp(1, MAX_LIMIT))
                  .to_a

      {
        total_count: total,
        returned_count: rows.size,
        status_counts: status_counts(base_scope),
        meetings: serialize(rows)
      }
    end

    private

    def filtered_scope(scope, status:, search:, agent_id:, lead_id:, after:, before:, upcoming_only:)
      scope = apply_status_filter(scope, status.to_s) if status.present?
      scope = scope.where(agent_id: agent_id) if agent_id.present?
      scope = scope.where(lead_id: lead_id) if lead_id.present?
      scope = scope.where(scheduled_at: after..) if after
      scope = scope.where(scheduled_at: ..before) if before
      if upcoming_only
        scope = scope.where(status: IN_FLIGHT_MEETING_STATUSES)
                     .where('scheduled_at > ?', Time.current)
      end
      scope = apply_search(scope, search) if search.present?
      scope
    end

    # Same semantics as MeetingsController#filtered_meetings_for.
    def apply_status_filter(scope, filter)
      case filter
      when 'positive'
        scope.where(status: 'positive').or(scope.where(status: 'completed', outcome: 'positive'))
      when 'neutral'
        scope.where(status: 'neutral').or(scope.where(status: 'completed', outcome: 'neutral'))
      when 'scheduled'
        scope.where(status: %w[scheduled rescheduled])
      when 'scheduling', 'no_show'
        scope.where(status: filter)
      else
        scope.where(status: filter)
      end
    end

    def apply_search(scope, search)
      LeadSearchSql.apply(scope.joins(:lead), search)
    end

    def status_counts(scope)
      rows = scope.group(:status).count
      Meeting::STATUSES.index_with { |status| rows[status].to_i }
    end

    def serialize(rows)
      conversation_ids = conversation_ids_for(rows.map(&:lead_id))

      rows.map do |meeting|
        meeting_json(meeting, conversation_ids[meeting.lead_id])
      end
    end

    def meeting_json(meeting, conversation_id)
      {
        id: meeting.id,
        status: meeting.status,
        display_status: meeting.customer_display_status,
        in_flight: meeting.modifiable? && !meeting.pending_removal?,
        terminal: meeting.terminal?,
        meeting_type: meeting.meeting_type,
        scheduled_at: meeting.scheduled_at&.iso8601,
        duration_minutes: meeting.duration_minutes,
        location: meeting.location,
        notes: meeting.notes&.truncate(500),
        outcome: meeting.outcome,
        source: meeting.source,
        created_at: meeting.created_at.iso8601,
        completed_at: meeting.completed_at&.iso8601,
        cancelled_at: meeting.cancelled_at&.iso8601,
        lead: {
          id: meeting.lead_id,
          name: meeting.lead.display_name,
          email: meeting.lead.email,
          company: meeting.lead.company,
          job_title: meeting.lead.job_title
        },
        agent: {
          id: meeting.agent_id,
          name: meeting.agent.name
        },
        assigned_to: meeting.assigned_to_account&.full_name,
        conversation_id: conversation_id
      }
    end

    def conversation_ids_for(lead_ids)
      return {} if lead_ids.empty?

      scoped(Conversation)
        .visible_in_reply_center
        .where(lead_id: lead_ids.uniq)
        .order(last_reply_at: :desc)
        .pluck(:lead_id, :id)
        .each_with_object({}) do |(lead_id, conversation_id), memo|
          memo[lead_id] ||= conversation_id
        end
    end

    def parse_time(value)
      return nil if value.blank?

      Time.zone.parse(value.to_s)
    rescue ArgumentError
      nil
    end

    def invalid_enum(field, value, allowed)
      { error: "Unknown #{field} '#{value.to_s.truncate(30)}'. Valid values: #{allowed.join(', ')}." }
    end

    def invalid_time(field, value)
      { error: "Could not parse #{field} '#{value.to_s.truncate(30)}'. Use an ISO 8601 date like 2026-08-01." }
    end
  end
end
