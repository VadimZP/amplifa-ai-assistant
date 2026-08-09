class ReplyAttachment < ApplicationRecord
  belongs_to :reply

  has_one_attached :file

  validates :original_filename, presence: true
  validates :content_type, presence: true
  validates :file_size_bytes, presence: true
  validates :content_id, length: { maximum: 255 }, allow_blank: true
  validate :file_must_be_attached

  private

  def file_must_be_attached
    errors.add(:file, 'must be attached') unless file.attached?
  end
end
