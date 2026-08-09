# frozen_string_literal: true

class Lead < ApplicationRecord
  EMAIL_DOMAIN_SQL = "LOWER(split_part(leads.email, '@', 2))"
  COMPANY_WEBSITE_DOMAIN_SQL = <<~SQL.squish.freeze
    regexp_replace(
      split_part(
        regexp_replace(lower(coalesce(leads.company_website, '')), '^https?://', ''),
        '/',
        1
      ),
      '^www\.',
      ''
    )
  SQL
  # ============================================================================
  # Associations
  # ============================================================================

  belongs_to :organization
  belongs_to :lead_import, optional: true
  belongs_to :person, optional: true # Global master contact record
  has_many :agent_leads, dependent: :destroy
  has_many :agents, through: :agent_leads
  has_many :meetings, dependent: :destroy

  delegate :company_website_summary, :current_company, to: :person, allow_nil: true

  # ============================================================================
  # Validations
  # ============================================================================

  validates :email, presence: true,
                    format: { with: URI::MailTo::EMAIL_REGEXP, message: 'must be a valid email address' },
                    uniqueness: { scope: :organization_id, case_sensitive: false }
  validates :organization, presence: true
  validates :linkedin_url, format: { with: %r{\Ahttps?://(www\.)?linkedin\.com/}i, message: 'must be a LinkedIn URL' },
                           allow_blank: true
  validate :validate_company_website_format

  enum :blacklist_reason_category, Blacklist::REASON_CATEGORIES, prefix: true

  # ============================================================================
  # Callbacks
  # ============================================================================

  before_validation :normalize_email

  # ============================================================================
  # Scopes
  # ============================================================================

  scope :for_organization, ->(org) { where(organization_id: org.id) }
  scope :not_blacklisted, -> { where(blacklisted: false) }
  scope :blacklisted, -> { where(blacklisted: true) }
  scope :effectively_not_blacklisted, -> { not_blacklisted }
  scope :effectively_not_blacklisted_for, lambda { |organization|
    relation = organization.present? ? where(organization_id: organization.id) : all
    relation.effectively_not_blacklisted
  }
  scope :visible_in_customer_agents, lambda {
    where(blacklisted: false)
      .or(
        where(
          blacklisted: true,
          blacklist_reason_category: Blacklist.customer_visible_reply_reason_categories
        )
      )
  }
  scope :visible_in_customer_agents_for, lambda { |organization|
    relation = organization.present? ? where(organization_id: organization.id) : all
    relation.visible_in_customer_agents
  }
  scope :with_email_domain, ->(domain) { where('email LIKE ?', "%@#{domain}") }
  scope :recent, -> { order(created_at: :desc) }
  scope :by_company, ->(company) { where(company: company) }
  scope :with_person, -> { where.not(person_id: nil) }
  scope :without_person, -> { where(person_id: nil) }
  scope :with_hubspot_id, -> { where.not(hubspot_contact_id: [nil, '']) }
  scope :with_pipedrive_id, -> { where.not(pipedrive_person_id: [nil, '']) }
  scope :with_pipedrive_organization_id, -> { where.not(pipedrive_organization_id: [nil, '']) }
  scope :with_pipedrive_deal_id, -> { where.not(pipedrive_deal_id: [nil, '']) }
  scope :with_salesforce_contact_id, -> { where.not(salesforce_contact_id: [nil, '']) }
  scope :with_salesforce_opportunity_id, -> { where.not(salesforce_opportunity_id: [nil, '']) }

  # ============================================================================
  # Class Methods
  # ============================================================================

  def self.create_from_person!(organization:, person:, additional_attrs: {})
    create!(
      organization: organization,
      person: person,
      email: person.email,
      first_name: person.first_name,
      last_name: person.last_name,
      full_name: person.full_name,
      job_title: person.job_title,
      company: person.company,
      company_website: person.company_website,
      location: person.location,
      linkedin_url: person.linkedin_url,
      **additional_attrs
    )
  end

  # Finds or creates a Lead linked to a Person (creates Person if needed)
  def self.find_or_create_with_person!(organization:, email:, attributes: {})
    # Find existing lead in this org
    lead = find_by(organization: organization, email: email.strip.downcase)
    return lead if lead

    # Find or create the global Person
    person = Person.find_or_create_by!(email: email.strip.downcase) do |p|
      p.first_name = attributes[:first_name]
      p.last_name = attributes[:last_name]
      p.full_name = attributes[:full_name]
      p.job_title = attributes[:job_title]
      p.company = attributes[:company]
      p.company_website = attributes[:company_website]
      p.location = attributes[:location]
      p.linkedin_url = attributes[:linkedin_url]
    end

    # Create the lead linked to person
    create_from_person!(organization: organization, person: person, additional_attrs: attributes.except(
      :first_name, :last_name, :full_name, :job_title, :company,
      :company_website, :location, :linkedin_url
    ))
  end

  # ============================================================================
  # Instance Methods
  # ============================================================================

  def disc_profile
    person&.disc_profile
  end

  def linkedin_scraped_data
    person&.linkedin_scraped_data || {}
  end

  def linkedin_scraped_at
    person&.linkedin_scraped_at
  end

  def linkedin_posts_scraped_data
    person&.linkedin_posts_scraped_data || {}
  end

  def linkedin_posts_scraped_at
    person&.linkedin_posts_scraped_at
  end

  def company_website_scraped_data
    person&.company_website_scraped_data || {}
  end

  def company_website_scraped_at
    person&.company_website_scraped_at
  end

  def disc_profile_assessed_at
    person&.disc_profile_assessed_at
  end

  def linkedin_headline
    person&.linkedin_headline
  end

  def linkedin_summary
    person&.linkedin_summary
  end

  def company_website_content
    person&.company_website_content
  end

  def linkedin_posts
    person&.linkedin_posts || []
  end

  def timezone
    person&.timezone
  end

  def latest_buying_signals_summary
    nil
  end

  def timezone_resolved_at
    person&.timezone_resolved_at
  end

  def email_provider
    person&.email_provider
  end

  def preferred_locale
    person&.preferred_locale
  end

  def locale_source
    person&.locale_source
  end

  def display_name
    full_name.presence || [first_name, last_name].compact.join(' ').presence || email
  end

  def hubspot_linked?
    hubspot_contact_id.present?
  end

  def pipedrive_linked?
    pipedrive_person_id.present?
  end

  def pipedrive_organization_linked?
    pipedrive_organization_id.present?
  end

  def pipedrive_deal_linked?
    pipedrive_deal_id.present?
  end

  def salesforce_contact_linked?
    salesforce_contact_id.present?
  end

  def salesforce_opportunity_linked?
    salesforce_opportunity_id.present?
  end

  def sync_from_person!
    return self unless person

    update!(
      email: person.email,
      first_name: person.first_name,
      last_name: person.last_name,
      full_name: person.full_name,
      job_title: person.job_title,
      company: person.company,
      company_website: person.company_website,
      location: person.location,
      linkedin_url: person.linkedin_url
    )
  end

  # Marks the lead as blacklisted with a reason
  def blacklist!(reason:, category: nil)
    update!(
      blacklisted: true,
      blacklist_reason: reason,
      blacklist_reason_category: category || Blacklist.reason_category_for_reason(reason),
      blacklisted_at: Time.current
    )
  end

  # Removes the blacklist flag from the lead
  def unblacklist!
    update!(
      blacklisted: false,
      blacklist_reason: nil,
      blacklist_reason_category: nil,
      blacklisted_at: nil
    )
  end

  # Extracts the domain from the email address
  def email_domain
    email&.split('@')&.last
  end

  def company_website_domain
    self.class.normalize_domain(company_website)
  end

  def self.normalize_domain(value)
    return if value.blank?

    normalized = value.to_s.strip.downcase
    normalized = "https://#{normalized}" unless normalized.match?(%r{\Ahttps?://}i)

    host = URI.parse(normalized).host&.downcase
    host&.sub(/\Awww\./, '')
  rescue URI::InvalidURIError
    nil
  end

  private

  def normalize_email
    self.email = email&.strip&.downcase
  end

  # Custom URL validation that accepts domain-only formats like "example.com"
  # in addition to full URLs like "https://example.com"
  def validate_company_website_format
    return if company_website.blank?

    url = company_website.strip

    # If it looks like a full URL with protocol, validate using standard URI parser
    if url.match?(%r{\Ahttps?://}i)
      begin
        uri = URI.parse(url)
        errors.add(:company_website, 'must be a valid URL') unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
      rescue URI::InvalidURIError
        errors.add(:company_website, 'must be a valid URL')
      end
    else
      # Domain-only format: validate it looks like a valid domain
      # Matches: example.com, www.example.com, sub.domain.example.co.uk
      domain_regex = /\A[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+\z/i
      errors.add(:company_website, 'must be a valid URL or domain') unless url.match?(domain_regex)
    end
  end
end
