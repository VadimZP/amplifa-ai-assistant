# frozen_string_literal: true

module BusinessDayHelper
  VALID_WINDOWS = %w[today yesterday last_7_days].freeze

  class << self
    def yesterday(from:)
      date = from
      # Keep going back one day until we hit a weekday
      loop do
        date -= 1.day
        return date if weekday?(date)
      end
    end

    def last_n_calendar_days_excluding_weekends(n, from:)
      start_date = from - (n - 1).days
      (start_date..from).select { |date| weekday?(date) }
    end

    def date_range_for_window(window, from: Date.current)
      unless VALID_WINDOWS.include?(window)
        raise ArgumentError,
              "Unknown window: #{window.inspect}. Valid windows: #{VALID_WINDOWS.join(', ')}"
      end

      case window
      when 'today'
        [from]
      when 'yesterday'
        [yesterday(from: from)]
      when 'last_7_days'
        last_n_calendar_days_excluding_weekends(7, from: from)
      end
    end

    def add_business_days(from:, days:)
      raise ArgumentError, "days must be non-negative, got #{days}" if days.negative?

      date = normalize_to_weekday(from)
      days.times { date = next_business_day(date) }
      date
    end

    private

    def next_business_day(date)
      date += 1.day
      date += 1.day until weekday?(date)
      date
    end

    def normalize_to_weekday(date)
      return date if weekday?(date)

      normalized = date
      normalized += 1.day until weekday?(normalized)
      normalized
    end

    def weekday?(date)
      date.wday != 0 && date.wday != 6
    end
  end
end
