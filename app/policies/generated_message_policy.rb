# frozen_string_literal: true

class GeneratedMessagePolicy < ApplicationPolicy
  def show?
    super || belongs_to_user_org?
  end

  def send_test?
    amplifa_admin? || belongs_to_user_org?
  end

  def customer_send_test?
    # WHY: Customers can send test emails to their own address for their org's messages
    return false if amplifa_admin?
    return false if record.agent.deleted?

    belongs_to_user_org?
  end

  class Scope < Scope
    def resolve
      return super if user&.amplifa_admin?
      return scope.none unless current_organization_id

      scope
        .joins(agent_lead: :agent)
        .where(agents: { organization_id: current_organization_id })
        .merge(Agent.not_deleted)
    end
  end

  private

  def belongs_to_user_org?
    record.agent.present? && !record.agent.deleted? && same_current_organization?(record.agent.organization_id)
  end
end
