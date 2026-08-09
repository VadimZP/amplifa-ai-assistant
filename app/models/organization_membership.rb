class OrganizationMembership < ApplicationRecord
  ROLES = %w[customer_admin customer_user].freeze
  STATUSES = %w[active inactive].freeze

  belongs_to :account
  belongs_to :organization

  validates :role, inclusion: { in: ROLES }
  validates :status, inclusion: { in: STATUSES }
  validates :account_id, uniqueness: { scope: :organization_id }

  scope :active, -> { joins(:organization).where(status: 'active', deactivated_at: nil, organizations: { deactivated_at: nil }) }
  scope :switchable, -> { active.where(organizations: { archived_at: nil }) }

  def active?
    status == 'active' && deactivated_at.nil? && organization&.active?
  end

  def customer_admin?
    role == 'customer_admin'
  end

  def customer_user?
    role == 'customer_user'
  end
end
