class PlaybookPolicy < ApplicationPolicy
  def index?
    # WHY: All authenticated users can list playbooks
    # Scoped to their organization via Scope class
    true
  end

  def show?
    super || same_current_organization?(record.organization_id)
  end

  def update?
    # WHY: Admins can always edit
    # Customers can edit only draft or changes_requested playbooks in their org
    return true if amplifa_admin?

    same_current_organization?(record.organization_id) && record.can_edit?
  end

  def generate?
    amplifa_admin?
  end

  def create_from_generation?
    return false if amplifa_admin?

    customer_admin? && current_organization_id.present?
  end

  def approve?
    # WHY: Only customers can approve their own playbooks
    # Admins cannot approve (customers must approve)
    !amplifa_admin? &&
      same_current_organization?(record.organization_id) &&
      record.can_approve?
  end

  def request_changes?
    # WHY: Only customers can request changes
    !amplifa_admin? &&
      same_current_organization?(record.organization_id) &&
      record.can_request_changes?
  end

  def move_to_draft?
    amplifa_admin?
  end

  def archive?
    amplifa_admin? || (customer_admin? && same_current_organization?(record.organization_id))
  end

  def upload_file?
    update?
  end

  class Scope < Scope
    def resolve
      return super if user&.amplifa_admin?

      return scope.none unless current_organization_id

      scope.where(organization_id: current_organization_id)
    end
  end
end
