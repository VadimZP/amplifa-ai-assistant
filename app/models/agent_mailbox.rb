# frozen_string_literal: true

# Join table linking agents to the mailboxes they can use for sending.
class AgentMailbox < ApplicationRecord
  # Associations
  belongs_to :agent
  belongs_to :mailbox

  # Validations
  validates :agent_id, uniqueness: { scope: :mailbox_id, message: "already has this mailbox assigned" }
  validate :same_organization

  private

  def same_organization
    return unless agent.present? && mailbox.present?

    if agent.organization_id != mailbox.organization_id
      errors.add(:base, "Agent and Mailbox must belong to the same organization")
    end
  end
end
