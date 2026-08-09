# frozen_string_literal: true

# Person is the global master contact record, deduplicated by email across ALL organizations.
# Stores enrichment data (LinkedIn scrape, DISC profile, company website scrape, email provider).
# Lead records reference Person and COPY enrichment data at sync time.
class Person < ApplicationRecord
  # ============================================================================
  # Constants
  # ============================================================================

  # Valid DISC profile codes
  DISC_PROFILES = %w[D I S C DI DC ID IC SC SI].freeze

  LINKEDIN_SCRAPE_CACHE_DURATION = 60.days
  LINKEDIN_POSTS_SCRAPE_CACHE_DURATION = 60.days
  LINKEDIN_PROFILE_PHOTO_CACHE_DURATION = 60.days
  COMPANY_WEBSITE_SCRAPE_CACHE_DURATION = 60.days
  EMAIL_PROVIDER_CACHE_DURATION = 90.days

  # ============================================================================
  # Associations
  # ============================================================================

  has_many :leads, dependent: :nullify
  has_many :email_aliases, class_name: 'PersonEmailAlias', dependent: :destroy, inverse_of: :person
  has_many :organizations, through: :leads
  belongs_to :current_company, class_name: 'Company', optional: true, inverse_of: :people
  has_one_attached :linkedin_profile_photo

  # ============================================================================
  # Validations
  # ============================================================================

  validates :email, presence: true,
                    format: { with: URI::MailTo::EMAIL_REGEXP, message: 'must be a valid email address' },
                    uniqueness: { case_sensitive: false }

  validates :linkedin_url, format: { with: %r{\Ahttps?://(www\.)?linkedin\.com/}i, message: 'must be a LinkedIn URL' },
                           allow_blank: true,
                           uniqueness: { allow_blank: true }

  validates :disc_profile, inclusion: { in: DISC_PROFILES }, allow_blank: true
  validates :email_provider, inclusion: { in: EmailDomain::PROVIDER_TYPES }, allow_blank: true
  validates :preferred_locale, format: {
    with: /\A[a-z]{2,3}(?:-[A-Z]{2})?\z/,
    message: 'must be a valid locale tag (e.g. en or en-US)'
  }, allow_blank: true

  # ============================================================================
  # Callbacks
  # ============================================================================

  before_validation :normalize_email
  before_validation :assign_current_company_from_snapshot,
                    if: -> { will_save_change_to_company? || will_save_change_to_company_website? || current_company_id.nil? }
  before_save :resolve_timezone, if: :will_save_change_to_location?

  # ============================================================================
  # Scopes
  # ============================================================================

  # People with LinkedIn profiles
  scope :with_linkedin, -> { where.not(linkedin_url: [nil, '']) }

  scope :needs_linkedin_scrape, lambda {
    with_linkedin.where(
      'linkedin_scraped_at IS NULL OR linkedin_scraped_at < ?',
      LINKEDIN_SCRAPE_CACHE_DURATION.ago
    )
  }

  scope :needs_linkedin_posts_scrape, lambda {
    with_linkedin.where(
      'linkedin_posts_scraped_at IS NULL OR linkedin_posts_scraped_at < ?',
      LINKEDIN_POSTS_SCRAPE_CACHE_DURATION.ago
    )
  }

  # People with LinkedIn data but no DISC profile
  scope :needs_disc_profile, lambda {
    where(disc_profile: nil)
      .where("linkedin_scraped_data != '{}'::jsonb")
  }

  # People needing email provider detection
  scope :needs_email_provider_detection, lambda {
    where(
      'email_provider_detected_at IS NULL OR email_provider_detected_at < ?',
      EMAIL_PROVIDER_CACHE_DURATION.ago
    )
  }

  # ============================================================================
  # Cache Status Methods
  # ============================================================================

  def linkedin_scrape_fresh?
    linkedin_scraped_at.present? && linkedin_scraped_at > LINKEDIN_SCRAPE_CACHE_DURATION.ago
  end

  def linkedin_scrape_stale?
    !linkedin_scrape_fresh?
  end

  def linkedin_posts_scrape_fresh?
    linkedin_posts_scraped_at.present? && linkedin_posts_scraped_at > LINKEDIN_POSTS_SCRAPE_CACHE_DURATION.ago
  end

  def linkedin_posts_scrape_stale?
    !linkedin_posts_scrape_fresh?
  end

  def company_website_scrape_fresh?
    company_website_scraped_at.present? && company_website_scraped_at > COMPANY_WEBSITE_SCRAPE_CACHE_DURATION.ago
  end

  def company_website_scrape_stale?
    !company_website_scrape_fresh?
  end

  def linkedin_profile_photo_fresh?
    linkedin_profile_photo_downloaded_at.present? &&
      linkedin_profile_photo_downloaded_at > LINKEDIN_PROFILE_PHOTO_CACHE_DURATION.ago
  end

  def linkedin_profile_photo_stale?
    !linkedin_profile_photo_fresh?
  end

  def email_provider_detection_fresh?
    email_provider_detected_at.present? && email_provider_detected_at > EMAIL_PROVIDER_CACHE_DURATION.ago
  end

  def email_provider_detection_stale?
    !email_provider_detection_fresh?
  end
  # ============================================================================
  # Update Methods
  # ============================================================================

  def update_linkedin_posts_scrape!(data)
    update!(
      linkedin_posts_scraped_data: data,
      linkedin_posts_scraped_at: Time.current,
      linkedin_posts_scrape_error: nil
    )
  end

  def update_company_website_scrape!(data)
    update!(
      company_website_scraped_data: data,
      company_website_scraped_at: Time.current,
      company_website_scrape_error: nil
    )
  end

  # Update DISC profile with metadata
  def update_disc_profile!(profile, source:, data:)
    update!(
      disc_profile: profile,
      disc_profile_source: source,
      disc_profile_data: data,
      disc_profile_assessed_at: Time.current
    )
  end

  def update_linkedin_profile_photo!(blob)
    linkedin_profile_photo.attach(blob)
    update!(
      linkedin_profile_photo_downloaded_at: Time.current,
      linkedin_profile_photo_error: nil
    )
  end

  # Update email provider from DNS detection
  def update_email_provider!(provider)
    update!(
      email_provider: provider,
      email_provider_detected_at: Time.current
    )
  end
  # ============================================================================
  # Data Accessors
  # ============================================================================

  # Returns display name with fallback chain: full_name -> first+last -> email
  def display_name
    full_name.presence || [first_name, last_name].compact.join(' ').presence || email
  end

  def learn_email_alias!(candidate_email)
    normalized_email = PersonEmailAlias.normalize_email_value(candidate_email)
    return nil if normalized_email.blank? || normalized_email == email

    email_aliases.find_or_create_by!(email: normalized_email)
  end

  def matches_email?(candidate_email)
    normalized_email = PersonEmailAlias.normalize_email_value(candidate_email)
    return false if normalized_email.blank?

    email == normalized_email || email_aliases.exists?(email: normalized_email)
  end

  # Accessor for LinkedIn headline from scraped data
  def linkedin_headline
    linkedin_scraped_data['headline']
  end

  def linkedin_summary
    linkedin_scraped_data['summary']
  end

  def linkedin_posts
    linkedin_posts_scraped_data['posts'] || []
  end

  def company_website_content
    read_attribute(:company_website_scraped_data)&.dig('content')
  end

  def company_website_scraped_data
    read_attribute(:company_website_scraped_data) || {}
  end

  def company_website_scraped_at
    read_attribute(:company_website_scraped_at)
  end

  def company_website_summary
    nil
  end

  def company_website_summary_fresh?
    false
  end

  # ============================================================================
  # Timezone Methods
  # ============================================================================

  # Returns the resolved timezone or nil
  def resolved_timezone
    timezone
  end

  # Manually triggers timezone resolution (e.g., for backfill)
  def resolve_timezone!
    resolve_timezone
    save! if timezone_changed?
  end

  private

  def normalize_email
    self.email = email&.strip&.downcase
  end

  def assign_current_company_from_snapshot
    self.current_company = Company.find_or_create_from_identity(
      name: company,
      website_url: company_website
    )
  end

  def resolve_timezone
    resolved = LocationTimezoneResolver.resolve(location)
    if resolved.present?
      self.timezone = resolved
      self.timezone_source = 'location'
      self.timezone_resolved_at = Time.current
    elsif location.blank?
      # Clear timezone if location is cleared
      self.timezone = nil
      self.timezone_source = nil
      self.timezone_resolved_at = nil
    end
    # If location is present but couldn't be resolved, keep existing timezone (don't clear it)
  end
end
