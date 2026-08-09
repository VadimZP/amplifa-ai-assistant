class BlacklistPolicy < ApplicationPolicy
  def index?
    # WHY: All authenticated users can view blacklist entries
    # Scoped to their org's entries + global entries via Scope class
    true
  end

  def show?
    # WHY: Admins can view any entry
    # Customers can view their org's entries or global entries
    return true if amplifa_admin?

    record.organization_id.nil? || same_current_organization?(record.organization_id)
  end

  def create?
    # WHY: Admins can create any entry
    # Customer admins can create entries for their org only
    super || customer_admin?
  end

  def create_global?
    amplifa_admin?
  end

  def update?
    # WHY: Admins can update any entry
    # Customer admins can update their org's entries (not global)
    return true if amplifa_admin?

    customer_admin? && same_current_organization?(record.organization_id)
  end

  def destroy?
    # WHY: Admins can delete any entry
    # Customer admins can delete their org's entries (not global)
    return true if amplifa_admin?

    customer_admin? && same_current_organization?(record.organization_id)
  end

  class Scope < Scope
    def resolve
      return super if user&.amplifa_admin?
      # WHY: Customers see their org's entries + global entries
      # Global entries (organization_id = nil) affect all orgs
      scope.where(organization_id: [current_organization_id, nil])
    end
  end
end
