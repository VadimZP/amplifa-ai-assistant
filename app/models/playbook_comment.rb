class PlaybookComment < ApplicationRecord
  BODY_MAX_LENGTH = 8000
  FEEDBACK_TABS = %w[training_data samples import_leads].freeze

  # Associations
  belongs_to :playbook
  belongs_to :account

  # Validations
  validates :playbook, presence: true
  validates :account, presence: true
  validates :body, presence: true, length: { minimum: 1, maximum: BODY_MAX_LENGTH }
  validates :comment_type, inclusion: { in: %w[general request_changes approval] }
  validate :feedback_context_has_valid_tab

  # Scopes
  scope :for_playbook, ->(playbook) { where(playbook_id: playbook.id) }
  scope :chronological, -> { order(created_at: :asc) }
  scope :recent, -> { order(created_at: :desc) }
  scope :by_type, ->(type) { where(comment_type: type) }
  scope :general, -> { where(comment_type: 'general') }
  scope :status_related, -> { where(comment_type: %w[request_changes approval]) }

  # Methods
  def author_name
    account.full_name
  end

  def general?
    comment_type == 'general'
  end

  def request_changes?
    comment_type == 'request_changes'
  end

  def approval?
    comment_type == 'approval'
  end

  private

  def feedback_context_has_valid_tab
    return if feedback_context.blank?

    unless feedback_context.is_a?(Hash)
      errors.add(:feedback_context, 'must be a hash')
      return
    end

    tab = feedback_context.with_indifferent_access[:tab]
    return if FEEDBACK_TABS.include?(tab)

    errors.add(:feedback_context, 'must include a valid tab')
  end
end
