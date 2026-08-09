class Invitation < ApplicationRecord
  # Associations
  belongs_to :organization
  belongs_to :account, optional: true
  belongs_to :invited_by, class_name: 'Account'

  # Validations
  validates :email, presence: true,
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :email, uniqueness: {
    scope: :organization_id,
    conditions: -> { where(status: ['pending', 'accepted']) },
    message: 'already has a pending or accepted invitation'
  }
  validates :first_name, presence: true, length: { minimum: 1, maximum: 100 }
  validates :last_name, presence: true, length: { minimum: 1, maximum: 100 }
  validates :role, presence: true, inclusion: { in: %w[customer_admin customer_user] }
  validates :token, presence: true, uniqueness: true
  validates :status, inclusion: { in: %w[pending accepted expired cancelled] }
  validate :expires_at_in_future, if: -> { pending? && new_record? }

  # Scopes
  scope :pending, -> { where(status: 'pending').where('expires_at > ?', Time.current) }
  scope :expired, -> { where(status: 'pending').where('expires_at <= ?', Time.current) }
  scope :for_organization, ->(org) { where(organization_id: org.id) }
  scope :recent, -> { order(created_at: :desc) }

  # Callbacks
  before_validation :generate_token, on: :create
  before_validation :set_expires_at, on: :create

  # Methods
  def expired?
    status == 'pending' && expires_at <= Time.current
  end

  def can_be_accepted?
    status == 'pending' && !expired?
  end

  def pending?
    status == 'pending'
  end

  def accept!(password, account_params = {})
    # Implementation in controller - this is a helper method
    return false unless can_be_accepted?
    true
  end

  def cancel!
    return false unless status == 'pending'
    update!(status: 'cancelled')
  end

  def resend!
    return false unless status == 'pending'
    transaction do
      update!(
        token: SecureRandom.urlsafe_base64(32),
        expires_at: 7.days.from_now,
        sent_at: Time.current
      )
      InvitationMailer.invite(self).deliver_later
    end
  end

  private

  def generate_token
    self.token ||= SecureRandom.urlsafe_base64(32)
  end

  def set_expires_at
    self.expires_at ||= 7.days.from_now
  end

  def expires_at_in_future
    if expires_at && expires_at <= Time.current
      errors.add(:expires_at, 'must be in the future')
    end
  end
end
