# frozen_string_literal: true

# Moves the active meeting of one conversation's lead to a new time — the assistant's counterpart
# to the Reschedule action in the Meetings Center, with the same status semantics as
# MeetingsController#reschedule: setting the first concrete time on a 'scheduling' meeting books
# it, while moving an already-booked one marks it rescheduled.
module Assistant
  class MeetingRescheduleTool < BaseTool
    include MeetingTimeParsing

    RESCHEDULABLE_STATUSES = %w[scheduling scheduled rescheduled].freeze

    description 'Moves the active meeting with the lead of one email conversation to a new date ' \
                'and time. Also sets the time of a meeting that was still being scheduled. Use ' \
                'conversation_list first to find the conversation id. Only call this after the ' \
                'user clearly named the lead and the new date and time.'

    param :conversation_id, type: :integer,
          desc: 'The id of the conversation whose lead\'s meeting to move', required: true
    param :scheduled_at,
          desc: 'New meeting date and time in ISO 8601 with a timezone offset ' \
                '(e.g. 2026-08-12T15:30:00+03:00)',
          required: true

    def execute(conversation_id:, scheduled_at:)
      conversation = scoped(Conversation).find_by(id: conversation_id)
      # WHY the same message for foreign and unknown ids: a distinguishable answer would let a
      # caller probe which ids exist in other organizations.
      return { error: 'Conversation not found.' } unless conversation

      meeting = latest_active_meeting(conversation.lead_id)
      return { error: 'This lead has no active meeting. Use meeting_create to schedule one.' } unless meeting

      authorize!(meeting, :reschedule?)

      time, time_error = parse_meeting_time(scheduled_at)
      return time_error if time_error

      if same_minute?(meeting.scheduled_at, time)
        return { error: 'The meeting is already scheduled at this time.',
                 meeting_id: meeting.id, scheduled_at: meeting.scheduled_at.iso8601 }
      end

      unless RESCHEDULABLE_STATUSES.include?(meeting.status)
        return { error: "This meeting is already #{meeting.status} and can no longer be rescheduled." }
      end

      previous_status = meeting.status
      previous_scheduled_at = meeting.scheduled_at

      if meeting.status == 'scheduling'
        meeting.update!(status: 'scheduled', scheduled_at: time)
      else
        meeting.reschedule!(time)
      end

      success_payload(meeting, conversation, previous_status, previous_scheduled_at)
    end

    private

    def success_payload(meeting, conversation, previous_status, previous_scheduled_at)
      {
        meeting_id: meeting.id,
        lead_name: conversation.lead.display_name,
        company: conversation.lead.company,
        previous_status: previous_status,
        status: meeting.status,
        previous_scheduled_at: previous_scheduled_at&.iso8601,
        scheduled_at: meeting.scheduled_at.iso8601,
        same_day_meeting_count: same_day_meeting_count(meeting.scheduled_at)
      }
    end
  end
end
