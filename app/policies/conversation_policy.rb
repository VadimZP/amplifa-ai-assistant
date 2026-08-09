# frozen_string_literal: true

# ConversationPolicy - Authorization for viewing and managing conversations.
# Conversations are organization-scoped (each conversation belongs to an organization).
# Amplifa admins have full access to all conversations.
# Customer admins can view their organization's conversations but have read-only access.
class ConversationPolicy < ApplicationPolicy
  # WHY: Both admins and customer admins can view the conversations list.
  # The list is scoped by organization via the Scope class.
  def index?
    amplifa_admin? || customer_account?
  end

  # WHY: Admins can view any conversation.
  # Customer admins can view conversations belonging to their organization.
  def show?
    return true if amplifa_admin?

    customer_account? && belongs_to_user_organization?
  end

  # WHY: Only Amplifa admins can close conversations.
  # This is an administrative action for managing conversation lifecycle.
  def close?
    amplifa_admin?
  end

  # WHY: Only Amplifa admins can reopen closed conversations.
  # This allows admins to resume engagement with leads.
  def reopen?
    amplifa_admin?
  end

  # WHY: Only Amplifa admins can snooze conversations.
  # Snoozing temporarily hides conversations until a specified time.
  def snooze?
    amplifa_admin?
  end

  # WHY: Only Amplifa admins can send replies.
  # This ensures quality control over outgoing communications.
  def send_reply?
    return true if amplifa_admin?

    customer_account? && belongs_to_user_organization?
  end

  # WHY: Both admins and customer admins can mark replies as read.
  # This allows customers to track which replies they've reviewed.
  def mark_read?
    return true if amplifa_admin?

    customer_account? && belongs_to_user_organization?
  end

  def update_interest_status?
    return true if amplifa_admin?

    customer_account? && belongs_to_user_organization?
  end

  private

  # WHY: Helper to check if the conversation belongs to the user's organization.
  # Conversations are directly associated with an organization.
  def belongs_to_user_organization?
    same_current_organization?(record.organization_id)
  end

  class Scope < Scope
    # WHY: Admins can see all conversations across all organizations.
    # Customer admins can only see conversations from their own organization.
    def resolve
      return scope.all if user&.amplifa_admin?

      if customer_account? && current_organization_id
        scope.where(organization_id: current_organization_id)
      else
        scope.none
      end
    end
  end
end
