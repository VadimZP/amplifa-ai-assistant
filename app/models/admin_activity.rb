class AdminActivity < ApplicationRecord
  # Associations
  belongs_to :account
  belongs_to :organization, optional: true

  # Validations
  validates :account_id, presence: true
  validates :action, presence: true, length: { minimum: 1, maximum: 100 }
  validate :details_must_be_hash

  # Scopes
  scope :for_organization, ->(org) { where(organization_id: org.id) }
  scope :by_action, ->(action_type) { where(action: action_type) }
  scope :recent, -> { order(created_at: :desc) }
  scope :impersonation_actions, -> { where(action: ['login_as_customer', 'exit_impersonation']) }

  # Methods
  def self.log_activity(account:, action:, organization: nil, details: {}, ip_address: nil, user_agent: nil)
    create!(
      account: account,
      organization: organization,
      action: action,
      details: details,
      ip_address: ip_address,
      user_agent: user_agent
    )
  end

  private

  def details_must_be_hash
    if details.nil?
      errors.add(:details, "can't be blank")
    elsif !details.is_a?(Hash)
      errors.add(:details, "must be a hash")
    end
  end
end
