# frozen_string_literal: true

class McpOauthRefreshToken < ApplicationRecord
  belongs_to :account

  validates :jti, :client_id, :scope, :aud, :expires_at, presence: true
  validates :jti, uniqueness: true

  def consumed?
    consumed_at.present?
  end

  def expired?
    expires_at <= Time.current
  end
end
