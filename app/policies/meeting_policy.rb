# frozen_string_literal: true

# Authorization policy for Meeting records.
# Controls who can view, create, and manage meetings with leads.
class MeetingPolicy < ApplicationPolicy
  # WHY: All authenticated users can list meetings, scoped to their organization
  def index?
    true
  end

  # WHY: Admins can see all meetings, customers can see their organization's meetings
  def show?
    super || belongs_to_user_organization?
  end

  # WHY: Customers can manually create meetings for their own organization from the meetings page.
  def create?
    amplifa_admin? || customer_account?
  end

  # WHY: Only admins can update meetings
  def update?
    amplifa_admin?
  end

  # WHY: Only admins can delete meetings
  def destroy?
    amplifa_admin?
  end

  def mark_completed?
    amplifa_admin? || belongs_to_user_organization?
  end

  def mark_no_show?
    amplifa_admin? || belongs_to_user_organization?
  end

  # WHY: Only admins can cancel meetings
  def cancel?
    amplifa_admin?
  end

  def reschedule?
    amplifa_admin? || belongs_to_user_organization?
  end

  def update_notes?
    amplifa_admin? || belongs_to_user_organization?
  end

  def assign?
    amplifa_admin? || belongs_to_user_organization?
  end

  def decline_removal?
    amplifa_admin?
  end

  # WHY: Customers can set outcome on their organization's meetings (AMP-136)
  def set_outcome?
    amplifa_admin? || belongs_to_user_organization?
  end

  def request_removal?
    amplifa_admin? || belongs_to_user_organization?
  end

  class Scope < Scope
    def resolve
      return super if user&.amplifa_admin?

      # WHY: Customers can only see meetings belonging to their org's agents
      return scope.none unless current_organization_id

      scope.joins(:agent).where(agents: { organization_id: current_organization_id })
    end
  end

  private

  def belongs_to_user_organization?
    same_current_organization?(record.agent&.organization_id)
  end
end
