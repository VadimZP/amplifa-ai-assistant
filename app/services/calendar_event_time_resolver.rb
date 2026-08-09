# frozen_string_literal: true

require 'time'

class CalendarEventTimeResolver
  ISO_FLOATING_TIME_PATTERN =
    /\A(?<year>\d{4})-(?<month>\d{2})-(?<day>\d{2})T(?<hour>\d{2}):(?<minute>\d{2})(?::(?<second>\d{2})(?:\.\d+)?)?\z/

  def self.resolve(event_data:)
    new(event_data:).resolve
  end

  def initialize(event_data:)
    @event_data = hash_like(event_data)
  end

  def resolve
    start_at = parse_datetime(@event_data[:start_at])
    return {} unless timed_event?(start_at)

    end_at = parse_datetime(@event_data[:end_at]) || default_end_at(start_at)

    {
      'display_start_at' => iso8601_time(start_at),
      'display_end_at' => iso8601_time(end_at)
    }.compact
  rescue ArgumentError, TypeError
    {}
  end

  private

  def timed_event?(value)
    value.present? && value[:kind] != :date
  end

  def parse_datetime(value)
    property = hash_like(value)
    date_time_value = property[:date_time].presence
    return nil if date_time_value.blank?

    return { kind: :date, date: Date.iso8601(date_time_value) } if date_time_value.match?(/\A\d{4}-\d{2}-\d{2}\z/)
    return parse_offset_datetime(date_time_value) if date_time_value.match?(/[zZ]\z|[+-]\d{2}:\d{2}\z/)

    match = date_time_value.match(ISO_FLOATING_TIME_PATTERN)
    return nil unless match

    parts = match.named_captures.transform_values(&:to_i)
    time_zone = resolved_time_zone(property[:time_zone])
    return nil unless time_zone

    {
      kind: :zoned,
      time: time_zone.local(parts['year'], parts['month'], parts['day'], parts['hour'], parts['minute'],
                            parts['second'])
    }
  end

  def parse_offset_datetime(value)
    time = Time.iso8601(value)
    { kind: :utc, time: time.utc }
  rescue ArgumentError
    nil
  end

  def resolved_time_zone(value)
    timezone_name = value.to_s.strip
    return nil if timezone_name.blank?

    normalized_name = CalendarInviteLinkBuilder::WINDOWS_TIME_ZONES[timezone_name] || timezone_name
    ActiveSupport::TimeZone[normalized_name] || Time.find_zone(normalized_name)
  end

  def default_end_at(start_at)
    return nil unless timed_event?(start_at)

    start_at
  end

  def iso8601_time(value)
    value[:time]&.utc&.iso8601
  end

  def hash_like(value)
    return {} unless value.respond_to?(:to_h)

    value.to_h.with_indifferent_access
  end
end
