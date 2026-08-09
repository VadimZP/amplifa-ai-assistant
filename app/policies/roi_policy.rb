# frozen_string_literal: true

# RoiPolicy
#
# Controller-level policy for the RoiController.
# Since RoiController doesn't have a specific model, we use a symbol-based policy.
#
# WHY: All authenticated non-admin users should be able to access the ROI dashboard.
# Admins are not expected to use this page (they can impersonate if needed).
class RoiPolicy < Struct.new(:user, :roi)
  def index?
    # WHY: Any authenticated customer user can view the ROI dashboard.
    # Admins can also access (e.g. when impersonating).
    user.present?
  end

  def update?
    user.present? && Current.organization.present?
  end
end
