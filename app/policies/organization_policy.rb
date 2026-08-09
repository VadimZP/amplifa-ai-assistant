class OrganizationPolicy < ApplicationPolicy
  def show?
    super || current_organization_id == record.id
  end

  def update?
    super || (customer_admin? && current_organization_id == record.id)
  end

  def update_company_settings?
    # WHY: Allow amplifa admins to edit any organization's settings (for support)
    # and allow customer admins to edit their own organization's settings
    # Customer users cannot edit settings (read-only access)
    amplifa_admin? || (customer_admin? && record.id == current_organization_id)
  end

  # WHY: Only Amplifa admins can update Slack webhook configuration.
  # This is a sensitive integration setting that controls notifications.
  def update_slack_settings?
    amplifa_admin?
  end

  class Scope < Scope
    def resolve
      return super if user&.amplifa_admin?
      return scope.none unless current_organization_id

      scope.where(id: current_organization_id)
    end
  end
end
