class EmailTwoFactorChallenge < ApplicationRecord
  RESEND_INTERVAL = 60.seconds
  EXPIRES_IN = 30.minutes

  belongs_to :account

  validates :token_digest, presence: true, uniqueness: true
  validates :expires_at, :last_sent_at, presence: true

  scope :active, -> { where(used_at: nil).where('expires_at > ?', Time.current) }
  scope :newest_first, -> { order(created_at: :desc) }

  def self.create_for!(account:, return_to:, remember_login:)
    raw_token = SecureRandom.urlsafe_base64(32)
    challenge = create!(
      account: account,
      token_digest: digest(raw_token),
      expires_at: EXPIRES_IN.from_now,
      last_sent_at: Time.current,
      return_to: safe_return_to(return_to),
      remember_login: remember_login
    )

    [challenge, raw_token]
  end

  def self.find_active_by_token(raw_token)
    active.find_by(token_digest: digest(raw_token.to_s))
  end

  def self.digest(raw_token)
    OpenSSL::HMAC.hexdigest('SHA256', Rails.application.secret_key_base, raw_token.to_s)
  end

  def self.safe_return_to(path)
    value = path.to_s
    return if value.blank?

    value if value.start_with?('/') && !value.start_with?('//')
  end

  def resend_available_at
    last_sent_at + RESEND_INTERVAL
  end

  def resend_available?
    Time.current >= resend_available_at
  end

  def use_once!
    self.class.where(id: id, used_at: nil).where('expires_at > ?', Time.current).update_all(
      used_at: Time.current,
      updated_at: Time.current
    ) == 1
  end

  def mark_sent!
    update!(last_sent_at: Time.current)
  end

  def use!
    update!(used_at: Time.current)
  end
end
