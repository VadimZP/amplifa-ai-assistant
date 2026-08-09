class AgentPolicy < ApplicationPolicy
  def index?
    # WHY: All authenticated users can list agents
    # Scoped to their organization via Scope class
    true
  end

  def show?
    return false if record.deleted?

    # WHY: Admins can view any agent
    # Customers can only view agents in their organization
    super || same_current_organization?(record.organization_id)
  end

  def import_leads?
    amplifa_admin?
  end

  def assign_mailboxes?
    amplifa_admin?
  end

  def review_samples?
    # WHY: Customers can review samples for their org's agents when samples are generated
    return false if record.deleted?
    return false if amplifa_admin?
    return false unless same_current_organization?(record.organization_id)

    record.samples_generated?
  end

  def approve_samples?
    # WHY: Customers can approve samples for their org's agents when samples are generated but not yet approved
    return false if record.deleted?
    return false if amplifa_admin?
    return false unless same_current_organization?(record.organization_id)

    record.samples_generated? && !record.samples_approved?
  end

  def request_changes?
    # WHY: Customers can request changes for their org's agents when samples are generated
    return false if record.deleted?
    return false if amplifa_admin?
    return false unless same_current_organization?(record.organization_id)

    record.samples_generated?
  end

  def pause_campaign?
    return false if record.deleted?
    return false if amplifa_admin?

    customer_admin? && same_current_organization?(record.organization_id)
  end

  def resume_campaign?
    return false if record.deleted?
    return false if amplifa_admin?

    customer_admin? && same_current_organization?(record.organization_id)
  end

  class Scope < Scope
    def resolve
      visible_scope = scope.not_deleted
      return visible_scope if user&.amplifa_admin?

      return visible_scope.none unless current_organization_id

      visible_scope.where(organization_id: current_organization_id)
    end
  end
end
