# InvitationPolicy - Only Amplifa admins can manage invitations.
# All CRUD actions inherit admin-only access from ApplicationPolicy.
class InvitationPolicy < ApplicationPolicy
  # WHY: Only amplifa admins should be able to resend invitations
  # for expired or undelivered invitation emails
  def resend?
    amplifa_admin?
  end

  # WHY: Only amplifa admins should be able to cancel pending invitations
  # to revoke access before an invitation is accepted
  def cancel?
    amplifa_admin?
  end

  class Scope < Scope
    def resolve
      return super if user&.amplifa_admin?
      # WHY: Customer users and admins should not see any invitations
      # as invitation management is admin-only functionality
      scope.none
    end
  end
end
