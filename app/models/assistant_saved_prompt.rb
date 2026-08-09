# frozen_string_literal: true

# A reusable prompt saved by one user inside one workspace. Prompts marked `welcome_pinned` appear
# on the assistant welcome screen as quick-start suggestions.
class AssistantSavedPrompt < ApplicationRecord
  TITLE_MAX_LENGTH = 80
  MAX_PROMPT_LENGTH = 8_000
  WELCOME_PINNED_LIMIT = 8

  belongs_to :account
  belongs_to :organization

  validates :title, presence: true, length: { maximum: TITLE_MAX_LENGTH }
  validates :prompt, presence: true, length: { maximum: MAX_PROMPT_LENGTH }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :welcome_pinned_limit, if: :welcome_pinned?

  scope :for_workspace, lambda { |account_id:, organization_id:|
    where(account_id: account_id, organization_id: organization_id)
  }
  scope :welcome_pinned, -> { where(welcome_pinned: true).order(:position, :id) }
  scope :recent, -> { order(updated_at: :desc, id: :desc) }

  before_validation :assign_welcome_position, if: :welcome_pinned?

  private

  def assign_welcome_position
    return if position.positive? && !welcome_pinned_changed?

    max_position = self.class.for_workspace(account_id: account_id, organization_id: organization_id)
                         .welcome_pinned
                         .where.not(id: id)
                         .maximum(:position)
    self.position = max_position.to_i + 1
  end

  def welcome_pinned_limit
    scope = self.class.for_workspace(account_id: account_id, organization_id: organization_id)
                    .welcome_pinned
                    .where.not(id: id)

    return if scope.count < WELCOME_PINNED_LIMIT

    errors.add(:welcome_pinned, :too_many)
  end
end
