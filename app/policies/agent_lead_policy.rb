class AgentLeadPolicy < ApplicationPolicy
  def index?
    # WHY: All authenticated users can list agent_leads
    # Scoped to their organization via Scope class
    true
  end

  def show?
    super || belongs_to_user_organization?
  end

  # WHY: Only admins can mark meetings (for now).
  # This tracks manual meeting booking for dogfooding purposes.
  def mark_meeting?
    user&.amplifa_admin?
  end

  def unmark_meeting?
    user&.amplifa_admin?
  end

  def generate_messages?
    user&.amplifa_admin?
  end

  class Scope < Scope
    def resolve
      return super if user&.amplifa_admin?
      # WHY: Customers can only see agent_leads belonging to their org's agents
      return scope.none unless current_organization_id

      scope.joins(:agent).where(agents: { organization_id: current_organization_id }).merge(Agent.not_deleted)
    end
  end

  private

  def belongs_to_user_organization?
    record.agent.present? && !record.agent.deleted? && same_current_organization?(record.agent.organization_id)
  end
end
