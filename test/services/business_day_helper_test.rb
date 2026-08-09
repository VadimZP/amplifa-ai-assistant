# frozen_string_literal: true

require 'test_helper'

class BusinessDayHelperTest < Minitest::Test
  # April 2026 calendar:
  # Su Mo Tu We Th Fr Sa
  #           1  2  3  4
  #  5  6  7  8  9 10 11
  # 12 13 14 15 16 17 18
  # 19 20 21 22 23 24 25
  # 26 27 28 29 30

  def test_yesterday_from_monday_returns_friday
    # April 6, 2026 is a Monday
    result = BusinessDayHelper.yesterday(from: Date.new(2026, 4, 6))
    assert_equal Date.new(2026, 4, 3), result
  end

  def test_yesterday_from_tuesday_returns_monday
    # April 7, 2026 is a Tuesday
    result = BusinessDayHelper.yesterday(from: Date.new(2026, 4, 7))
    assert_equal Date.new(2026, 4, 6), result
  end

  def test_yesterday_from_wednesday_returns_tuesday
    # April 8, 2026 is a Wednesday
    result = BusinessDayHelper.yesterday(from: Date.new(2026, 4, 8))
    assert_equal Date.new(2026, 4, 7), result
  end

  def test_yesterday_from_saturday_returns_friday
    # April 4, 2026 is a Saturday
    result = BusinessDayHelper.yesterday(from: Date.new(2026, 4, 4))
    assert_equal Date.new(2026, 4, 3), result
  end

  def test_yesterday_from_sunday_returns_friday
    # April 5, 2026 is a Sunday
    result = BusinessDayHelper.yesterday(from: Date.new(2026, 4, 5))
    assert_equal Date.new(2026, 4, 3), result
  end

  def test_last_n_calendar_days_excluding_weekends_returns_5_weekdays_from_wednesday
    # April 8, 2026 is a Wednesday
    # Last 7 calendar days: April 2-8 (Thu-Wed)
    # Weekdays: April 2, 3, 6, 7, 8 (Thu, Fri, Mon, Tue, Wed)
    result = BusinessDayHelper.last_n_calendar_days_excluding_weekends(7, from: Date.new(2026, 4, 8))
    expected = [
      Date.new(2026, 4, 2),
      Date.new(2026, 4, 3),
      Date.new(2026, 4, 6),
      Date.new(2026, 4, 7),
      Date.new(2026, 4, 8)
    ]
    assert_equal expected, result
  end

  def test_last_n_calendar_days_excluding_weekends_returns_5_weekdays_from_monday
    # April 6, 2026 is a Monday
    # Last 7 calendar days: March 31 - April 6 (Tue-Mon)
    # Weekdays: March 31, April 1, 2, 3, 6 (Tue, Wed, Thu, Fri, Mon)
    result = BusinessDayHelper.last_n_calendar_days_excluding_weekends(7, from: Date.new(2026, 4, 6))
    expected = [
      Date.new(2026, 3, 31),
      Date.new(2026, 4, 1),
      Date.new(2026, 4, 2),
      Date.new(2026, 4, 3),
      Date.new(2026, 4, 6)
    ]
    assert_equal expected, result
  end

  def test_last_n_calendar_days_excluding_weekends_returns_only_weekdays
    # April 8, 2026 is a Wednesday
    result = BusinessDayHelper.last_n_calendar_days_excluding_weekends(7, from: Date.new(2026, 4, 8))
    result.each do |date|
      refute_equal 0, date.wday, "Sunday found in result: #{date}"
      refute_equal 6, date.wday, "Saturday found in result: #{date}"
    end
  end

  def test_date_range_for_window_with_today_returns_array_with_single_date
    # Use a fixed date for testing
    result = BusinessDayHelper.date_range_for_window('today', from: Date.new(2026, 4, 8))
    assert_equal [Date.new(2026, 4, 8)], result
  end

  def test_date_range_for_window_with_yesterday_returns_array_with_single_date
    # April 8, 2026 is a Wednesday, yesterday is Tuesday
    result = BusinessDayHelper.date_range_for_window('yesterday', from: Date.new(2026, 4, 8))
    assert_equal [Date.new(2026, 4, 7)], result
  end

  def test_date_range_for_window_with_last_7_days_returns_business_days
    # April 8, 2026 is a Wednesday
    result = BusinessDayHelper.date_range_for_window('last_7_days', from: Date.new(2026, 4, 8))
    expected = [
      Date.new(2026, 4, 2),
      Date.new(2026, 4, 3),
      Date.new(2026, 4, 6),
      Date.new(2026, 4, 7),
      Date.new(2026, 4, 8)
    ]
    assert_equal expected, result
  end

  def test_date_range_for_window_with_invalid_window_raises_argument_error
    assert_raises(ArgumentError) do
      BusinessDayHelper.date_range_for_window('invalid_window', from: Date.new(2026, 4, 8))
    end
  end

  def test_date_range_for_window_with_nil_window_raises_argument_error
    assert_raises(ArgumentError) do
      BusinessDayHelper.date_range_for_window(nil, from: Date.new(2026, 4, 8))
    end
  end

  def test_add_business_days_monday_plus_3_equals_thursday
    assert_equal Date.new(2026, 3, 5), BusinessDayHelper.add_business_days(from: Date.new(2026, 3, 2), days: 3)
  end

  def test_add_business_days_friday_plus_1_equals_monday_skips_weekend
    assert_equal Date.new(2026, 3, 9), BusinessDayHelper.add_business_days(from: Date.new(2026, 3, 6), days: 1)
  end

  def test_add_business_days_wednesday_plus_3_equals_monday_next_week_skips_weekend
    assert_equal Date.new(2026, 3, 9), BusinessDayHelper.add_business_days(from: Date.new(2026, 3, 4), days: 3)
  end

  def test_add_business_days_friday_plus_3_equals_wednesday_next_week
    assert_equal Date.new(2026, 3, 11), BusinessDayHelper.add_business_days(from: Date.new(2026, 3, 6), days: 3)
  end

  def test_add_business_days_saturday_plus_1_normalizes_to_monday_then_adds_1_equals_tuesday
    assert_equal Date.new(2026, 3, 10), BusinessDayHelper.add_business_days(from: Date.new(2026, 3, 7), days: 1)
  end

  def test_add_business_days_days_0_on_a_weekday_returns_same_day
    assert_equal Date.new(2026, 3, 4), BusinessDayHelper.add_business_days(from: Date.new(2026, 3, 4), days: 0)
  end

  def test_add_business_days_days_0_on_saturday_normalizes_to_monday
    assert_equal Date.new(2026, 3, 9), BusinessDayHelper.add_business_days(from: Date.new(2026, 3, 7), days: 0)
  end

  def test_add_business_days_days_0_on_sunday_normalizes_to_monday
    assert_equal Date.new(2026, 3, 9), BusinessDayHelper.add_business_days(from: Date.new(2026, 3, 8), days: 0)
  end

  def test_add_business_days_negative_days_raises_argument_error
    assert_raises(ArgumentError) do
      BusinessDayHelper.add_business_days(from: Date.new(2026, 3, 4), days: -1)
    end
  end
end
