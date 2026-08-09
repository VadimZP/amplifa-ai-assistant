# frozen_string_literal: true

# Stores files and URLs that provide supporting material for playbooks.
class PlaybookAttachment < ApplicationRecord
  ATTACHABLE_TYPES = %w[reference proof_point knowledge_base].freeze
  EXTRACTION_STATUSES = %w[pending processing extracting summarizing completed failed].freeze
  SOURCE_TYPES = %w[file url].freeze

  belongs_to :organization
  belongs_to :playbook, optional: true
  belongs_to :uploaded_by, class_name: 'Account', optional: true
  has_many :playbook_attachment_playbooks, dependent: :destroy
  has_many :assigned_playbooks, through: :playbook_attachment_playbooks, source: :playbook

  has_one_attached :file

  before_validation :set_organization_from_playbook
  before_validation :set_default_display_name

  validates :organization, presence: true
  validates :attachable_type, presence: true, inclusion: { in: ATTACHABLE_TYPES }
  validates :attachable_id, presence: true
  validates :attachable_id, uniqueness: { scope: %i[playbook_id attachable_type] }, unless: :knowledge_base?
  validates :attachable_id, uniqueness: { scope: %i[organization_id attachable_type] }, if: :knowledge_base?
  validates :playbook, presence: true, unless: :knowledge_base?
  validates :original_filename, presence: true, if: :file_source?
  validates :display_name, presence: true, if: :knowledge_base?
  validates :source_type, presence: true, inclusion: { in: SOURCE_TYPES }, if: :knowledge_base?
  validates :source_url, presence: true, if: :url_source?
  validates :extraction_status, presence: true, inclusion: { in: EXTRACTION_STATUSES }
  validate :file_must_be_attached, if: :file_source?
  validate :knowledge_base_assignment_present, if: :knowledge_base?

  scope :for_playbook, ->(playbook) { where(playbook_id: playbook.id) }
  scope :for_references, -> { where(attachable_type: 'reference') }
  scope :for_proof_points, -> { where(attachable_type: 'proof_point') }
  scope :knowledge_base, -> { where(attachable_type: 'knowledge_base') }
  scope :uploaded_by_amplifa_admin, -> { joins(:uploaded_by).merge(Account.amplifa_admins) }
  scope :for_playbook_or_all, lambda { |playbook|
    left_joins(:playbook_attachment_playbooks)
      .where(applies_to_all_playbooks: true, organization_id: playbook.organization_id)
      .or(left_joins(:playbook_attachment_playbooks).where(playbook_attachment_playbooks: { playbook_id: playbook.id }))
      .distinct
  }
  scope :with_extraction_status, ->(status) { where(extraction_status: status) }

  def knowledge_base?
    attachable_type == 'knowledge_base'
  end

  def file_source?
    source_type.blank? || source_type == 'file'
  end

  def url_source?
    source_type == 'url'
  end

  def assigned_to_all_playbooks?
    applies_to_all_playbooks?
  end

  private

  def set_organization_from_playbook
    self.organization ||= playbook&.organization
  end

  def set_default_display_name
    self.display_name = original_filename.presence || source_title.presence || source_url if display_name.blank?
  end

  def file_must_be_attached
    errors.add(:file, 'must be attached') unless file.attached?
  end

  def knowledge_base_assignment_present
    return if applies_to_all_playbooks?
    return if assigned_playbooks.any? || playbook_attachment_playbooks.any?

    errors.add(:base, 'Select at least one playbook')
  end
end
