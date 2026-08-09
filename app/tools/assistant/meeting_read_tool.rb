# frozen_string_literal: true

# Reads one meeting's full details for the assistant. Read-only — use meeting_list first to find
# the meeting id.
module Assistant
  class MeetingReadTool < BaseTool
    NOTES_LENGTH = 2_000
    OUTCOME_NOTES_LENGTH = 1_000

    description 'Reads one meeting: lead, agent, status, scheduled time, notes and outcome. ' \
                'Use meeting_list first to find the meeting id. Read-only.'

    param :meeting_id, type: :integer, desc: 'The id of the meeting to read', required: true

    def execute(meeting_id:)
      meeting = scoped(Meeting).includes(:lead, :agent, :assigned_to_account).find_by(id: meeting_id)
      return { error: 'Meeting not found.' } unless meeting

      authorize!(meeting, :show?)

      conversation_id = conversation_id_for(meeting.lead_id)

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
        notes: meeting.notes&.truncate(NOTES_LENGTH),
        outcome: meeting.outcome,
        outcome_notes: meeting.outcome_notes&.truncate(OUTCOME_NOTES_LENGTH),
        source: meeting.source,
        created_at: meeting.created_at.iso8601,
        completed_at: meeting.completed_at&.iso8601,
        cancelled_at: meeting.cancelled_at&.iso8601,
        removal_comment: meeting.removal_comment,
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
        assigned_to: assigned_to_json(meeting.assigned_to_account),
        conversation_id: conversation_id,
        scheduling_hint: scheduling_hint(meeting, conversation_id)
      }
    end

    private

    def assigned_to_json(account)
      return nil unless account

      {
        id: account.id,
        name: account.full_name,
        email: account.email
      }
    end

    def conversation_id_for(lead_id)
      scoped(Conversation)
        .visible_in_reply_center
        .where(lead_id: lead_id)
        .order(last_reply_at: :desc)
        .pick(:id)
    end

    def scheduling_hint(meeting, conversation_id)
      return nil unless conversation_id

      if meeting.modifiable? && !meeting.pending_removal?
        'Use meeting_reschedule to move this meeting, or meeting_cancel to remove it.'
      elsif meeting.terminal? || meeting.pending_removal?
        'This meeting has ended. Use meeting_create (with this conversation_id) to book a new one.'
      end
    end
  end
end
