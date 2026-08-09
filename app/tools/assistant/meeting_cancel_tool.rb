# frozen_string_literal: true

# Cancels the active meeting of one conversation's lead WITHOUT touching the conversation's
# interest status — a lead can stay interested while a specific meeting falls through. Removal
# semantics mirror ConversationInterestStatusUpdater#remove_associated_meeting! (the interest-status
# side-effect path): an amplifa admin deletes the meeting outright, a customer marks it
# pending_removal — the same "Request removal" flow the Meetings Center offers.
module Assistant
  class MeetingCancelTool < BaseTool
    include MeetingTimeParsing

    description 'Cancels the active meeting with the lead of one email conversation. Does NOT ' \
                'change the conversation\'s interest status — use this when the user wants the ' \
                'meeting gone but the lead may still be interested. Use conversation_list first ' \
                'to find the conversation id. Only call this after the user clearly named the lead.'

    param :conversation_id, type: :integer,
          desc: 'The id of the conversation whose lead\'s meeting to cancel', required: true
    param :comment, desc: 'Optional short reason for the cancellation, stored on the meeting',
          required: false

    def execute(conversation_id:, comment: nil)
      conversation = scoped(Conversation).find_by(id: conversation_id)
      # WHY the same message for foreign and unknown ids: a distinguishable answer would let a
      # caller probe which ids exist in other organizations.
      return { error: 'Conversation not found.' } unless conversation

      meeting = latest_active_meeting(conversation.lead_id)
      return { error: 'This lead has no active meeting to cancel.' } unless meeting

      authorize!(meeting, :request_removal?)

      unless meeting.removal_requestable?
        return { error: "This meeting is already #{meeting.status} and can no longer be cancelled." }
      end

      payload = success_payload(meeting, conversation)
      ActiveRecord::Base.transaction { remove_meeting!(meeting, comment) }
      payload
    end

    private

    # Same actor split as ConversationInterestStatusUpdater: customers cannot hard-delete a
    # meeting (MeetingPolicy#cancel? is admin-only), so their cancellation becomes a removal
    # request for an admin to confirm; the agent_lead booking marker is cleared either way once
    # no active meeting remains.
    def remove_meeting!(meeting, comment)
      agent_lead = meeting.agent_lead

      if account.amplifa_admin?
        meeting.destroy!
      else
        meeting.mark_pending_removal!(comment_body: comment)
      end

      return unless agent_lead.meetings.where.not(status: ACTIVE_MEETING_EXCLUDED_STATUSES).none?

      agent_lead.update!(meeting_booked_at: nil, meeting_notes: nil)
    end

    def success_payload(meeting, conversation)
      {
        meeting_id: meeting.id,
        lead_name: conversation.lead.display_name,
        company: conversation.lead.company,
        previous_status: meeting.status,
        scheduled_at: meeting.scheduled_at&.iso8601,
        removal: account.amplifa_admin? ? 'deleted' : 'pending_removal',
        interest_status: conversation.interest_status
      }
    end
  end
end
