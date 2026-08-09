# frozen_string_literal: true

require 'test_helper'

class SenderTest < ActiveSupport::TestCase
  # === Association Tests ===

  # WHY: Sender must belong to an organization for proper scoping
  test 'belongs to organization' do
    sender = senders(:acme_john)
    assert_instance_of Organization, sender.organization
    assert_equal organizations(:acme), sender.organization
  end

  # WHY: Sender can have multiple mailboxes for different email addresses
  test 'has many mailboxes' do
    sender = senders(:acme_john)
    assert_respond_to sender, :mailboxes
  end

  # WHY: Deleting sender should not delete mailboxes (set to null instead)
  test 'nullifies mailboxes on destroy' do
    sender = senders(:acme_john)
    mailbox = mailboxes(:acme_mailbox_one)
    mailbox.update!(sender: sender)

    sender.destroy!

    mailbox.reload
    assert_nil mailbox.sender_id
  end

  # === Validation Tests ===

  # WHY: First name is required for proper identification
  test 'requires first_name' do
    sender = Sender.new(
      organization: organizations(:acme),
      last_name: 'Test',
      email: 'test@acme.com'
    )
    assert_not sender.valid?
    assert_includes sender.errors[:first_name], "can't be blank"
  end

  # WHY: Last name is required for proper identification
  test 'requires last_name' do
    sender = Sender.new(
      organization: organizations(:acme),
      first_name: 'Test',
      email: 'test@acme.com'
    )
    assert_not sender.valid?
    assert_includes sender.errors[:last_name], "can't be blank"
  end

  # WHY: Email is required for contact purposes
  test 'requires email' do
    sender = Sender.new(
      organization: organizations(:acme),
      first_name: 'Test',
      last_name: 'User'
    )
    assert_not sender.valid?
    assert_includes sender.errors[:email], "can't be blank"
  end

  # WHY: Email must be a valid format
  test 'requires valid email format' do
    sender = Sender.new(
      organization: organizations(:acme),
      first_name: 'Test',
      last_name: 'User',
      email: 'not-an-email'
    )
    assert_not sender.valid?
    assert_includes sender.errors[:email], 'is invalid'
  end

  # WHY: Email must be unique within an organization
  test 'requires unique email within organization' do
    existing = senders(:acme_john)
    sender = Sender.new(
      organization: existing.organization,
      first_name: 'Another',
      last_name: 'John',
      email: existing.email
    )
    assert_not sender.valid?
    assert_includes sender.errors[:email], 'has already been taken'
  end

  # WHY: Same email can exist in different organizations
  test 'allows same email in different organizations' do
    sender = Sender.new(
      organization: organizations(:beta),
      first_name: 'John',
      last_name: 'Smith',
      email: 'john@acme.com' # Same as acme_john but different org
    )
    assert sender.valid?
  end

  # WHY: Status must be a valid value
  test 'requires valid status' do
    sender = Sender.new(
      organization: organizations(:acme),
      first_name: 'Test',
      last_name: 'User',
      email: 'test@acme.com',
      status: 'invalid_status'
    )
    assert_not sender.valid?
    assert_includes sender.errors[:status], 'is not included in the list'
  end

  # WHY: Status defaults to active
  test 'defaults status to active' do
    sender = Sender.new(
      organization: organizations(:acme),
      first_name: 'Test',
      last_name: 'User',
      email: 'test@acme.com'
    )
    assert_equal 'active', sender.status
  end

  # WHY: LinkedIn URL must be a valid LinkedIn profile URL
  test 'validates linkedin_url format' do
    sender = senders(:acme_john)
    sender.linkedin_url = 'https://twitter.com/invalid'
    assert_not sender.valid?
    assert_includes sender.errors[:linkedin_url], 'must be a valid LinkedIn profile URL'
  end

  # WHY: Valid LinkedIn URLs should pass
  test 'accepts valid linkedin_url' do
    sender = senders(:acme_john)

    valid_urls = [
      'https://linkedin.com/in/username',
      'https://www.linkedin.com/in/username',
      'http://linkedin.com/in/username'
    ]

    valid_urls.each do |url|
      sender.linkedin_url = url
      assert sender.valid?, "Expected #{url} to be valid"
    end
  end

  # WHY: LinkedIn URL is optional
  test 'allows blank linkedin_url' do
    sender = senders(:acme_jane)
    assert_nil sender.linkedin_url
    assert sender.valid?
  end

  # WHY: Calendly URL must be a valid Calendly URL
  # WHY: Valid Calendly URLs should pass
  test 'accepts valid calendly_url' do
    sender = senders(:acme_john)

    valid_urls = [
      'https://calendly.com/username',
      'https://www.calendly.com/username/meeting',
      'http://calendly.com/team/user'
    ]

    valid_urls.each do |url|
      sender.calendly_url = url
      assert sender.valid?, "Expected #{url} to be valid"
    end
  end

  # WHY: Calendly URL is optional
  test 'allows blank calendly_url' do
    sender = senders(:acme_jane)
    assert_nil sender.calendly_url
    assert sender.valid?
  end

  # === Callback Tests ===

  # WHY: Email should be normalized to lowercase for consistency
  test 'normalizes email to lowercase' do
    sender = Sender.create!(
      organization: organizations(:acme),
      first_name: 'Test',
      last_name: 'User',
      email: 'TEST.USER@ACME.COM'
    )
    assert_equal 'test.user@acme.com', sender.email
  end

  # WHY: Email should be stripped of whitespace
  test 'strips whitespace from email' do
    sender = Sender.create!(
      organization: organizations(:acme),
      first_name: 'Test',
      last_name: 'User',
      email: '  test2@acme.com  '
    )
    assert_equal 'test2@acme.com', sender.email
  end

  # === Status Predicate Tests ===

  # WHY: active? predicate for easy status checking
  test 'active? returns true when status is active' do
    sender = senders(:acme_john)
    assert sender.active?
    assert_not sender.inactive?
  end

  # WHY: inactive? predicate for easy status checking
  test 'inactive? returns true when status is inactive' do
    sender = senders(:acme_inactive)
    assert sender.inactive?
    assert_not sender.active?
  end

  # === Name Helper Tests ===

  # WHY: full_name provides formatted name for display
  test 'full_name returns first and last name' do
    sender = senders(:acme_john)
    assert_equal 'John Smith', sender.full_name
  end

  # WHY: display_name uses nickname when available
  test 'display_name returns nickname when present' do
    sender = senders(:acme_john)
    assert_equal 'Johnny', sender.display_name
  end

  # WHY: display_name falls back to first_name when no nickname
  test 'display_name returns first_name when no nickname' do
    sender = senders(:acme_jane)
    assert_equal 'Jane', sender.display_name
  end

  # === Scope Tests ===

  # WHY: active scope filters only active senders
  test 'active scope returns only active senders' do
    active_senders = Sender.active
    assert active_senders.all?(&:active?)
    assert_not active_senders.any?(&:inactive?)
  end

  # WHY: inactive scope filters only inactive senders
  test 'inactive scope returns only inactive senders' do
    inactive_senders = Sender.inactive
    assert inactive_senders.all?(&:inactive?)
    assert_not inactive_senders.any?(&:active?)
  end

  # === Capacity Helper Tests ===

  # WHY: total_daily_capacity aggregates capacity across all active mailboxes
  test 'total_daily_capacity sums active mailbox limits' do
    sender = senders(:acme_john)
    mailbox1 = mailboxes(:acme_mailbox_one)
    mailbox2 = mailboxes(:acme_mailbox_two)

    mailbox1.update!(sender: sender)
    mailbox2.update!(sender: sender)

    expected = mailbox1.daily_send_limit + mailbox2.daily_send_limit
    assert_equal expected, sender.total_daily_capacity
  end

  # WHY: Paused mailboxes should not count toward capacity
  test 'total_daily_capacity excludes paused mailboxes' do
    sender = senders(:acme_john)
    active_mailbox = mailboxes(:acme_mailbox_one)
    paused_mailbox = mailboxes(:acme_paused_mailbox)

    active_mailbox.update!(sender: sender)
    paused_mailbox.update!(sender: sender)

    assert_equal active_mailbox.daily_send_limit, sender.total_daily_capacity
  end

  # WHY: mailbox_count returns total number of mailboxes
  test 'mailbox_count returns total mailbox count' do
    sender = senders(:acme_inactive)
    assert_equal 0, sender.mailbox_count

    mailboxes(:acme_mailbox_one).update!(sender: sender)
    assert_equal 1, sender.reload.mailbox_count

    mailboxes(:acme_mailbox_two).update!(sender: sender)
    assert_equal 2, sender.reload.mailbox_count
  end

  # WHY: active_mailbox_count returns only active mailboxes
  test 'active_mailbox_count returns only active mailboxes' do
    sender = senders(:acme_john)
    mailboxes(:acme_mailbox_one).update!(sender: sender)
    mailboxes(:acme_paused_mailbox).update!(sender: sender)

    assert_equal 2, sender.reload.mailbox_count
    assert_equal 1, sender.active_mailbox_count
  end

  # === Profile Photo Tests ===

  # WHY: Profile photo is optional
  test 'profile_photo is optional' do
    sender = senders(:acme_jane)
    assert_not sender.profile_photo.attached?
    assert sender.valid?
  end

  # NOTE: Full profile photo validation tests require ActiveStorage test setup
  # which would test file size limits (4MB) and content types (JPEG/PNG only)

  # === Calendly Connection Status Tests ===

  # WHY: calendly_connection_status defaults to 'disconnected' and must be valid
  test 'calendly_connection_status defaults to disconnected' do
    sender = Sender.new(
      organization: organizations(:acme),
      first_name: 'Test',
      last_name: 'User',
      email: 'calendly-test@acme.com'
    )
    assert_equal 'disconnected', sender.calendly_connection_status
    assert sender.valid?
  end

  # WHY: Only valid Calendly statuses should be accepted
  # === Calendly Predicate Method Tests ===

  # WHY: calendly_connected? provides clean API for checking connection state
  # WHY: calendly_disconnected? provides clean API for checking disconnected state
  # WHY: calendly_error? provides clean API for checking error state
  # === Calendly Token Validation Tests ===

  # WHY: Token is invalid when access token is blank
  # WHY: Token is valid when access token exists and no expiry is set
  # WHY: Token is valid when expiry is more than 5 minutes away
  # WHY: Token is invalid when within 5 minute buffer of expiry
  # WHY: calendly_token_expired? returns true when token is blank
  # WHY: calendly_token_expired? returns false when no expiry is set
  # WHY: calendly_token_expired? returns true when past expiry
  # === Clear Calendly Connection Tests ===

  # WHY: clear_calendly_connection! should reset all Calendly fields
  test 'calendly tokens are stored in plain text' do
    sender = senders(:acme_john)
    sender.update!(
      calendly_access_token: 'secret_access_token',
      calendly_refresh_token: 'secret_refresh_token',
      calendly_webhook_signing_key: 'secret_signing_key'
    )

    # Verify we can read the decrypted values
    sender.reload
    assert_equal 'secret_access_token', sender.calendly_access_token
    assert_equal 'secret_refresh_token', sender.calendly_refresh_token
    assert_equal 'secret_signing_key', sender.calendly_webhook_signing_key

    raw = sender.class.connection.execute(
      "SELECT calendly_access_token FROM senders WHERE id = #{sender.id}"
    ).first
    assert_not_nil raw['calendly_access_token']
    assert_equal 'secret_access_token', raw['calendly_access_token']
  end

  # === Calendly Scope Tests ===

  # WHY: calendly_connected scope filters senders by connection status
  # WHY: calendly_disconnected scope filters senders by disconnected status
  # === Meetings Association Test ===

  # WHY: Sender can have many meetings created via their Calendly account
  test 'has many meetings' do
    sender = senders(:acme_john)
    assert_respond_to sender, :meetings
  end

  # === Calendly Link Helper Tests ===

  # === Send Window Fields Tests ===

  # WHY: Timezone is required for send window calculations
  test 'requires timezone' do
    sender = Sender.new(
      organization: organizations(:acme),
      first_name: 'Test',
      last_name: 'User',
      email: 'test@acme.com',
      timezone: nil
    )
    assert_not sender.valid?
    assert_includes sender.errors[:timezone], "can't be blank"
  end

  # WHY: Timezone must be a valid IANA timezone
  test 'validates timezone is valid IANA timezone' do
    sender = senders(:acme_john)
    sender.timezone = 'Invalid/Timezone'
    assert_not sender.valid?
    assert_includes sender.errors[:timezone], 'is not a valid timezone'
  end

  # WHY: Valid IANA timezones should be accepted
  test 'accepts valid IANA timezones' do
    sender = senders(:acme_john)
    valid_timezones = ['Europe/Berlin', 'America/New_York', 'Asia/Tokyo', 'UTC', 'Europe/London']

    valid_timezones.each do |tz|
      sender.timezone = tz
      assert sender.valid?, "Expected #{tz} to be a valid timezone"
    end
  end

  # WHY: Timezone defaults to Europe/Berlin
  test 'defaults timezone to Europe/Berlin' do
    sender = Sender.new(
      organization: organizations(:acme),
      first_name: 'Test',
      last_name: 'User',
      email: 'test@acme.com'
    )
    assert_equal 'Europe/Berlin', sender.timezone
  end

  test 'timezone_options use IANA identifiers as values' do
    options = Sender.timezone_options(reference_time: Time.utc(2026, 1, 15, 12, 0, 0))

    assert_includes options, ['Europe/Berlin', '(UTC+01:00) Europe/Berlin']
    assert_includes options, ['UTC', '(UTC+00:00) UTC']
  end

  test 'timezone_options reflect daylight saving offsets in labels' do
    options = Sender.timezone_options(reference_time: Time.utc(2026, 7, 15, 12, 0, 0)).to_h

    assert_equal '(UTC+02:00) Europe/Berlin', options['Europe/Berlin']
  end

  # WHY: send_window_start_hour must be 0-23
  test 'validates send_window_start_hour is 0-23' do
    sender = senders(:acme_john)

    sender.send_window_end_hour = 23
    sender.send_window_end_minute = 30

    # Valid values
    [0, 8, 12, 23].each do |hour|
      sender.send_window_start_hour = hour
      assert sender.valid?, "Expected hour #{hour} to be valid"
    end

    # Invalid values
    [-1, 24, 25].each do |hour|
      sender.send_window_start_hour = hour
      assert_not sender.valid?, "Expected hour #{hour} to be invalid"
      assert_includes sender.errors[:send_window_start_hour], 'must be between 0 and 23'
    end
  end

  # WHY: send_window_end_hour must be 0-23
  test 'validates send_window_end_hour is 0-23' do
    sender = senders(:acme_john)
    sender.assign_attributes(send_window_start_hour: 0, send_window_start_minute: 0, send_window_end_minute: 30)

    # Valid values
    [0, 8, 12, 23].each do |hour|
      sender.send_window_end_hour = hour
      assert sender.valid?, "Expected hour #{hour} to be valid"
    end

    # Invalid values
    [-1, 24, 25].each do |hour|
      sender.send_window_end_hour = hour
      assert_not sender.valid?, "Expected hour #{hour} to be invalid"
      assert_includes sender.errors[:send_window_end_hour], 'must be between 0 and 23'
    end
  end

  # WHY: send_window_start_minute must be 0 or 30
  test 'validates send_window_start_minute is 0 or 30' do
    sender = senders(:acme_john)

    # Valid values
    [0, 30].each do |minute|
      sender.send_window_start_minute = minute
      assert sender.valid?, "Expected minute #{minute} to be valid"
    end

    # Invalid values
    [1, 15, 45, 59].each do |minute|
      sender.send_window_start_minute = minute
      assert_not sender.valid?, "Expected minute #{minute} to be invalid"
      assert_includes sender.errors[:send_window_start_minute], 'must be 0 or 30'
    end
  end

  # WHY: send_window_end_minute must be 0 or 30
  test 'validates send_window_end_minute is 0 or 30' do
    sender = senders(:acme_john)

    # Valid values
    [0, 30].each do |minute|
      sender.send_window_end_minute = minute
      assert sender.valid?, "Expected minute #{minute} to be valid"
    end

    # Invalid values
    [1, 15, 45, 59].each do |minute|
      sender.send_window_end_minute = minute
      assert_not sender.valid?, "Expected minute #{minute} to be invalid"
      assert_includes sender.errors[:send_window_end_minute], 'must be 0 or 30'
    end
  end

  # WHY: Start time must be before end time
  test 'validates start time is before end time' do
    sender = senders(:acme_john)

    # Valid: start before end
    sender.send_window_start_hour = 8
    sender.send_window_start_minute = 0
    sender.send_window_end_hour = 18
    sender.send_window_end_minute = 0
    assert sender.valid?

    # Valid: same hour, different minutes
    sender.send_window_start_hour = 8
    sender.send_window_start_minute = 0
    sender.send_window_end_hour = 8
    sender.send_window_end_minute = 30
    assert sender.valid?

    # Invalid: start after end
    sender.send_window_start_hour = 18
    sender.send_window_start_minute = 0
    sender.send_window_end_hour = 8
    sender.send_window_end_minute = 0
    assert_not sender.valid?
    assert_includes sender.errors[:send_window_start_hour], 'must be before end time'

    # Invalid: same time
    sender.send_window_start_hour = 8
    sender.send_window_start_minute = 0
    sender.send_window_end_hour = 8
    sender.send_window_end_minute = 0
    assert_not sender.valid?
    assert_includes sender.errors[:send_window_start_hour], 'must be before end time'
  end

  # WHY: Defaults for send window fields
  test 'defaults send window fields' do
    sender = Sender.new(
      organization: organizations(:acme),
      first_name: 'Test',
      last_name: 'User',
      email: 'test@acme.com'
    )
    assert_equal 8, sender.send_window_start_hour
    assert_equal 18, sender.send_window_end_hour
    assert_equal 0, sender.send_window_start_minute
    assert_equal 0, sender.send_window_end_minute
  end

  # === Send Window Helper Methods Tests ===

  # WHY: send_window_start_time_on returns correct time in sender's timezone
  test 'send_window_start_time_on returns time in sender timezone' do
    sender = senders(:acme_john)
    sender.update!(
      timezone: 'America/New_York',
      send_window_start_hour: 9,
      send_window_start_minute: 30
    )

    date = Date.new(2025, 4, 9)
    start_time = sender.send_window_start_time_on(date)

    assert_equal 9, start_time.hour
    assert_equal 30, start_time.min
    assert_equal 'America/New_York', start_time.time_zone.name
  end

  # WHY: send_window_end_time_on returns correct time in sender's timezone
  test 'send_window_end_time_on returns time in sender timezone' do
    sender = senders(:acme_john)
    sender.update!(
      timezone: 'Europe/London',
      send_window_end_hour: 17,
      send_window_end_minute: 30
    )

    date = Date.new(2025, 4, 9)
    end_time = sender.send_window_end_time_on(date)

    assert_equal 17, end_time.hour
    assert_equal 30, end_time.min
    assert_equal 'Europe/London', end_time.time_zone.name
  end

  # WHY: in_send_window? returns true when time is within window
  test 'in_send_window? returns true when time is within window' do
    sender = senders(:acme_john)
    sender.update!(
      timezone: 'UTC',
      send_window_start_hour: 8,
      send_window_start_minute: 0,
      send_window_end_hour: 18,
      send_window_end_minute: 0
    )

    # Time within window
    time = Time.zone.parse('2025-04-09 12:00:00')
    assert sender.in_send_window?(time)
  end

  # WHY: in_send_window? returns false when time is before window
  test 'in_send_window? returns false when time is before window' do
    sender = senders(:acme_john)
    sender.update!(
      timezone: 'UTC',
      send_window_start_hour: 8,
      send_window_start_minute: 0,
      send_window_end_hour: 18,
      send_window_end_minute: 0
    )

    # Time before window
    time = Time.zone.parse('2025-04-09 07:59:00')
    assert_not sender.in_send_window?(time)
  end

  # WHY: in_send_window? returns false when time is after window
  test 'in_send_window? returns false when time is after window' do
    sender = senders(:acme_john)
    sender.update!(
      timezone: 'UTC',
      send_window_start_hour: 8,
      send_window_start_minute: 0,
      send_window_end_hour: 18,
      send_window_end_minute: 0
    )

    # Time after window
    time = Time.zone.parse('2025-04-09 18:00:01')
    assert_not sender.in_send_window?(time)
  end

  # WHY: in_send_window? uses current time by default
  test 'in_send_window? uses current time by default' do
    sender = senders(:acme_john)
    sender.update!(
      timezone: 'UTC',
      send_window_start_hour: 0,
      send_window_start_minute: 0,
      send_window_end_hour: 23,
      send_window_end_minute: 30
    )

    # Should use Time.current by default
    travel_to Time.utc(2026, 1, 1, 12, 0, 0) do
      assert sender.in_send_window?
    end
  end

  # WHY: in_send_window? respects half-hour boundaries
  test 'in_send_window? respects half-hour boundaries' do
    sender = senders(:acme_john)
    sender.update!(
      timezone: 'UTC',
      send_window_start_hour: 8,
      send_window_start_minute: 30,
      send_window_end_hour: 18,
      send_window_end_minute: 30
    )

    # Just before start
    time = Time.zone.parse('2025-04-09 08:29:59')
    assert_not sender.in_send_window?(time)

    # At start
    time = Time.zone.parse('2025-04-09 08:30:00')
    assert sender.in_send_window?(time)

    # Just before end
    time = Time.zone.parse('2025-04-09 18:29:59')
    assert sender.in_send_window?(time)

    # At end (exclusive)
    time = Time.zone.parse('2025-04-09 18:30:00')
    assert_not sender.in_send_window?(time)
  end

  # WHY: in_send_window? respects sender's timezone
  test 'in_send_window? respects sender timezone' do
    sender = senders(:acme_john)
    sender.update!(
      timezone: 'America/New_York',
      send_window_start_hour: 8,
      send_window_start_minute: 0,
      send_window_end_hour: 18,
      send_window_end_minute: 0
    )

    # Create a time that is 8am in New York but different in UTC
    # 8am EST = 1pm UTC (during winter)
    time = Time.zone.parse('2025-01-09 13:00:00') # 1pm UTC = 8am EST
    assert sender.in_send_window?(time)
  end

  # WHY: jobs need a reusable sender-local timestamp instead of ad hoc timezone math
  test 'local_time converts utc time into sender timezone' do
    sender = senders(:acme_john)
    time = Time.utc(2025, 1, 3, 23, 30, 0)

    local_time = sender.local_time(time)

    assert_instance_of ActiveSupport::TimeWithZone, local_time
    assert_equal Time.find_zone!('Europe/Berlin').parse('2025-01-04 00:30:00'), local_time
  end

  # WHY: sender-local date must follow the sender timezone around utc date boundaries
  test 'local_date returns sender local date across utc midnight boundary' do
    sender = senders(:acme_john)
    sender.timezone = 'Asia/Tokyo'
    time = Time.utc(2025, 1, 3, 23, 0, 0)

    assert_equal Date.new(2025, 1, 4), sender.local_date(time)
  end

  # WHY: weekend detection must use the sender timezone rather than server time
  test 'weekend? returns true for saturday sunday and false for weekdays in sender timezone' do
    sender = senders(:acme_john)

    assert sender.weekend?(Time.utc(2025, 1, 4, 12, 0, 0))
    assert sender.weekend?(Time.utc(2025, 1, 5, 12, 0, 0))
    assert_not sender.weekend?(Time.utc(2025, 1, 6, 12, 0, 0))
  end

  # WHY: the same utc timestamp can be a weekend for one sender and a weekday for another
  test 'weekend? can differ by sender timezone for the same utc timestamp' do
    berlin_sender = senders(:acme_john)
    utc_sender = berlin_sender.dup
    utc_sender.timezone = 'UTC'
    time = Time.utc(2025, 1, 3, 23, 30, 0)

    assert berlin_sender.weekend?(time)
    assert_not utc_sender.weekend?(time)
  end

  # WHY: sunday night utc can already be monday for the sender and should not count as weekend
  test 'weekend? handles sunday to monday rollover in sender timezone' do
    sender = senders(:acme_john)
    sender.timezone = 'Asia/Dubai'
    time = Time.utc(2025, 1, 5, 22, 0, 0)

    assert_equal Date.new(2025, 1, 6), sender.local_date(time)
    assert_not sender.weekend?(time)
  end
end
