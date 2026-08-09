class SentReplyAttachment < ApplicationRecord
  MAX_FILE_SIZE_BYTES = 10.megabytes

  belongs_to :sent_reply

  has_one_attached :file

  validates :original_filename, presence: true
  validates :content_type, presence: true
  validates :file_size_bytes,
            presence: true,
            numericality: { greater_than: 0, less_than_or_equal_to: MAX_FILE_SIZE_BYTES }
  validate :file_must_be_attached

  private

  def file_must_be_attached
    errors.add(:file, 'must be attached') unless file.attached?
  end
end
