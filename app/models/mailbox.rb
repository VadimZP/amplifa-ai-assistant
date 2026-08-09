# frozen_string_literal: true

# Represents an email mailbox for API-based sending via Google/Microsoft.
# No SMTP/IMAP credentials stored - uses the email_domain's domain-wide delegation.
class Mailbox < ApplicationRecord
  # Constants
  STATUSES = %w[active paused suspended deleted].freeze
  VISIBLE_STATUSES = (STATUSES - %w[deleted]).freeze
  GOOGLE_MAIL_SERVICE_DISABLED_ERROR = 'failedPrecondition: Mail service not enabled'
  WARMUP_DAYS = 21

  attr_writer :preloaded_daily_sends_today

  # Minimum seconds between sends from the same mailbox (7 minutes)
  MIN_SEND_SPACING_SECONDS = 7 * 60
  # Maximum additional random delay (4 minutes)
  MAX_SEND_SPACING_JITTER_SECONDS = 4 * 60
  MAX_LEGITIMATE_COOLDOWN_SECONDS = MIN_SEND_SPACING_SECONDS + MAX_SEND_SPACING_JITTER_SECONDS
  COOLDOWN_CORRUPTION_GRACE_SECONDS = 60

  # Associations
  belongs_to :email_domain
  belongs_to :organization
  belongs_to :sender, optional: true
  has_many :agent_mailboxes, dependent: :destroy
  has_many :agents, through: :agent_mailboxes
  has_many :generated_messages, dependent: :restrict_with_error
  has_many :replies, dependent: :restrict_with_error
  has_many :conversations, dependent: :restrict_with_error
  has_many :sent_replies, dependent: :restrict_with_error

  # Validations
  validates :email, presence: true,
                    uniqueness: { conditions: -> { not_deleted } },
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :daily_send_limit, presence: true,
                               numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 2000 }
  validate :email_matches_email_domain
  validate :same_organization_as_email_domain

  # Scopes
  scope :active, -> { where(status: 'active') }
  scope :paused, -> { where(status: 'paused') }
  scope :suspended, -> { where(status: 'suspended') }
  scope :not_deleted, -> { where.not(status: 'deleted') }
  scope :for_organization, ->(org) { where(organization_id: org&.id) }
  scope :with_capacity, -> { active.where('daily_send_limit > 0') }
  scope :warmup_complete, lambda {
    where('warmup_started_at IS NULL OR warmup_started_at <= ?', WARMUP_DAYS.days.ago)
  }

  # Status predicates
  def active?
    status == 'active'
  end

  def paused?
    status == 'paused'
  end

  def suspended?
    status == 'suspended'
  end

  def deleted?
    status == 'deleted'
  end

  def mark_deleted!
    transaction do
      agent_mailboxes.destroy_all
      AgentLead.where(assigned_mailbox_id: id).update_all(assigned_mailbox_id: nil)
      update!(status: 'deleted', sender: nil)
    end
  end

  def destroy_for_domain_deletion!
    transaction do
      if conversations.exists?
        mark_deleted!
      else
        remove_domain_deletion_blockers!
        destroy!
      end
    end
  end

  # Returns the number of emails sent today from this mailbox
  def daily_sends_today
    return @preloaded_daily_sends_today if instance_variable_defined?(:@preloaded_daily_sends_today)

    generated_messages
      .where(status: 'sent', sent_at: local_send_date.beginning_of_day..local_send_date.end_of_day)
      .count
  end

  # Returns remaining capacity for today
  def daily_capacity_remaining
    [daily_send_limit - daily_sends_today, 0].max
  end

  # Checks if this mailbox can send more emails today
  def has_capacity?
    daily_capacity_remaining > 0
  end

  # Checks if warmup period is complete
  def warmup_complete?
    return true if warmup_started_at.nil?

    warmup_started_at <= WARMUP_DAYS.days.ago
  end

  # Returns warmup progress as a percentage (0-100)
  def warmup_progress_percentage
    return 100 if warmup_started_at.nil?
    return 100 if warmup_complete?

    days_elapsed = ((Time.current - warmup_started_at) / 1.day).floor
    [(days_elapsed.to_f / WARMUP_DAYS * 100).round, 100].min
  end

  # Returns days remaining in warmup
  def warmup_days_remaining
    return 0 if warmup_started_at.nil? || warmup_complete?

    days_elapsed = ((Time.current - warmup_started_at) / 1.day).floor
    [WARMUP_DAYS - days_elapsed, 0].max
  end

  def has_sender?
    sender_id.present?
  end

  # Checks if this mailbox can send (active, has capacity, warmup complete, has sender)
  def can_send?
    active? && has_capacity? && warmup_complete? && has_sender?
  end

  def sendable_now?
    active? && warmup_complete? && has_sender? && has_capacity? && ready_to_send_now?
  end

  # Full display name for email sending
  def full_display_name
    return display_name if display_name.present?
    return "#{first_name} #{last_name}".strip if first_name.present? || last_name.present?

    email.split('@').first
  end

  # Returns sender's full name with fallback to mailbox name
  def sender_full_name
    sender&.full_name || "#{first_name} #{last_name}".strip.presence || email.split('@').first
  end

  # Returns sender's display name with fallback to mailbox name
  def sender_display_name
    sender&.display_name || first_name.presence || email.split('@').first
  end

  delegate :provider_type, :google?, :microsoft?, to: :email_domain

  def recently_polled?
    last_polled_at.present? && last_polled_at > 30.minutes.ago
  end

  def polling_status
    return 'never' if last_polled_at.nil?
    return 'error' if last_poll_error.present?
    return 'recent' if recently_polled?

    'stale'
  end

  def mark_polled!(error: nil)
    update!(
      last_polled_at: Time.current,
      last_poll_error: error
    )
  end

  def mark_poll_error!(error, suspend: false)
    attributes = {
      last_polled_at: Time.current,
      last_poll_error: error
    }
    attributes[:status] = 'suspended' if suspend

    update!(attributes)
  end

  def google_mail_service_disabled_error?(error_message)
    error_message.to_s.include?(GOOGLE_MAIL_SERVICE_DISABLED_ERROR)
  end

  def self.cooldown_duration_seconds
    MIN_SEND_SPACING_SECONDS + rand(MAX_SEND_SPACING_JITTER_SECONDS + 1)
  end

  # Records when an email was sent from this mailbox.
  # Used for per-mailbox send spacing to ensure human-like sending patterns.
  def record_send!
    sent_at = Time.current
    update!(
      last_sent_at: sent_at,
      next_available_send_at: sent_at + self.class.cooldown_duration_seconds.seconds
    )
  end

  # Returns the earliest time this mailbox can send the next email.
  # Uses the persisted next_available_send_at when present so cooldown checks
  # and loop scheduling share the same exact target time.
  # The corruption guard lives on the read side because a travel_to'd writer stamps
  # a legitimate-looking Time.current, so record_send! cannot self-validate. Corrupt
  # values become ready-now instead of rolling-clamped because min(stored, now + bound)
  # recomputes on each read and never expires. The accepted tradeoff is that a backward
  # system-clock jump greater than the grace can release a send up to ~11 min early,
  # which is benign.
  # @return [Time] The earliest allowed send time
  def next_available_send_time
    if next_available_send_at.present?
      return Time.current if corrupt_future_send_stamp?(next_available_send_at)

      return [next_available_send_at, Time.current].max
    end

    return Time.current if last_sent_at.nil?
    return Time.current if corrupt_future_send_stamp?(last_sent_at)

    fallback_time = last_sent_at + MIN_SEND_SPACING_SECONDS.seconds + MAX_SEND_SPACING_JITTER_SECONDS.seconds
    [fallback_time, Time.current].max
  end

  def next_send_time
    return nil unless active? && warmup_complete? && has_sender? && has_capacity?

    [next_available_send_time, next_send_window_open_at].compact.max
  end

  # Returns seconds until this mailbox can send again, or 0 if ready now.
  # @return [Integer] Seconds to wait before sending
  def seconds_until_can_send
    wait_time = (next_available_send_time - Time.current).to_i
    [wait_time, 0].max
  end

  # Checks if this mailbox is ready to send now (respects send spacing).
  # @return [Boolean] True if enough time has passed since last send
  def ready_to_send_now?
    seconds_until_can_send.zero?
  end

  def next_send_window_open_at(from: Time.current)
    return nil unless sender.present?

    local_time = sender.local_time(from)
    current_date = local_time.to_date

    loop do
      start_time = sender.send_window_start_time_on(current_date)
      end_time = sender.send_window_end_time_on(current_date)

      if start_time.saturday? || start_time.sunday?
        current_date += 1.day
        next
      end

      return local_time if local_time >= start_time && local_time < end_time
      return start_time if local_time < start_time

      current_date += 1.day
    end
  end

  private

  def corrupt_future_send_stamp?(timestamp)
    return false unless timestamp > Time.current + (MAX_LEGITIMATE_COOLDOWN_SECONDS + COOLDOWN_CORRUPTION_GRACE_SECONDS).seconds

    Rails.logger.warn("[Mailbox] Mailbox #{id}: ignoring corrupt future send timestamp #{timestamp.iso8601} (now=#{Time.current.iso8601}); treating mailbox as ready")
    true
  end

  def remove_domain_deletion_blockers!
    agent_mailboxes.destroy_all
    AgentLead.where(assigned_mailbox_id: id).update_all(assigned_mailbox_id: nil)
    generated_messages.update_all(mailbox_id: nil)
    sent_replies.destroy_all
    replies.destroy_all
  end

  def local_send_date
    sender ? sender.local_date : Date.current
  end

  def email_matches_email_domain
    return unless email.present? && email_domain.present?

    return if email_domain.domain_for_email?(email)

    errors.add(:email, "must match the email domain (#{email_domain.domain})")
  end

  def same_organization_as_email_domain
    return unless email_domain.present? && organization.present?

    return unless email_domain.organization_id != organization_id

    errors.add(:email_domain, 'must belong to the same organization')
  end
end
