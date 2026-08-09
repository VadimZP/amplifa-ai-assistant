class MeetingDeclinedComment < ApplicationRecord
  BODY_MAX_LENGTH = 8000

  belongs_to :meeting
  belongs_to :account

  validates :meeting, presence: true
  validates :account, presence: true
  validates :body, presence: true, length: { minimum: 1, maximum: BODY_MAX_LENGTH }

  scope :chronological, -> { order(created_at: :asc) }

  def author_name
    account.full_name
  end
end
