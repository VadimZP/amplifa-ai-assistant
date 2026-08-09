class LeadImportPolicy < ApplicationPolicy
  def index?
    # WHY: Admins can see all imports; customers can view their org's import history (read-only)
    super || current_organization_id.present?
  end

  def show?
    # WHY: Admins can see all imports; customers can view their own org's imports
    super || same_current_organization?(record.organization_id)
  end

  class Scope < Scope
    def resolve
      return super if user&.amplifa_admin?
      return scope.none unless current_organization_id

      scope.where(organization_id: current_organization_id)
    end
  end
end
