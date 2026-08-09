# frozen_string_literal: true

# Represents a person who sends outreach messages in an organization.
# Each sender can have multiple mailboxes (email addresses) and stores
# profile information used for signatures and future LinkedIn automation.
class Sender < ApplicationRecord
  # Constants
  STATUSES = %w[active inactive].freeze
  UTC_TIMEZONE_IDENTIFIER = 'UTC'

  def self.timezone_options(reference_time: Time.current)
    ActiveSupport::TimeZone.all.map do |timezone|
      identifier = timezone_identifier(timezone)
      offset = reference_time.in_time_zone(timezone).formatted_offset

      [identifier, "(UTC#{offset}) #{identifier}"]
    end
  end

  # Associations
  belongs_to :organization
  has_many :mailboxes, dependent: :nullify
  has_many :meetings, dependent: :nullify
  has_one_attached :profile_photo

  # Validations
  validates :first_name, presence: true
  validates :last_name, presence: true
  validates :email, presence: true,
                    format: { with: URI::MailTo::EMAIL_REGEXP },
                    uniqueness: { scope: :organization_id, case_sensitive: false }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :linkedin_url,
            format: { with: %r{\Ahttps?://(www\.)?linkedin\.com/in/}, message: 'must be a valid LinkedIn profile URL' },
            allow_blank: true
  validate :acceptable_profile_photo

  # Send window validations
  validates :timezone, presence: true
  validate :timezone_is_valid_iana
  validates :send_window_start_hour, presence: true,
                                     numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 23, message: 'must be between 0 and 23' }
  validates :send_window_end_hour, presence: true,
                                   numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 23, message: 'must be between 0 and 23' }
  validates :send_window_start_minute, presence: true, inclusion: { in: [0, 30], message: 'must be 0 or 30' }
  validates :send_window_end_minute, presence: true, inclusion: { in: [0, 30], message: 'must be 0 or 30' }
  validate :send_window_start_before_end

  # Scopes
  scope :active, -> { where(status: 'active') }
  scope :inactive, -> { where(status: 'inactive') }

  # Callbacks
  before_validation :normalize_email

  # Status predicates
  def active?
    status == 'active'
  end

  def inactive?
    status == 'inactive'
  end

  # Name helpers
  def full_name
    "#{first_name} #{last_name}"
  end

  def display_name
    nickname.presence || first_name
  end

  # Capacity helpers
  def total_daily_capacity
    mailboxes.not_deleted.active.sum(:daily_send_limit)
  end

  def total_remaining_capacity
    mailboxes.not_deleted.active.sum(&:daily_capacity_remaining)
  end

  def mailbox_count
    mailboxes.not_deleted.count
  end

  def active_mailbox_count
    mailboxes.not_deleted.active.count
  end

  # Signature rendering (delegate to service)
  def rendered_signature
    SignatureRenderer.new(self).render
  end

  def rendered_signature_for(lead:, agent: nil, agent_lead: nil)
    SignatureRenderer.new(self, lead: lead, agent: agent, agent_lead: agent_lead).render
  end

  # Send window helper methods
  def send_window_start_time_on(date)
    tz = ActiveSupport::TimeZone.new(timezone)
    tz.local(date.year, date.month, date.day, send_window_start_hour, send_window_start_minute)
  end

  def send_window_end_time_on(date)
    tz = ActiveSupport::TimeZone.new(timezone)
    tz.local(date.year, date.month, date.day, send_window_end_hour, send_window_end_minute)
  end

  def local_time(time = Time.current)
    tz = ActiveSupport::TimeZone.new(timezone)
    time.in_time_zone(tz)
  end

  def local_date(time = Time.current)
    tz = ActiveSupport::TimeZone.new(timezone)
    time.in_time_zone(tz).to_date
  end

  def weekend?(time = Time.current)
    tz = ActiveSupport::TimeZone.new(timezone)
    time.in_time_zone(tz).saturday? || time.in_time_zone(tz).sunday?
  end

  def in_send_window?(time = Time.current)
    # Convert time to sender's timezone
    tz = ActiveSupport::TimeZone.new(timezone)
    local_time = time.in_time_zone(tz)

    # Get start and end times for the same date
    start_time = send_window_start_time_on(local_time.to_date)
    end_time = send_window_end_time_on(local_time.to_date)

    # Check if time is within window (inclusive start, exclusive end)
    local_time >= start_time && local_time < end_time
  end

  private

  def normalize_email
    self.email = email.to_s.strip.downcase
  end

  def timezone_is_valid_iana
    return if timezone.blank?

    tz = ActiveSupport::TimeZone.new(timezone)
    errors.add(:timezone, 'is not a valid timezone') if tz.nil?
  end

  def send_window_start_before_end
    return if send_window_start_hour.blank? || send_window_end_hour.blank?

    start_minutes = (send_window_start_hour * 60) + send_window_start_minute.to_i
    end_minutes = (send_window_end_hour * 60) + send_window_end_minute.to_i

    return if start_minutes < end_minutes

    errors.add(:send_window_start_hour, 'must be before end time')
  end

  def acceptable_profile_photo
    return unless profile_photo.attached?

    # File size validation (4MB max for Microsoft 365 compatibility)
    errors.add(:profile_photo, 'must be less than 4MB') if profile_photo.byte_size > 4.megabytes

    # Content type validation (JPEG/PNG only for cross-platform compatibility)
    acceptable_types = ['image/jpeg', 'image/png']
    return if acceptable_types.include?(profile_photo.content_type)

    errors.add(:profile_photo, 'must be JPEG or PNG')
  end

  def self.timezone_identifier(timezone)
    timezone.tzinfo.name == 'Etc/UTC' ? UTC_TIMEZONE_IDENTIFIER : timezone.tzinfo.name
  end
  private_class_method :timezone_identifier
end
