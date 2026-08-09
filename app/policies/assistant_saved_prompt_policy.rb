# frozen_string_literal: true

# Saved assistant prompts are private to the account that created them, scoped to one workspace.
class AssistantSavedPromptPolicy < ApplicationPolicy
  def index?
    customer_account?
  end

  def show?
    customer_account? && owned_by_user? && belongs_to_user_organization?
  end

  def create?
    customer_account?
  end

  def update?
    show?
  end

  def destroy?
    show?
  end

  class Scope < Scope
    def resolve
      return scope.none unless customer_account? && current_organization_id && user

      scope.where(account_id: user.id, organization_id: current_organization_id)
    end
  end

  private

  def owned_by_user?
    record.account_id == user&.id
  end

  def belongs_to_user_organization?
    same_current_organization?(record.organization_id)
  end
end
