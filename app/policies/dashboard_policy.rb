# DashboardPolicy
#
# This is a controller-level policy for the DashboardController.
# Since DashboardController doesn't have a specific model, we use a symbol-based policy.
#
# WHY: All authenticated users should be able to access their dashboard.
# Admins are redirected to the admin dashboard in the controller logic.
class DashboardPolicy < ApplicationPolicy
  def index?
    # WHY: Any authenticated user can access a dashboard
    # The controller handles redirecting admins to the correct dashboard
    user.present?
  end

  # Used by OrgAdmin::DashboardController to authorize access to org admin pages.
  # Both customer admins and amplifa admins can access the org admin dashboard.
  def org_admin?
    customer_admin? || amplifa_admin?
  end
end
