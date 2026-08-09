# frozen_string_literal: true

# Sales playbook used as the approved campaign context for agents.
class Playbook < ApplicationRecord
  STATUSES = %w[draft changes_requested approved archived].freeze

  before_destroy :pause_active_agents, prepend: true

  # Associations
  belongs_to :organization
  belongs_to :approved_by, class_name: 'Account', optional: true
  has_many :playbook_comments, dependent: :destroy
  has_many :playbook_attachments, dependent: :destroy
  has_many :playbook_attachment_playbooks, dependent: :destroy
  has_many :assigned_playbook_attachments, through: :playbook_attachment_playbooks, source: :playbook_attachment
  has_many :agents, dependent: :nullify
  has_many :organization_file_playbooks, dependent: :destroy
  has_many :organization_files, through: :organization_file_playbooks
  has_paper_trail on: [:update], skip: %i[version_cursor_id redo_version_snapshots]

  VERSIONED_ATTRIBUTES = %w[
    product value_proposition personae use_cases references proof_points ai_generation_notes status language approved_at
    approved_by_id
  ].freeze

  attr_accessor :preserve_version_navigation

  before_update :clear_version_navigation, if: :clear_version_navigation?

  # Validations
  validates :organization, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :language, inclusion: { in: SupportedLocale::ALL }
  validates :personae, presence: true
  validates :use_cases, presence: true
  validates :product, presence: true

  # Custom validations for JSONB structure
  validate :product_structure_valid
  validate :personae_structure_valid
  validate :use_cases_structure_valid
  validate :references_structure_valid
  validate :proof_points_structure_valid
  validate :approved_metadata_present, if: :approved?

  # Scopes
  scope :for_organization, ->(org) { where(organization_id: org.id) }
  scope :for_product_name, ->(product_name) { where("product->>'name' = ?", product_name) }
  scope :by_status, ->(status) { where(status: status) }
  scope :draft, -> { where(status: 'draft') }
  scope :changes_requested, -> { where(status: 'changes_requested') }
  scope :approved, -> { where(status: 'approved') }
  scope :archived, -> { where(status: 'archived') }
  scope :pending_review, -> { where(status: %w[draft changes_requested]) }
  scope :recent, -> { order(created_at: :desc) }

  # State check methods
  def draft?
    status == 'draft'
  end

  def changes_requested?
    status == 'changes_requested'
  end

  def approved?
    status == 'approved'
  end

  def archived?
    status == 'archived'
  end

  # Permission check methods
  def can_edit?
    draft? || changes_requested?
  end

  def can_approve?
    draft? || changes_requested?
  end

  def can_request_changes?
    draft? || changes_requested? || approved?
  end

  def can_archive?
    true # Can archive from any state
  end

  def knowledge_base_available?
    organization.playbook_attachments
                .knowledge_base
                .for_playbook_or_all(self)
                .uploaded_by_amplifa_admin
                .exists?
  end

  def contextual_playbook_attachments
    attachments = playbook_attachments
    where_chain = attachments.where if attachments.respond_to?(:where)
    return attachments unless where_chain.respond_to?(:not)

    direct_attachments = where_chain.not(attachable_type: 'knowledge_base')
    knowledge_base_attachments = organization.playbook_attachments.knowledge_base.for_playbook_or_all(self)

    PlaybookAttachment.where(id: direct_attachments.select(:id))
                      .or(PlaybookAttachment.where(id: knowledge_base_attachments.select(:id)))
  end

  def completed_contextual_playbook_attachments
    attachments = contextual_playbook_attachments
    return attachments.where(extraction_status: 'completed') if attachments.respond_to?(:where)

    Array(attachments).select { |attachment| attachment.extraction_status == 'completed' }
  end

  # Transition methods
  def request_changes!
    update!(status: 'changes_requested', approved_at: nil, approved_by_id: nil)
  end

  def approve!(approved_by_account)
    update!(
      status: 'approved',
      approved_at: Time.current,
      approved_by_id: approved_by_account.id
    )
  end

  def archive!
    update!(status: 'archived')
  end

  def move_to_draft!
    update!(status: 'draft', approved_at: nil, approved_by_id: nil)
  end

  # Content helper methods
  def persona_count
    personae.length
  end

  def use_case_count
    use_cases.length
  end

  def reference_count
    references.length
  end

  def proof_point_count
    proof_points.length
  end

  def has_file_attachments?
    references.any? { |r| r['file_url'].present? } ||
      proof_points.any? { |p| p['file_url'].present? }
  end

  def file_attachment_count
    references.count { |r| r['file_url'].present? } +
      proof_points.count { |p| p['file_url'].present? }
  end

  def ai_generated?
    ai_generation_notes.present?
  end

  # Product helper methods
  def product_name
    product['name']
  end

  def product_description
    product['description']
  end

  def product_metadata
    product['metadata'] || {}
  end

  private

  def clear_version_navigation?
    !preserve_version_navigation && (changed & VERSIONED_ATTRIBUTES).any?
  end

  def clear_version_navigation
    self.version_cursor_id = nil
    self.redo_version_snapshots = []
  end

  def pause_active_agents
    agents.active.find_each(&:pause!)
  end

  # JSONB Structure Validations

  def product_structure_valid
    return if product.blank?

    unless product.is_a?(Hash)
      errors.add(:product, 'must be an object')
      return
    end

    errors.add(:product, "missing 'name'") unless product['name'].present?

    if product['description'].present? && !product['description'].is_a?(String)
      errors.add(:product, "'description' must be a string")
    end

    return unless product['metadata'].present? && !product['metadata'].is_a?(Hash)

    errors.add(:product, "'metadata' must be an object")
  end

  def personae_structure_valid
    return if personae.blank?

    personae.each_with_index do |persona, index|
      unless persona.is_a?(Hash)
        errors.add(:personae, "Item #{index} must be an object")
        next
      end

      errors.add(:personae, "Item #{index} missing 'id'") unless persona['id'].present?
      errors.add(:personae, "Item #{index} missing 'name'") unless persona['name'].present?
      errors.add(:personae, "Item #{index} missing 'title'") unless persona['title'].present?
      errors.add(:personae, "Item #{index} missing 'order'") unless persona['order'].present?

      next unless persona['pain_points'].present?

      errors.add(:personae, "Item #{index} pain_points must be an array") unless persona['pain_points'].is_a?(Array)
    end
  end

  def use_cases_structure_valid
    return if use_cases.blank?

    use_cases.each_with_index do |use_case, index|
      unless use_case.is_a?(Hash)
        errors.add(:use_cases, "Item #{index} must be an object")
        next
      end

      errors.add(:use_cases, "Item #{index} missing 'id'") unless use_case['id'].present?
      errors.add(:use_cases, "Item #{index} missing 'title'") unless use_case['title'].present?
      errors.add(:use_cases, "Item #{index} missing 'description'") unless use_case['description'].present?
      errors.add(:use_cases, "Item #{index} missing 'order'") unless use_case['order'].present?
    end
  end

  def references_structure_valid
    return if references.blank?

    references.each_with_index do |reference, index|
      unless reference.is_a?(Hash)
        errors.add(:references, "Item #{index} must be an object")
        next
      end

      errors.add(:references, "Item #{index} missing 'id'") unless reference['id'].present?
      errors.add(:references, "Item #{index} missing 'customer_name'") unless reference['customer_name'].present?
      errors.add(:references, "Item #{index} missing 'description'") unless reference['description'].present?
      errors.add(:references, "Item #{index} missing 'order'") unless reference['order'].present?

      # If file_url present, file_name and file_size should also be present
      next unless reference['file_url'].present?

      unless reference['file_name'].present?
        errors.add(:references,
                   "Item #{index} with file_url must have file_name")
      end
      unless reference['file_size'].present?
        errors.add(:references,
                   "Item #{index} with file_url must have file_size")
      end
    end
  end

  def proof_points_structure_valid
    return if proof_points.blank?

    proof_points.each_with_index do |proof_point, index|
      unless proof_point.is_a?(Hash)
        errors.add(:proof_points, "Item #{index} must be an object")
        next
      end

      errors.add(:proof_points, "Item #{index} missing 'id'") unless proof_point['id'].present?
      errors.add(:proof_points, "Item #{index} missing 'claim'") unless proof_point['claim'].present?
      errors.add(:proof_points, "Item #{index} missing 'description'") unless proof_point['description'].present?
      errors.add(:proof_points, "Item #{index} missing 'order'") unless proof_point['order'].present?

      # If file_url present, file_name and file_size should also be present
      next unless proof_point['file_url'].present?

      unless proof_point['file_name'].present?
        errors.add(:proof_points,
                   "Item #{index} with file_url must have file_name")
      end
      unless proof_point['file_size'].present?
        errors.add(:proof_points,
                   "Item #{index} with file_url must have file_size")
      end
    end
  end

  def approved_metadata_present
    return unless status == 'approved' && (approved_at.nil? || approved_by_id.nil?)

    errors.add(:base, 'Approved playbooks must have approved_at and approved_by_id')
  end
end
