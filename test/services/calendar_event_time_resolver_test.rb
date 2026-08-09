# frozen_string_literal: true

require 'test_helper'

class CalendarEventTimeResolverTest < ActiveSupport::TestCase
  test 'resolves microsoft floating event times into utc instants' do
    result = CalendarEventTimeResolver.resolve(
      event_data: {
        start_at: {
          date_time: '2025-01-03T15:00:00.0000000',
          time_zone: 'Pacific Standard Time'
        },
        end_at: {
          date_time: '2025-01-03T15:30:00.0000000',
          time_zone: 'Pacific Standard Time'
        }
      }
    )

    assert_equal '2025-01-03T23:00:00Z', result['display_start_at']
    assert_equal '2025-01-03T23:30:00Z', result['display_end_at']
  end

  test 'returns empty hash when timezone is unavailable' do
    result = CalendarEventTimeResolver.resolve(
      event_data: {
        start_at: {
          date_time: '2025-01-03T15:00:00.0000000',
          time_zone: nil
        }
      }
    )

    assert_equal({}, result)
  end

  test 'returns empty hash for malformed event data' do
    result = CalendarEventTimeResolver.resolve(
      event_data: {
        start_at: 'bad'
      }
    )

    assert_equal({}, result)
  end

  test 'uses zero-duration fallback when end_at is missing' do
    result = CalendarEventTimeResolver.resolve(
      event_data: {
        start_at: {
          date_time: '2025-01-03T15:00:00.0000000',
          time_zone: 'Pacific Standard Time'
        }
      }
    )

    assert_equal '2025-01-03T23:00:00Z', result['display_start_at']
    assert_equal '2025-01-03T23:00:00Z', result['display_end_at']
  end

  test 'returns empty hash for invalid date values' do
    result = CalendarEventTimeResolver.resolve(
      event_data: {
        start_at: {
          date_time: '2025-99-99',
          time_zone: 'Pacific Standard Time'
        }
      }
    )

    assert_equal({}, result)
  end
end
