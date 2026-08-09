# frozen_string_literal: true

# Stores organization-uploaded source files that are not processed imports.
class OrganizationFile < ApplicationRecord
  CATEGORIES = %w[lead_list].freeze
  EXTRACTION_STATUSES = %w[pending extracting summarizing completed failed].freeze
  SOURCE_TYPES = %w[file url].freeze

  belongs_to :organization
  belongs_to :uploaded_by, class_name: 'Account'
  has_many :organization_file_playbooks, dependent: :destroy
  has_many :playbooks, through: :organization_file_playbooks

  has_one_attached :file

  before_validation :set_default_display_name

  validates :original_filename, presence: true, if: :file_source?
  validates :display_name, presence: true
  validates :uploaded_by, presence: true
  validates :category, presence: true, inclusion: { in: CATEGORIES }
  validates :extraction_status, presence: true, inclusion: { in: EXTRACTION_STATUSES }
  validates :source_type, presence: true, inclusion: { in: SOURCE_TYPES }
  validates :source_url, presence: true, if: :url_source?
  validate :file_must_be_attached, if: :file_source?

  scope :lead_lists, -> { where(category: 'lead_list') }
  scope :for_playbook_or_all, lambda { |playbook|
    left_joins(:organization_file_playbooks)
      .where(applies_to_all_playbooks: true)
      .or(left_joins(:organization_file_playbooks).where(organization_file_playbooks: { playbook_id: playbook.id }))
      .distinct
  }
  scope :uploaded_by_amplifa_admin, -> { joins(:uploaded_by).merge(Account.amplifa_admins) }

  def lead_list?
    category == 'lead_list'
  end

  def assigned_to_all_playbooks?
    applies_to_all_playbooks?
  end

  def primary_playbook
    playbooks.order(:id).first
  end

  def file_source?
    source_type == 'file'
  end

  def url_source?
    source_type == 'url'
  end

  private

  def set_default_display_name
    self.display_name = original_filename.presence || source_title.presence || source_url if display_name.blank?
  end

  def file_must_be_attached
    errors.add(:file, 'must be attached') unless file.attached?
  end
end
