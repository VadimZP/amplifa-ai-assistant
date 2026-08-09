# frozen_string_literal: true

class AgentLeadRun < ApplicationRecord
  STATUSES = %w[active completed restarted cancelled].freeze

  belongs_to :agent_lead
  belongs_to :assigned_mailbox, class_name: 'Mailbox', optional: true
  belongs_to :restarted_by, class_name: 'Account', optional: true
  has_many :generated_messages, dependent: :restrict_with_error

  before_destroy :ensure_not_current_run

  validates :run_number, presence: true, numericality: { only_integer: true, greater_than: 0 },
                         uniqueness: { scope: :agent_lead_id }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :started_at, presence: true

  validate :assigned_mailbox_same_organization

  scope :active, -> { where(status: 'active') }

  def active?
    status == 'active'
  end

  private

  def assigned_mailbox_same_organization
    return unless assigned_mailbox.present? && agent_lead.present?
    return if assigned_mailbox.organization_id == agent_lead.agent.organization_id

    errors.add(:assigned_mailbox, 'must belong to the same organization')
  end

  def ensure_not_current_run
    return unless agent_lead&.current_agent_lead_run_id == id

    errors.add(:base, 'Cannot delete the current agent lead run')
    throw(:abort)
  end
end
