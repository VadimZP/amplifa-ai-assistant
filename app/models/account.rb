class Account < ApplicationRecord
  include Rodauth::Rails.model
  enum :status, { unverified: 1, verified: 2, closed: 3 }

  # Associations
  belongs_to :organization, optional: true
  has_many :organization_memberships, dependent: :destroy
  has_many :organizations, through: :organization_memberships
  belongs_to :impersonating, class_name: 'Account', optional: true
  has_many :admin_activities, dependent: :destroy
  has_many :conversation_reads, dependent: :destroy
  has_many :email_two_factor_challenges, dependent: :destroy

  # Constants
  ROLES = %w[amplifa_admin customer_admin customer_user].freeze
  PROTECTED_AMPLIFA_ADMIN_EMAILS = %w[admin@amplifa.com].freeze

  # Validations
  validates :email, presence: true, uniqueness: { case_sensitive: false }
  validates :first_name, presence: true, length: { maximum: 50 }
  validates :last_name, presence: true, length: { maximum: 50 }
  validates :role, inclusion: { in: ROLES }
  validates :locale, inclusion: { in: SupportedLocale::ALL, allow_nil: true }
  validate :timezone_must_be_valid, if: -> { timezone.present? }
  validate :organization_required_for_customer_roles
  validate :organization_forbidden_for_amplifa_admin
  validate :protected_amplifa_admin_identity_immutable, on: :update

  after_create :ensure_primary_organization_membership

  # Scopes
  scope :active, -> { where(deactivated_at: nil) }
  scope :amplifa_admins, -> { where(role: 'amplifa_admin') }
  scope :customer_admins, -> { where(role: 'customer_admin') }
  scope :customer_users, -> { where(role: 'customer_user') }
  scope :customers, -> { where(role: %w[customer_admin customer_user]) }
  scope :for_organization, ->(org) { where(organization_id: org.id) }

  def active_organization_memberships
    organization_memberships.active
  end

  def switchable_organization_memberships
    organization_memberships.switchable
  end

  # Status methods
  def active?
    deactivated_at.nil? && status == 'verified'
  end

  def deactivate!
    update!(deactivated_at: Time.current, status: :closed)
  end

  # Role methods
  def amplifa_admin?
    role == 'amplifa_admin'
  end

  def customer_admin?
    role == 'customer_admin'
  end

  def customer_user?
    role == 'customer_user'
  end

  def can_impersonate?
    amplifa_admin?
  end

  def requires_email_two_factor_authentication?
    account_two_factor_required = amplifa_admin? && two_factor_authentication_required?

    account_two_factor_required || organization&.two_factor_authentication_required? || false
  end

  def protected_from_admin_deletion?
    amplifa_admin? && self.class.protected_amplifa_admin_email?(email)
  end

  # Name methods
  def full_name
    "#{first_name} #{last_name}"
  end

  # Internationalization methods
  def effective_locale
    locale || organization&.locale || 'en'
  end

  def effective_timezone
    timezone.presence || 'UTC'
  end

  def self.protected_amplifa_admin_email?(email)
    PROTECTED_AMPLIFA_ADMIN_EMAILS.include?(email.to_s.downcase)
  end

  def ensure_primary_organization_membership
    return unless organization_id.present? && (customer_admin? || customer_user?)

    organization_memberships.find_or_create_by!(organization_id: organization_id) do |membership|
      membership.role = role
      membership.status = 'active'
    end
  end

  private

  def timezone_must_be_valid
    return if ActiveSupport::TimeZone[timezone]

    errors.add(:timezone, 'is not included in the list')
  end

  def organization_required_for_customer_roles
    return unless (customer_admin? || customer_user?) && organization_id.blank?

    errors.add(:organization, 'is required for customer roles')
  end

  def organization_forbidden_for_amplifa_admin
    return unless amplifa_admin? && organization_id.present?

    errors.add(:organization, 'must be blank for amplifa_admin role')
  end

  def protected_amplifa_admin_identity_immutable
    return unless role_in_database == 'amplifa_admin'
    return unless self.class.protected_amplifa_admin_email?(email_in_database)

    errors.add(:email, 'cannot be changed for protected Amplifa admins') if will_save_change_to_email?
    errors.add(:role, 'cannot be changed for protected Amplifa admins') if will_save_change_to_role?
    errors.add(:status, 'cannot be changed for protected Amplifa admins') if will_save_change_to_status?
  end
end
