# frozen_string_literal: true

# Shared helpers for the meeting scheduling tools (meeting_create, meeting_reschedule): strict
# date/time validation plus the lead/day meeting lookups both tools need.
#
# WHY strict Time.iso8601 instead of the controllers' Time.zone.parse: tool arguments come from
# the model, and a lenient parser silently turns garbage like "222:00" or a mistyped year into a
# real (wrong) date. Time.iso8601 raises on impossible components, so the tool can hand the model
# a structured correction hint instead of booking a meeting at a time nobody asked for.
module Assistant
  module MeetingTimeParsing
    EXPECTED_TIME_FORMAT = 'ISO 8601 with a timezone offset, e.g. 2026-08-12T15:30:00+03:00'

    # Guards against a mis-parsed year (e.g. "20260812") producing a meeting centuries away.
    MAX_SCHEDULING_HORIZON = 2.years

    ACTIVE_MEETING_EXCLUDED_STATUSES = %w[cancelled pending_removal].freeze

    # Only meetings still in the scheduling pipeline block new bookings or cancel/reschedule.
    # Terminal outcomes (no_show, completed, positive, neutral) are historical — use
    # meeting_create to book again instead of meeting_reschedule.
    IN_FLIGHT_MEETING_STATUSES = %w[scheduling scheduled rescheduled].freeze

    private

    # Returns [time, nil] on success or [nil, error_payload] on failure. The payload carries the
    # expected format and the raw value so the model can propose a correction to the user.
    def parse_meeting_time(raw)
      time = begin
        Time.iso8601(raw.to_s.strip)
      rescue ArgumentError
        return [nil, invalid_time(raw, 'The requested date/time is invalid.')]
      end

      if time <= Time.current
        return [nil, invalid_time(raw, 'That time is in the past — meetings must be scheduled for a future time.')]
      end
      if time > MAX_SCHEDULING_HORIZON.from_now
        return [nil, invalid_time(raw, 'That date is more than 2 years ahead — double-check the year.')]
      end

      [time, nil]
    end

    def invalid_time(raw, message)
      { error: message, expected_format: EXPECTED_TIME_FORMAT, received: raw.to_s.truncate(50) }
    end

    # Minute precision: seconds/fractions never come from a real scheduling request, so two times
    # in the same minute mean "the same meeting time" to the user.
    def same_minute?(first, second)
      first.present? && second.present? && first.change(sec: 0) == second.change(sec: 0)
    end

    def latest_active_meeting(lead_id)
      Meeting.where(organization_id: organization.id, lead_id: lead_id)
             .where(status: IN_FLIGHT_MEETING_STATUSES)
             .order(created_at: :desc)
             .first
    end

    # Day boundaries follow the offset the user supplied in scheduled_at, so "that day" means the
    # user's day, not the server's.
    def same_day_meeting_count(time)
      Meeting.where(organization_id: organization.id)
             .where.not(status: ACTIVE_MEETING_EXCLUDED_STATUSES)
             .where(scheduled_at: time.all_day)
             .count
    end
  end
end
