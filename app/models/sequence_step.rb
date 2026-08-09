# frozen_string_literal: true

# Represents a single step in an agent's outreach sequence.
# Supports multiple event types (email, linkedin, etc.) for future extensibility.
class SequenceStep < ApplicationRecord
  # Constants
  EVENT_TYPES = %w[email linkedin_message linkedin_visit linkedin_connect manual_task].freeze
  MAX_STEPS_PER_AGENT = 15
  MAX_DELAY_DAYS = 30

  # Associations
  belongs_to :agent, optional: true
  belongs_to :global_sequence, optional: true
  has_many :generated_messages, dependent: :destroy

  # Validations
  validates :position, presence: true
  validates :position,
            numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: MAX_STEPS_PER_AGENT },
            unless: :archived?
  validates :position,
            numericality: { only_integer: true, greater_than: 0 },
            if: :archived?
  validates :event_type, presence: true, inclusion: { in: EVENT_TYPES }
  validates :delay_days, presence: true,
                         numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: MAX_DELAY_DAYS }
  validates :name, length: { maximum: 100 }, allow_nil: true

  validate :single_owner_present
  validate :position_unique_within_owner
  validate :sequence_not_too_long

  # Scopes
  scope :active, -> { where(active: true) }
  scope :not_archived, -> { where(archived: false) }
  scope :copyable, -> { not_archived }
  scope :email_steps, -> { where(event_type: 'email') }
  scope :ordered, -> { order(:position) }
  scope :for_agent, ->(agent) { where(agent_id: agent.id) }
  scope :for_global_sequence, ->(global_sequence) { where(global_sequence_id: global_sequence.id) }

  # Event type predicates
  def email?
    event_type == 'email'
  end

  def linkedin_message?
    event_type == 'linkedin_message'
  end

  def linkedin_visit?
    event_type == 'linkedin_visit'
  end

  def linkedin_connect?
    event_type == 'linkedin_connect'
  end

  def manual_task?
    event_type == 'manual_task'
  end

  # Display name for UI (uses custom name or generates one)
  def display_name
    name.presence || "Step #{position}: #{event_type.humanize}"
  end

  # Returns the previous step in the sequence
  def previous_step
    sibling_steps.where('position < ?', position).order(position: :desc).first
  end

  # Returns the next step in the sequence
  def next_step
    sibling_steps.active.where('position > ?', position).order(position: :asc).first
  end

  # Returns the total delay from start of sequence to this step
  def cumulative_delay_days
    sibling_steps.where('position <= ?', position).sum(:delay_days)
  end

  def available_to_agent?(current_agent)
    return false if current_agent.blank?
    return agent_id == current_agent.id if agent_id.present?

    global_sequence_id.present? && current_agent.global_sequence_id == global_sequence_id
  end

  def sibling_steps
    owner_steps = global_sequence_id.present? ? global_sequence.sequence_steps : agent.sequence_steps
    owner_steps.not_archived
  end

  private

  def single_owner_present
    return if [agent_id.present?, global_sequence_id.present?].count(true) == 1

    errors.add(:base, 'Sequence step must belong to exactly one owner')
  end

  def position_unique_within_owner
    return if position.blank?

    scope = if global_sequence_id.present?
              self.class.where(global_sequence_id: global_sequence_id)
            elsif agent_id.present?
              self.class.where(agent_id: agent_id, global_sequence_id: nil)
            end

    return if scope.blank?
    return unless scope.where(position: position).where.not(id: id).exists?

    errors.add(:position, 'is already taken for this sequence')
  end

  def sequence_not_too_long
    return unless new_record?
    return if archived?

    steps = if global_sequence_id.present?
              global_sequence.sequence_steps.not_archived
            elsif agent.present?
              agent.sequence_steps.not_archived
            else
              return
            end

    return unless new_record?

    return unless steps.count >= MAX_STEPS_PER_AGENT

    errors.add(:base, "Sequence cannot have more than #{MAX_STEPS_PER_AGENT} steps")
  end
end
