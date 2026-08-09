class OrganizationFilePolicy < ApplicationPolicy
  def index?
    super || current_organization_id.present?
  end

  def show?
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
