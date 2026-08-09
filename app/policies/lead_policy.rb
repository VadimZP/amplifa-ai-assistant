class LeadPolicy < ApplicationPolicy
  # WHY: Amplifa admins can see all leads for platform oversight.
  # Customer admins and users can see leads belonging to their organization.
  def index?
    super || customer_account?
  end

  # WHY: Same access rules as index - if you can list leads, you can view individual ones.
  def show?
    super || belongs_to_user_organization?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return super if user&.amplifa_admin?
      return scope.none unless current_organization_id

      scope.where(organization_id: current_organization_id)
    end
  end

  private

  def belongs_to_user_organization?
    same_current_organization?(record.organization_id)
  end
end
