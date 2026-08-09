# TeamPolicy
#
# This is a controller-level policy for the TeamController.
# Since TeamController doesn't have a specific model, we use a symbol-based policy.
#
# WHY: All authenticated users should be able to view their team:
# - Customer users see their organization's team members
# - Amplifa admins see other amplifa admins (internal staff)
class TeamPolicy < Struct.new(:user, :team)
  def index?
    # WHY: All authenticated users can access the team page.
    # The TeamController handles showing the appropriate team members:
    # - Amplifa admins see other amplifa admins
    # - Customer users see their organization's members
    user.present?
  end
end
