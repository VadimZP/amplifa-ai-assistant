# frozen_string_literal: true

require 'test_helper'
require 'stringio'

class MailboxTest < ActiveSupport::TestCase
  # Tests cover basic validation (WHY: ensure mailbox configuration integrity)
  test 'requires email' do
    mailbox = Mailbox.new(
      email_domain: email_domains(:acme_google),
      organization: organizations(:acme)
    )
    assert_not mailbox.valid?
    assert_includes mailbox.errors[:email], "can't be blank"
  end

  test 'requires valid email format' do
    mailbox = Mailbox.new(
      email: 'not-an-email',
      email_domain: email_domains(:acme_google),
      organization: organizations(:acme)
    )
    assert_not mailbox.valid?
    assert_includes mailbox.errors[:email], 'is invalid'
  end

  test 'requires email_domain' do
    mailbox = Mailbox.new(
      email: 'new@acme.com',
      organization: organizations(:acme)
    )
    assert_not mailbox.valid?
    assert_includes mailbox.errors[:email_domain], 'must exist'
  end

  test 'requires organization' do
    mailbox = Mailbox.new(
      email: 'new@acme.com',
      email_domain: email_domains(:acme_google)
    )
    assert_not mailbox.valid?
    assert_includes mailbox.errors[:organization], 'must exist'
  end

  test 'validates daily_send_limit range' do
    mailbox = mailboxes(:acme_mailbox_one)

    mailbox.daily_send_limit = 0
    assert_not mailbox.valid?

    mailbox.daily_send_limit = 2001
    assert_not mailbox.valid?

    mailbox.daily_send_limit = 200
    assert mailbox.valid?
  end

  # Tests cover uniqueness (WHY: prevent duplicate email addresses)
  test 'prevents duplicate email addresses' do
    existing = mailboxes(:acme_mailbox_one)
    duplicate = Mailbox.new(
      email: existing.email,
      email_domain: existing.email_domain,
      organization: existing.organization
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:email], 'has already been taken'
  end

  test 'allows email reuse after soft deletion' do
    domain = EmailDomain.create!(
      organization: organizations(:acme),
      provider_type: 'google',
      domain: 'reusable-mailbox.com',
      status: 'active'
    )
    deleted_mailbox = Mailbox.create!(
      email: 'sender@reusable-mailbox.com',
      email_domain: domain,
      organization: organizations(:acme),
      status: 'deleted',
      daily_send_limit: 100
    )

    replacement = Mailbox.new(
      email: deleted_mailbox.email,
      email_domain: domain,
      organization: organizations(:acme),
      status: 'active',
      daily_send_limit: 100
    )

    assert replacement.valid?
  end

  # Tests cover domain validation (WHY: email must match email domain)
  test 'email must match email domain' do
    mailbox = Mailbox.new(
      email: 'user@wrong-domain.com',
      email_domain: email_domains(:acme_google),
      organization: organizations(:acme),
      daily_send_limit: 100
    )
    assert_not mailbox.valid?
    assert(mailbox.errors[:email].any? { |e| e.include?('must match the email domain') })
  end

  # Tests cover organization consistency (WHY: prevent cross-org data issues)
  test 'organization must match email domain organization' do
    mailbox = Mailbox.new(
      email: 'user@acme.com',
      email_domain: email_domains(:acme_google),
      organization: organizations(:beta), # Different org!
      daily_send_limit: 100
    )
    assert_not mailbox.valid?
    assert(mailbox.errors[:email_domain].any? { |e| e.include?('same organization') })
  end

  # Tests cover status predicates (WHY: convenient status checking)
  test 'status predicates work correctly' do
    assert mailboxes(:acme_mailbox_one).active?
    assert mailboxes(:acme_paused_mailbox).paused?
  end

  # Tests cover warmup calculations (WHY: track mailbox readiness)
  test 'warmup_complete? returns true when warmup_started_at is nil' do
    mailbox = mailboxes(:growth_lab_mailbox)
    assert_nil mailbox.warmup_started_at
    assert mailbox.warmup_complete?
  end

  test 'warmup_complete? returns true after 21 days' do
    mailbox = mailboxes(:acme_mailbox_one)
    mailbox.warmup_started_at = 30.days.ago
    assert mailbox.warmup_complete?
  end

  test 'warmup_complete? returns false during warmup' do
    mailbox = mailboxes(:acme_mailbox_two)
    # Started 10 days ago in fixture
    assert_not mailbox.warmup_complete?
  end

  test 'warmup_progress_percentage calculates correctly' do
    mailbox = mailboxes(:acme_mailbox_two)
    mailbox.warmup_started_at = 7.days.ago
    # 7/21 = ~33%
    assert_in_delta 33, mailbox.warmup_progress_percentage, 5
  end

  test 'warmup_days_remaining calculates correctly' do
    mailbox = mailboxes(:acme_mailbox_two)
    mailbox.warmup_started_at = 7.days.ago
    assert_in_delta 14, mailbox.warmup_days_remaining, 1
  end

  # Tests cover capacity methods (WHY: track sending limits)
  test 'daily_capacity_remaining returns correct value' do
    mailbox = mailboxes(:acme_mailbox_one)
    # No messages sent today, full capacity
    assert_equal mailbox.daily_send_limit, mailbox.daily_capacity_remaining
  end

  test 'has_capacity? returns true when capacity available' do
    mailbox = mailboxes(:acme_mailbox_one)
    assert mailbox.has_capacity?
  end

  # Tests cover can_send? method (WHY: composite check for send eligibility)
  test 'can_send? returns true when active, has capacity, and warmup complete' do
    mailbox = mailboxes(:acme_mailbox_one)
    # active, warmup started 30 days ago (complete), has capacity
    assert mailbox.can_send?
  end

  test 'can_send? returns false when paused' do
    mailbox = mailboxes(:acme_paused_mailbox)
    assert_not mailbox.can_send?
  end

  test 'can_send? returns false during warmup' do
    mailbox = mailboxes(:acme_mailbox_two)
    # Still warming up (10 days)
    assert_not mailbox.can_send?
  end

  test 'sendable_now? returns false when mailbox is cooling down' do
    mailbox = mailboxes(:acme_mailbox_one)
    mailbox.update!(last_sent_at: 1.minute.ago, next_available_send_at: 5.minutes.from_now)

    assert_not mailbox.sendable_now?
  end

  test 'sendable_now? returns true when cooldown has elapsed' do
    mailbox = mailboxes(:acme_mailbox_one)
    mailbox.update!(last_sent_at: 15.minutes.ago, next_available_send_at: 1.minute.ago)

    assert mailbox.sendable_now?
  end

  # Tests cover display name (WHY: for email "From" field)
  test 'full_display_name returns display_name when set' do
    mailbox = mailboxes(:acme_mailbox_one)
    assert_equal 'Acme Sales', mailbox.full_display_name
  end

  test 'full_display_name builds from first/last name when no display_name' do
    mailbox = mailboxes(:acme_mailbox_two)
    assert_equal 'Outreach Team', mailbox.full_display_name
  end

  test 'full_display_name extracts from email when no names' do
    mailbox = Mailbox.new(email: 'nobody@example.com')
    assert_equal 'nobody', mailbox.full_display_name
  end

  # Tests cover domain delegation (WHY: convenient access to domain info)
  test 'delegates provider_type to email_domain' do
    mailbox = mailboxes(:acme_mailbox_one)
    assert_equal 'google', mailbox.provider_type
    assert mailbox.google?
    assert_not mailbox.microsoft?
  end

  # Tests cover associations (WHY: ensure relationships work)
  test 'belongs to email_domain' do
    mailbox = mailboxes(:acme_mailbox_one)
    assert_equal email_domains(:acme_google), mailbox.email_domain
  end

  test 'belongs to organization' do
    mailbox = mailboxes(:acme_mailbox_one)
    assert_equal organizations(:acme), mailbox.organization
  end

  test 'has many agent_mailboxes' do
    mailbox = mailboxes(:acme_mailbox_one)
    assert_respond_to mailbox, :agent_mailboxes
  end

  test 'has many agents through agent_mailboxes' do
    mailbox = mailboxes(:acme_mailbox_one)
    assert_respond_to mailbox, :agents
  end

  # Tests cover scopes (WHY: efficient filtering for queries)
  test 'active scope returns only active mailboxes' do
    results = Mailbox.active
    assert results.all?(&:active?)
  end

  test 'for_organization scope filters by organization' do
    results = Mailbox.for_organization(organizations(:acme))
    assert(results.all? { |m| m.organization_id == organizations(:acme).id })
  end

  test 'warmup_complete scope filters correctly' do
    results = Mailbox.warmup_complete
    assert results.all?(&:warmup_complete?)
  end

  # WHY: Conversations association enables Reply Center mailbox-scoped queries
  test 'has many conversations' do
    mailbox = mailboxes(:acme_mailbox_one)
    assert_respond_to mailbox, :conversations
    assert_nothing_raised { mailbox.conversations.to_a }
  end

  # WHY: Sent replies association enables tracking outbound from mailbox
  test 'has many sent_replies' do
    mailbox = mailboxes(:acme_mailbox_one)
    assert_respond_to mailbox, :sent_replies
    assert_nothing_raised { mailbox.sent_replies.to_a }
  end

  # WHY: Polling status tracking shows when mail was last checked
  test 'recently_polled? returns true when polled within 30 minutes' do
    mailbox = mailboxes(:acme_mailbox_one)
    mailbox.last_polled_at = 15.minutes.ago
    assert mailbox.recently_polled?
  end

  test 'recently_polled? returns false when polled more than 30 minutes ago' do
    mailbox = mailboxes(:acme_mailbox_one)
    mailbox.last_polled_at = 45.minutes.ago
    refute mailbox.recently_polled?
  end

  test 'recently_polled? returns false when never polled' do
    mailbox = mailboxes(:acme_mailbox_one)
    mailbox.last_polled_at = nil
    refute mailbox.recently_polled?
  end

  # WHY: Polling status provides human-readable status for UI
  test 'polling_status returns never when last_polled_at is nil' do
    mailbox = mailboxes(:acme_mailbox_one)
    mailbox.last_polled_at = nil
    assert_equal 'never', mailbox.polling_status
  end

  test 'polling_status returns error when last_poll_error present' do
    mailbox = mailboxes(:acme_mailbox_one)
    mailbox.last_polled_at = 5.minutes.ago
    mailbox.last_poll_error = 'Connection timeout'
    assert_equal 'error', mailbox.polling_status
  end

  test 'polling_status returns recent when polled within 30 minutes' do
    mailbox = mailboxes(:acme_mailbox_one)
    mailbox.last_polled_at = 15.minutes.ago
    mailbox.last_poll_error = nil
    assert_equal 'recent', mailbox.polling_status
  end

  test 'polling_status returns stale when polled more than 30 minutes ago' do
    mailbox = mailboxes(:acme_mailbox_one)
    mailbox.last_polled_at = 2.hours.ago
    mailbox.last_poll_error = nil
    assert_equal 'stale', mailbox.polling_status
  end

  # WHY: mark_polled! updates polling tracking after mail fetch
  test 'mark_polled! updates last_polled_at and clears error' do
    mailbox = mailboxes(:acme_mailbox_one)
    mailbox.last_poll_error = 'Previous error'

    mailbox.mark_polled!

    assert_in_delta Time.current, mailbox.last_polled_at, 2.seconds
    assert_nil mailbox.last_poll_error
  end

  test 'mark_polled! records error when provided' do
    mailbox = mailboxes(:acme_mailbox_one)

    mailbox.mark_polled!(error: 'API rate limit exceeded')

    assert_in_delta Time.current, mailbox.last_polled_at, 2.seconds
    assert_equal 'API rate limit exceeded', mailbox.last_poll_error
  end

  test 'mark_poll_error! can suspend mailbox' do
    mailbox = mailboxes(:acme_mailbox_one)

    mailbox.mark_poll_error!(Mailbox::GOOGLE_MAIL_SERVICE_DISABLED_ERROR, suspend: true)

    assert_in_delta Time.current, mailbox.last_polled_at, 2.seconds
    assert_equal Mailbox::GOOGLE_MAIL_SERVICE_DISABLED_ERROR, mailbox.last_poll_error
    assert_equal 'suspended', mailbox.status
  end

  test 'google_mail_service_disabled_error? matches Gmail disabled message' do
    mailbox = mailboxes(:acme_mailbox_one)

    assert mailbox.google_mail_service_disabled_error?('failedPrecondition: Mail service not enabled')
    refute mailbox.google_mail_service_disabled_error?('Connection timeout')
  end

  test 'record_send! updates last_sent_at to current time' do
    mailbox = mailboxes(:acme_mailbox_one)
    mailbox.last_sent_at = nil

    mailbox.record_send!

    assert_in_delta Time.current, mailbox.last_sent_at, 2.seconds
    assert mailbox.next_available_send_at.present?
    assert_operator mailbox.next_available_send_at, :>=, mailbox.last_sent_at + 7.minutes
    assert_operator mailbox.next_available_send_at, :<=, mailbox.last_sent_at + 11.minutes
  end

  test 'next_available_send_time returns current time when never sent' do
    mailbox = mailboxes(:acme_mailbox_one)
    mailbox.last_sent_at = nil

    result = mailbox.next_available_send_time

    assert_in_delta Time.current, result, 2.seconds
  end

  test 'next_available_send_time returns persisted next available time when present' do
    mailbox = mailboxes(:acme_mailbox_one)
    mailbox.last_sent_at = 1.minute.ago
    mailbox.next_available_send_at = 7.minutes.from_now

    result = mailbox.next_available_send_time

    assert_equal mailbox.next_available_send_at.to_i, result.to_i
  end

  test 'ready_to_send_now ignores corrupt future next available send timestamp and logs warning' do
    mailbox = mailboxes(:acme_mailbox_one)

    travel_to Time.utc(2026, 3, 10, 12, 0, 0) do
      corrupt_timestamp = 6.days.from_now
      mailbox.next_available_send_at = corrupt_timestamp

      log_output = capture_mailbox_log do
        assert mailbox.ready_to_send_now?
        assert_equal 0, mailbox.seconds_until_can_send
      end

      assert_includes log_output, expected_corrupt_send_stamp_warning(mailbox, corrupt_timestamp)
    end
  end

  test 'normal future next available send timestamp keeps cooldown without warning' do
    mailbox = mailboxes(:acme_mailbox_one)

    travel_to Time.utc(2026, 3, 10, 12, 0, 0) do
      mailbox.next_available_send_at = 5.minutes.from_now

      log_output = capture_mailbox_log do
        assert_equal 300, mailbox.seconds_until_can_send
      end

      assert_empty log_output
    end
  end

  test 'future next available send timestamp corruption boundary is strictly greater than grace' do
    mailbox = mailboxes(:acme_mailbox_one)

    travel_to Time.utc(2026, 3, 10, 12, 0, 0) do
      mailbox.next_available_send_at = Time.current + 720.seconds

      safe_log_output = capture_mailbox_log do
        assert_equal 720, mailbox.seconds_until_can_send
      end

      assert_empty safe_log_output

      corrupt_timestamp = Time.current + 721.seconds
      mailbox.next_available_send_at = corrupt_timestamp

      corrupt_log_output = capture_mailbox_log do
        assert_equal 0, mailbox.seconds_until_can_send
      end

      assert_includes corrupt_log_output, expected_corrupt_send_stamp_warning(mailbox, corrupt_timestamp)
    end
  end

  test 'next_available_send_time falls back to conservative legacy cooldown when next_available_send_at is nil' do
    mailbox = mailboxes(:acme_mailbox_one)
    mailbox.last_sent_at = 1.minute.ago
    mailbox.next_available_send_at = nil

    result = mailbox.next_available_send_time

    expected = mailbox.last_sent_at + 11.minutes
    assert_equal expected.to_i, result.to_i
  end

  test 'fallback cooldown ignores corrupt future last sent timestamp and preserves normal cooldown without warning' do
    mailbox = mailboxes(:acme_mailbox_one)

    travel_to Time.utc(2026, 3, 10, 12, 0, 0) do
      corrupt_timestamp = 6.days.from_now
      mailbox.next_available_send_at = nil
      mailbox.last_sent_at = corrupt_timestamp

      corrupt_log_output = capture_mailbox_log do
        assert mailbox.ready_to_send_now?
        assert_equal 0, mailbox.seconds_until_can_send
      end

      assert_includes corrupt_log_output, expected_corrupt_send_stamp_warning(mailbox, corrupt_timestamp)

      mailbox.next_available_send_at = nil
      mailbox.last_sent_at = 3.minutes.ago

      normal_log_output = capture_mailbox_log do
        assert_equal 480, mailbox.seconds_until_can_send
      end

      assert_empty normal_log_output
    end
  end

  test 'ready_to_send_now ignores record_send timestamp written during future travel' do
    mailbox = mailboxes(:acme_mailbox_one)
    baseline_time = Time.utc(2026, 3, 10, 12, 0, 0)

    travel_to baseline_time + 6.days do
      mailbox.record_send!
    end

    travel_to baseline_time do
      assert mailbox.ready_to_send_now?
    end
  end

  test 'next_available_send_time returns current time when enough time has passed' do
    mailbox = mailboxes(:acme_mailbox_one)
    mailbox.last_sent_at = 20.minutes.ago

    result = mailbox.next_available_send_time

    assert_in_delta Time.current, result, 2.seconds
  end

  test 'seconds_until_can_send returns 0 when never sent' do
    mailbox = mailboxes(:acme_mailbox_one)
    mailbox.last_sent_at = nil

    assert_equal 0, mailbox.seconds_until_can_send
  end

  test 'seconds_until_can_send returns 0 when enough time has passed' do
    mailbox = mailboxes(:acme_mailbox_one)
    mailbox.last_sent_at = 20.minutes.ago

    assert_equal 0, mailbox.seconds_until_can_send
  end

  test 'seconds_until_can_send returns positive value when too soon' do
    mailbox = mailboxes(:acme_mailbox_one)
    mailbox.last_sent_at = 1.minute.ago
    mailbox.next_available_send_at = 11.minutes.from_now

    result = mailbox.seconds_until_can_send

    assert result > 0, "Expected positive wait time, got #{result}"
    assert result <= 11.minutes.to_i, 'Wait time should track the persisted cooldown target'
  end

  test 'ready_to_send_now? returns true when never sent' do
    mailbox = mailboxes(:acme_mailbox_one)
    mailbox.last_sent_at = nil

    assert mailbox.ready_to_send_now?
  end

  test 'ready_to_send_now? returns false when just sent' do
    mailbox = mailboxes(:acme_mailbox_one)
    mailbox.last_sent_at = 1.minute.ago
    mailbox.next_available_send_at = 7.minutes.from_now

    refute mailbox.ready_to_send_now?
  end

  test 'ready_to_send_now? returns true when enough time has passed' do
    mailbox = mailboxes(:acme_mailbox_one)
    mailbox.last_sent_at = 20.minutes.ago

    assert mailbox.ready_to_send_now?
  end

  test 'next_send_time returns cooldown target when mailbox is in send window' do
    mailbox = mailboxes(:acme_mailbox_one)

    travel_to Time.utc(2026, 3, 10, 12, 0, 0) do
      mailbox.update!(warmup_started_at: 30.days.ago, next_available_send_at: 5.minutes.from_now)

      assert_in_delta mailbox.next_available_send_at, mailbox.next_send_time, 2.seconds
    end
  end

  test 'next_send_time returns next send window start when mailbox is outside window' do
    mailbox = mailboxes(:acme_mailbox_one)

    travel_to Time.utc(2026, 3, 10, 3, 0, 0) do
      mailbox.update!(warmup_started_at: 30.days.ago, next_available_send_at: 2.minutes.from_now)

      expected = mailbox.sender.send_window_start_time_on(mailbox.sender.local_date)
      assert_in_delta expected, mailbox.next_send_time, 2.seconds
    end
  end

  private

  def capture_mailbox_log
    output = StringIO.new
    original_logger = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(output)
    yield
    output.string
  ensure
    Rails.logger = original_logger
  end

  def expected_corrupt_send_stamp_warning(mailbox, timestamp)
    "[Mailbox] Mailbox #{mailbox.id}: ignoring corrupt future send timestamp #{timestamp.iso8601} (now=#{Time.current.iso8601}); treating mailbox as ready"
  end

  def create_agent_mailbox_daily_counter(mailbox:, send_date:, sent_count:, agent: agents(:active_agent))
    AgentMailboxDailyCounter.create!(
      agent: agent,
      mailbox: mailbox,
      send_date: send_date,
      sent_count: sent_count
    )
  end
end
