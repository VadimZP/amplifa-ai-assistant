# frozen_string_literal: true

# ChatPolicy - Authorization for the customer-facing AI assistant.
#
# WHY this is the one policy that denies amplifa admins: the assistant acts on behalf of a customer
# inside a specific workspace, and Amplifa admins have no workspace of their own. Granting them
# access would mean a chat with no `Current.organization` to scope tools against. Admins who need to
# see the assistant impersonate a customer instead, at which point they authorize as that customer.
class ChatPolicy < ApplicationPolicy
  # WHY: Any member of the current workspace can use the assistant. The Scope narrows the list to
  # the caller's own chats.
  def index?
    customer_account?
  end

  # WHY: A chat is private to the account that created it. Even a customer admin cannot read a
  # colleague's chat, because a chat can contain anything the author typed.
  def show?
    customer_account? && owned_by_user? && belongs_to_user_organization?
  end

  def create?
    customer_account?
  end

  def destroy?
    show?
  end

  def pin?
    show?
  end

  # WHY: Posting a prompt mutates the chat, so it requires the same ownership check as reading it.
  def create_message?
    show?
  end

  private

  def owned_by_user?
    record.account_id == user&.id
  end

  def belongs_to_user_organization?
    same_current_organization?(record.organization_id)
  end

  class Scope < Scope
    # WHY: Deliberately does NOT call super. Amplifa admins get no chats (see the class comment),
    # and customers only ever see their own chats within the active workspace — never a colleague's,
    # never another organization's.
    def resolve
      return scope.none unless customer_account? && current_organization_id && user

      scope.where(account_id: user.id, organization_id: current_organization_id)
    end
  end
end
