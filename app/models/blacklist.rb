# frozen_string_literal: true

class Blacklist < ApplicationRecord
  # Constants
  VALUE_TYPES = %w[email domain].freeze
  SOURCES = %w[manual import unsubscribe interested].freeze
  DOMAIN_VALUE_PATTERN = /\A(?:\*|[a-z0-9][a-z0-9-]*)(?:\.(?:\*|[a-z0-9][a-z0-9-]*))+\z/i
  LEADING_WILDCARD_APEX_PATTERN = /\A\*\.[^.]+\z/i
  USER_SELECTABLE_SOURCES = %w[manual import unsubscribe].freeze
  REASON_CATEGORIES = {
    other: 'other',
    reply_interested: 'reply_interested',
    reply_not_interested: 'reply_not_interested',
    reply_wrong_person: 'reply_wrong_person'
  }.freeze
  CUSTOMER_VISIBLE_REPLY_INTEREST_STATUSES = %w[interested meeting_request not_interested wrong_person].freeze
  CUSTOMER_VISIBLE_REPLY_REASON_CATEGORIES = %w[reply_interested reply_not_interested reply_wrong_person].freeze
  INTEREST_STATUS_SOURCES = {
    'interested' => 'interested',
    'meeting_request' => 'interested',
    'not_interested' => 'unsubscribe',
    'wrong_person' => 'unsubscribe'
  }.freeze
  INTEREST_STATUS_REASON_CATEGORIES = {
    'interested' => REASON_CATEGORIES[:reply_interested],
    'meeting_request' => REASON_CATEGORIES[:reply_interested],
    'not_interested' => REASON_CATEGORIES[:reply_not_interested],
    'wrong_person' => REASON_CATEGORIES[:reply_wrong_person]
  }.freeze
  ORGANIZATION_PRIORITY_SQL = Arel.sql('organization_id IS NULL ASC')
  VALUE_TYPE_PRIORITY_SQL = Arel.sql("CASE WHEN value_type = 'email' THEN 0 ELSE 1 END")
  WILDCARD_PRIORITY_SQL = Arel.sql("CASE WHEN value LIKE '%*%' THEN 1 ELSE 0 END")

  # Associations
  belongs_to :organization, optional: true
  belongs_to :created_by, class_name: 'Account'

  # Callbacks
  before_destroy :store_unbackfill_attributes
  after_commit :backfill_blacklisted_leads, on: :create
  after_commit :unbackfill_blacklisted_leads, on: :destroy

  # Validations
  validates :value, presence: true
  validates :value_type, presence: true, inclusion: { in: VALUE_TYPES }
  validates :source, presence: true, inclusion: { in: SOURCES }
  validates :value, uniqueness: { scope: %i[organization_id value_type],
                                  message: 'is already blacklisted' }
  validate :value_format_matches_type

  enum :reason_category, REASON_CATEGORIES, prefix: true

  # Scopes
  scope :for_organization, ->(org) { where(organization_id: org.id) }
  scope :global, -> { where(organization_id: nil) }
  scope :emails, -> { where(value_type: 'email') }
  scope :domains, -> { where(value_type: 'domain') }
  scope :recent, -> { order(created_at: :desc) }

  def self.blacklisted?(email:, organization:, company_website: nil)
    return false if email.blank?

    matching_blacklist_entry(email: email, organization: organization, company_website: company_website).present?
  end

  def self.reply_interest_reason(interest_status, manual: false)
    prefix = manual ? 'Auto-blacklisted from manually set interest tag' : 'Auto-blacklisted from reply interest tag'
    "#{prefix}: #{interest_status.to_s.humanize}"
  end

  def self.reply_interest_reason_category(interest_status)
    INTEREST_STATUS_REASON_CATEGORIES.fetch(interest_status.to_s)
  end

  def self.reply_interest_source(interest_status)
    INTEREST_STATUS_SOURCES.fetch(interest_status.to_s)
  end

  def self.customer_visible_reply_reason_categories
    CUSTOMER_VISIBLE_REPLY_REASON_CATEGORIES
  end

  def self.reason_category_for_reason(reason, source: nil)
    case source.to_s
    when ''
      infer_reply_reason_category(reason)
    when 'interested'
      return REASON_CATEGORIES[:reply_interested] if reason == reply_interest_reason('interested')
      return REASON_CATEGORIES[:reply_interested] if reason == reply_interest_reason('interested', manual: true)
      return REASON_CATEGORIES[:reply_interested] if reason == reply_interest_reason('meeting_request')
      return REASON_CATEGORIES[:reply_interested] if reason == reply_interest_reason('meeting_request', manual: true)

      REASON_CATEGORIES[:other]
    when 'unsubscribe'
      infer_unsubscribe_reply_reason_category(reason)
    else
      REASON_CATEGORIES[:other]
    end
  end

  def self.upsert_reply_interest_entry!(lead:, interest_status:, actor:, reason: nil)
    upsert_reply_interest_email_entry!(
      organization: lead.organization,
      email: lead.email,
      interest_status: interest_status,
      actor: actor,
      reason: reason
    )
  end

  def self.upsert_reply_interest_email_entry!(organization:, email:, interest_status:, actor:, reason: nil)
    return if email.blank?

    normalized_email = normalize_email(email)
    entry = where(organization: organization, value_type: 'email')
            .where('LOWER(value) = ?', normalized_email)
            .first
    entry ||= new(organization: organization, value: normalized_email, value_type: 'email')
    entry.created_by ||= actor
    entry.source = reply_interest_source(interest_status)
    entry.reason = reason || reply_interest_reason(interest_status)
    entry.reason_category = reply_interest_reason_category(interest_status)
    entry.save!
  end

  def self.blacklist_reason_attributes(email:, organization:, company_website: nil)
    entry = matching_blacklist_entry(email: email, organization: organization, company_website: company_website)

    return nil unless entry

    {
      reason: entry.effective_reason,
      category: entry.reason_category.presence || REASON_CATEGORIES[:other]
    }
  end

  # Returns the reason for blacklisting (from the first matching entry)
  def self.blacklist_reason(email:, organization:, company_website: nil)
    blacklist_reason_attributes(
      email: email,
      organization: organization,
      company_website: company_website
    )&.fetch(:reason)
  end

  # Returns true if this is a global blacklist entry (no organization)
  def global?
    organization_id.nil?
  end

  def effective_reason
    reason.presence || self.class.default_reason_for(self)
  end

  def self.matching_blacklist_entry(email:, organization:, company_website: nil)
    return if email.blank?

    normalized_email = normalize_email(email)
    domains = candidate_domains(normalized_email, company_website)
    scope = applicable_scope(organization)

    email_entry = ordered_blacklist_scope(scope.emails).where('LOWER(value) = ?', normalized_email).first
    domain_entry = matching_domain_entry(ordered_blacklist_scope(scope.domains), domains)

    [email_entry, domain_entry].compact.min_by { |entry| entry_priority(entry) }
  end

  def self.matching_domain_entry(scope, domains)
    return if domains.empty?

    exact_entry = scope.where('LOWER(value) IN (?)', domains).first
    return exact_entry if exact_entry

    wildcard_conditions = Array.new(domains.size, "LOWER(?) LIKE REPLACE(LOWER(value), '*', '%')").join(' OR ')
    scope.where("value LIKE '%*%'").where(wildcard_conditions, *domains).first
  end

  def self.applicable_scope(organization)
    where('organization_id IS NULL OR organization_id = ?', organization&.id)
  end

  def self.ordered_blacklist_scope(scope)
    scope.order(ORGANIZATION_PRIORITY_SQL).order(VALUE_TYPE_PRIORITY_SQL).order(WILDCARD_PRIORITY_SQL).order(:id)
  end

  def self.candidate_domains(email, company_website)
    [email.split('@').last, Lead.normalize_domain(company_website)].compact.map(&:downcase).uniq
  end

  def self.normalize_email(email)
    email.to_s.strip.downcase
  end

  def self.entry_priority(entry)
    [
      entry.organization_id.nil? ? 1 : 0,
      entry.value_type == 'email' ? 0 : 1,
      entry.value.include?('*') ? 1 : 0,
      entry.id
    ]
  end

  def self.sql_like_pattern(value)
    value.to_s.strip.downcase.tr('*', '%')
  end

  def self.default_reason_for(entry)
    type_label = entry.value_type == 'domain' ? 'domain' : 'address'
    scope_label = entry.global? ? 'global' : 'organization'
    "Email #{type_label} on #{scope_label} blacklist"
  end

  private_class_method :matching_blacklist_entry, :matching_domain_entry, :applicable_scope,
                       :candidate_domains, :normalize_email, :ordered_blacklist_scope,
                       :entry_priority
  public_class_method :sql_like_pattern, :default_reason_for

  def backfill_blacklisted_leads
    BackfillBlacklistedLeadsJob.perform_later(id)
  end

  def unbackfill_blacklisted_leads
    UnbackfillBlacklistedLeadsJob.perform_later(@unbackfill_attributes)
  end

  def store_unbackfill_attributes
    @unbackfill_attributes = {
      organization_id: organization_id,
      value: value,
      value_type: value_type
    }
  end

  def value_format_matches_type
    return if value.blank? || value_type.blank?

    case value_type
    when 'email'
      errors.add(:value, 'must be a valid email address') unless value.match?(URI::MailTo::EMAIL_REGEXP)
    when 'domain'
      unless value.match?(DOMAIN_VALUE_PATTERN) && !value.match?(LEADING_WILDCARD_APEX_PATTERN)
        errors.add(:value,
                   'must be a valid domain')
      end
    end
  end

  def self.infer_reply_reason_category(reason)
    return REASON_CATEGORIES[:reply_interested] if reason == reply_interest_reason('interested')
    return REASON_CATEGORIES[:reply_interested] if reason == reply_interest_reason('interested', manual: true)
    return REASON_CATEGORIES[:reply_interested] if reason == reply_interest_reason('meeting_request')
    return REASON_CATEGORIES[:reply_interested] if reason == reply_interest_reason('meeting_request', manual: true)
    return REASON_CATEGORIES[:reply_not_interested] if reason == reply_interest_reason('not_interested')
    return REASON_CATEGORIES[:reply_not_interested] if reason == reply_interest_reason('not_interested', manual: true)
    return REASON_CATEGORIES[:reply_wrong_person] if reason == reply_interest_reason('wrong_person')
    return REASON_CATEGORIES[:reply_wrong_person] if reason == reply_interest_reason('wrong_person', manual: true)

    REASON_CATEGORIES[:other]
  end
  private_class_method :infer_reply_reason_category

  def self.infer_unsubscribe_reply_reason_category(reason)
    return REASON_CATEGORIES[:reply_not_interested] if reason == reply_interest_reason('not_interested')
    return REASON_CATEGORIES[:reply_not_interested] if reason == reply_interest_reason('not_interested', manual: true)
    return REASON_CATEGORIES[:reply_wrong_person] if reason == reply_interest_reason('wrong_person')
    return REASON_CATEGORIES[:reply_wrong_person] if reason == reply_interest_reason('wrong_person', manual: true)

    REASON_CATEGORIES[:other]
  end
  private_class_method :infer_unsubscribe_reply_reason_category
end
