class PlaybookCommentPolicy < ApplicationPolicy
  def index?
    super || same_current_organization?(record.playbook.organization_id)
  end

  def show?
    super || same_current_organization?(record.playbook.organization_id)
  end

  def create?
    super || same_current_organization?(record.playbook.organization_id)
  end

  def update?
    # WHY: Only comment author can edit their own comments (not even admins)
    record.account_id == user.id
  end

  def destroy?
    super || record.account_id == user.id
  end

  class Scope < Scope
    def resolve
      return super if user&.amplifa_admin?
      return scope.none unless current_organization_id

      scope.joins(:playbook).where(playbooks: { organization_id: current_organization_id })
    end
  end
end
