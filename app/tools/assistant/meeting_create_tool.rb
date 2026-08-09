# frozen_string_literal: true

# Books a meeting with the lead of one conversation — the assistant's counterpart to the manual
# "Add meeting" flow in the Meetings Center. Creation goes through AgentLead#schedule_meeting!,
# the same path MeetingsController#create takes; a lead who already has an active meeting is never
# double-booked (the tool points the model at meeting_reschedule instead).
module Assistant
  class MeetingCreateTool < BaseTool
    include MeetingTimeParsing

    description 'Books a meeting with the lead of one email conversation, as the user could from ' \
                'the Meetings page. Omit scheduled_at to create a meeting that is still being ' \
                'scheduled (no time agreed yet). Fails if the lead already has an active meeting ' \
                '— use meeting_reschedule to move it instead. Use conversation_list first to find ' \
                'the conversation id. Only call this after the user clearly named the lead and, ' \
                'if given, the date and time.'

    param :conversation_id, type: :integer, desc: 'The id of the conversation whose lead to meet',
          required: true
    param :scheduled_at,
          desc: 'Meeting date and time in ISO 8601 with a timezone offset ' \
                '(e.g. 2026-08-12T15:30:00+03:00). Omit when no time has been agreed yet.',
          required: false
    param :notes, desc: 'Optional notes to store on the meeting', required: false

    def execute(conversation_id:, scheduled_at: nil, notes: nil)
      conversation = scoped(Conversation).find_by(id: conversation_id)
      # WHY the same message for foreign and unknown ids: a distinguishable answer would let a
      # caller probe which ids exist in other organizations.
      return { error: 'Conversation not found.' } unless conversation

      authorize!(Meeting, :create?)

      time = nil
      if scheduled_at.present?
        time, time_error = parse_meeting_time(scheduled_at)
        return time_error if time_error
      end

      existing = latest_active_meeting(conversation.lead_id)
      return existing_meeting_payload(existing, time) if existing

      agent_lead = resolve_agent_lead(conversation)
      return { error: 'No matching campaign lead found for this conversation.' } unless agent_lead

      meeting = agent_lead.schedule_meeting!(
        scheduled_at: time,
        notes: notes.presence,
        status: time ? 'scheduled' : 'scheduling'
      )
      success_payload(meeting, conversation)
    end

    private

    # Never creates a duplicate. Same lead + same minute reads as "already booked" so the model
    # tells the user it exists and does nothing; any other active meeting steers the model to
    # meeting_reschedule.
    def existing_meeting_payload(existing, requested_time)
      error = if requested_time && same_minute?(existing.scheduled_at, requested_time)
                'A meeting with this lead at this time already exists.'
              else
                described = existing.scheduled_at ? "for #{existing.scheduled_at.iso8601}" : 'without a time yet'
                "This lead already has an active meeting (status: #{existing.status}, #{described}). " \
                  'Use meeting_reschedule to move it instead of creating a duplicate.'
              end

      { error: error, meeting_id: existing.id, status: existing.status,
        scheduled_at: existing.scheduled_at&.iso8601 }
    end

    # Mirrors ConversationInterestStatusUpdater's fallback: prefer the agent lead of the campaign
    # this conversation belongs to, else any campaign that contacted this lead within the
    # organization, and only create a new pairing when the conversation names an agent (same as
    # the manual Meetings page flow does for its selected agent).
    def resolve_agent_lead(conversation)
      candidates = AgentLead.joins(:agent)
                            .where(lead_id: conversation.lead_id)
                            .where(agents: { organization_id: organization.id })
      agent_lead = (candidates.find_by(agent_id: conversation.agent_id) if conversation.agent_id.present?)
      agent_lead ||= candidates.order(created_at: :desc).first
      return agent_lead if agent_lead
      return nil unless conversation.agent&.organization_id == organization.id

      AgentLead.create!(agent: conversation.agent, lead: conversation.lead)
    end

    def success_payload(meeting, conversation)
      {
        meeting_id: meeting.id,
        lead_name: conversation.lead.display_name,
        company: conversation.lead.company,
        status: meeting.status,
        scheduled_at: meeting.scheduled_at&.iso8601,
        notes: meeting.notes,
        same_day_meeting_count: meeting.scheduled_at ? same_day_meeting_count(meeting.scheduled_at) : nil
      }
    end
  end
end
