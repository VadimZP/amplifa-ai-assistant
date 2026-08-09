# frozen_string_literal: true

# Represents a configured email domain (like example.com) for sending emails.
# Each domain is associated with a provider (Google Workspace or Microsoft 365)
# and the credentials are stored globally, not per-domain.
class EmailDomain < ApplicationRecord
  # Constants
  PROVIDER_TYPES = %w[google microsoft].freeze
  STATUSES = %w[active inactive error deleted].freeze
  VISIBLE_STATUSES = (STATUSES - %w[deleted]).freeze

  # Associations
  belongs_to :organization
  has_many :mailboxes, dependent: :restrict_with_error

  before_validation :normalize_domain

  # Validations
  validates :provider_type, presence: true, inclusion: { in: PROVIDER_TYPES }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :domain, presence: true
  validate :domain_must_be_unique_across_organizations
  validates :microsoft_tenant_id, presence: true, if: :microsoft?
  validates :google_admin_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true

  # Scopes
  scope :google, -> { where(provider_type: 'google') }
  scope :microsoft, -> { where(provider_type: 'microsoft') }
  scope :active, -> { where(status: 'active') }
  scope :inactive, -> { where(status: 'inactive') }
  scope :with_errors, -> { where(status: 'error') }
  scope :not_deleted, -> { where.not(status: 'deleted') }
  scope :for_organization, ->(org) { where(organization_id: org.id) }

  # Provider type predicates
  def google?
    provider_type == 'google'
  end

  def microsoft?
    provider_type == 'microsoft'
  end

  # Status predicates
  def active?
    status == 'active'
  end

  def inactive?
    status == 'inactive'
  end

  def error?
    status == 'error'
  end

  def deleted?
    status == 'deleted'
  end

  def destroy_with_mailboxes!
    transaction do
      if mailboxes.joins(:conversations).exists?
        soft_delete_mailboxes!
      else
        hard_delete_with_mailboxes!
      end
    end
  end

  def mark_deleted!
    update!(status: 'deleted')
  end

  # Checks if a given email address belongs to this domain
  def domain_for_email?(email)
    return false if domain.blank? || email.blank?

    email_domain_part = email.to_s.split('@').last&.downcase
    domain.downcase == email_domain_part
  end

  # Records a successful verification
  def mark_verified!
    update!(
      status: 'active',
      last_verified_at: Time.current,
      verification_error: nil
    )
  end

  # Records a verification failure
  def mark_verification_error!(error_message)
    update!(
      status: 'error',
      verification_error: error_message
    )
  end

  private

  def soft_delete_mailboxes!
    mailboxes.find_each(&:mark_deleted!)
    mark_deleted!
    :soft_deleted
  end

  def hard_delete_with_mailboxes!
    mailboxes.find_each(&:destroy_for_domain_deletion!)
    destroy!
    :destroyed
  end

  def normalize_domain
    self.domain = domain.to_s.strip.downcase if domain.present?
  end

  def domain_must_be_unique_across_organizations
    return if domain.blank?

    existing_domain = EmailDomain
                      .not_deleted
                      .includes(:organization)
                      .where('LOWER(domain) = ?', domain.downcase)
                      .where.not(id: id)
                      .first
    return unless existing_domain

    if existing_domain.organization_id == organization_id
      errors.add(:domain, 'The domain already exists in the current organization.')
    else
      errors.add(:domain,
                 "The domain already exists in another organization, <b>#{existing_domain.organization.name}</b>.")
    end
  end
end
