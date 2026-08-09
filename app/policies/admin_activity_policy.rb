# AdminActivityPolicy - Only Amplifa admins can access the audit log.
# All actions inherit admin-only access from ApplicationPolicy.
class AdminActivityPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      return super if user&.amplifa_admin?
      # WHY: Customer users and admins should see no activities
      scope.none
    end
  end
end
