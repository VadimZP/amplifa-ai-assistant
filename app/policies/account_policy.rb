class AccountPolicy < ApplicationPolicy
  def index?
    super || customer_admin?
  end

  def show?
    super || same_organization?
  end

  def update?
    super || (customer_admin? && same_organization?) || own_profile?
  end

  def destroy?
    return false if record.deactivated_at.present?
    return false if record.id == user.id
    return false if record.protected_from_admin_deletion?

    super || (customer_admin? && same_organization?)
  end

  def impersonate?
    amplifa_admin?
  end

  class Scope < Scope
    def resolve
      return super if user&.amplifa_admin?

      return scope.none unless current_organization_id

      scope.joins(:organization_memberships)
           .where(organization_memberships: {
                    organization_id: current_organization_id,
                    status: 'active',
                    deactivated_at: nil
                  })
    end
  end

  private

  def same_organization?
    record.organization_memberships.active.exists?(organization_id: current_organization_id)
  end

  def own_profile?
    record.id == user.id
  end
end
