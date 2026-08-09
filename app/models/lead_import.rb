# frozen_string_literal: true

class LeadImport < ApplicationRecord
  # Constants
  STATUSES = %w[pending processing completed failed].freeze
  SOURCES = %w[csv hubspot pipedrive].freeze
  MAX_ERRORS = 100

  # Associations
  belongs_to :organization
  belongs_to :agent, optional: true
  belongs_to :imported_by, class_name: "Account"
  has_many :leads, dependent: :nullify
  has_one_attached :csv_file

  # Validations
  validates :organization, presence: true
  validates :imported_by, presence: true
  validates :original_filename, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :source, presence: true, inclusion: { in: SOURCES }
  validates :column_mapping, presence: true
  validate :column_mapping_has_email, if: -> { column_mapping.present? }

  # Scopes
  scope :for_organization, ->(org) { where(organization_id: org.id) }
  scope :pending, -> { where(status: "pending") }
  scope :processing, -> { where(status: "processing") }
  scope :completed, -> { where(status: "completed") }
  scope :failed, -> { where(status: "failed") }
  scope :recent, -> { order(created_at: :desc) }

  # Status predicate methods
  def pending?
    status == "pending"
  end

  def processing?
    status == "processing"
  end

  def completed?
    status == "completed"
  end

  def failed?
    status == "failed"
  end

  # Calculates progress as a percentage (0-100)
  def progress_percentage
    return 0 if total_rows.zero?

    (processed_rows.to_f / total_rows * 100).round
  end

  # Returns the duration of the import in seconds
  def duration_seconds
    return nil unless started_at && completed_at

    (completed_at - started_at).to_i
  end

  # Adds an error to the errors_detail array (capped at MAX_ERRORS)
  # Uses string keys for JSONB consistency
  def add_error(row:, message:)
    return if errors_detail.length >= MAX_ERRORS

    self.errors_detail = errors_detail + [{ "row" => row, "error" => message }]
  end

  private

  def column_mapping_has_email
    unless column_mapping.values.include?("email")
      errors.add(:column_mapping, "must map a column to email")
    end
  end
end
