require "test_helper"

class InvitationPolicyTest < ActiveSupport::TestCase
  test "amplifa admin can view invitations index" do
    # WHY: Amplifa admins need to manage invitations across all organizations
    # to control who gets access to the platform
    admin = accounts(:amplifa_admin)
    policy = InvitationPolicy.new(admin, Invitation)

    assert policy.index?, "Amplifa admin should be able to view invitations index"
  end

  test "amplifa admin can create invitations" do
    # WHY: Only amplifa admins should be able to invite new users to ensure
    # proper access control and security
    admin = accounts(:amplifa_admin)
    policy = InvitationPolicy.new(admin, Invitation)

    assert policy.create?, "Amplifa admin should be able to create invitations"
  end

  test "amplifa admin can resend invitations" do
    # WHY: Amplifa admins need to resend invitations when they expire or
    # when users don't receive the original email
    admin = accounts(:amplifa_admin)
    invitation = Invitation.new
    policy = InvitationPolicy.new(admin, invitation)

    assert policy.resend?, "Amplifa admin should be able to resend invitations"
  end

  test "amplifa admin can cancel invitations" do
    # WHY: Amplifa admins need to cancel invitations to revoke access
    # before an invitation is accepted
    admin = accounts(:amplifa_admin)
    invitation = Invitation.new
    policy = InvitationPolicy.new(admin, invitation)

    assert policy.cancel?, "Amplifa admin should be able to cancel invitations"
  end

  test "amplifa admin can destroy invitations" do
    # WHY: Amplifa admins need to clean up old invitation records for
    # data management purposes
    admin = accounts(:amplifa_admin)
    invitation = Invitation.new
    policy = InvitationPolicy.new(admin, invitation)

    assert policy.destroy?, "Amplifa admin should be able to destroy invitations"
  end

  test "customer admin cannot view invitations index" do
    # WHY: Invitation management is admin-only functionality. Customer admins
    # should not be able to see or manage invitations
    customer_admin = accounts(:customer_admin)
    policy = InvitationPolicy.new(customer_admin, Invitation)

    refute policy.index?, "Customer admin should not be able to view invitations index"
  end

  test "customer admin cannot create invitations" do
    # WHY: Only amplifa admins control who gets invited to the platform
    customer_admin = accounts(:customer_admin)
    policy = InvitationPolicy.new(customer_admin, Invitation)

    refute policy.create?, "Customer admin should not be able to create invitations"
  end

  test "customer admin cannot resend invitations" do
    # WHY: Customer admins have no access to invitation management
    customer_admin = accounts(:customer_admin)
    invitation = Invitation.new
    policy = InvitationPolicy.new(customer_admin, invitation)

    refute policy.resend?, "Customer admin should not be able to resend invitations"
  end

  test "customer admin cannot cancel invitations" do
    # WHY: Customer admins should not be able to interfere with the
    # invitation process managed by amplifa admins
    customer_admin = accounts(:customer_admin)
    invitation = Invitation.new
    policy = InvitationPolicy.new(customer_admin, invitation)

    refute policy.cancel?, "Customer admin should not be able to cancel invitations"
  end

  test "customer admin cannot destroy invitations" do
    # WHY: Only amplifa admins should be able to delete invitation records
    customer_admin = accounts(:customer_admin)
    invitation = Invitation.new
    policy = InvitationPolicy.new(customer_admin, invitation)

    refute policy.destroy?, "Customer admin should not be able to destroy invitations"
  end

  test "customer user cannot view invitations index" do
    # WHY: Regular customer users should have no access to invitation management
    customer_user = accounts(:customer_user)
    policy = InvitationPolicy.new(customer_user, Invitation)

    refute policy.index?, "Customer user should not be able to view invitations index"
  end

  test "customer user cannot create invitations" do
    # WHY: Regular customer users should not be able to invite others
    customer_user = accounts(:customer_user)
    policy = InvitationPolicy.new(customer_user, Invitation)

    refute policy.create?, "Customer user should not be able to create invitations"
  end

  test "customer user cannot resend invitations" do
    # WHY: Regular customer users have no invitation management capabilities
    customer_user = accounts(:customer_user)
    invitation = Invitation.new
    policy = InvitationPolicy.new(customer_user, invitation)

    refute policy.resend?, "Customer user should not be able to resend invitations"
  end

  test "customer user cannot cancel invitations" do
    # WHY: Regular customer users should not be able to interfere with invitations
    customer_user = accounts(:customer_user)
    invitation = Invitation.new
    policy = InvitationPolicy.new(customer_user, invitation)

    refute policy.cancel?, "Customer user should not be able to cancel invitations"
  end

  test "customer user cannot destroy invitations" do
    # WHY: Regular customer users should not be able to delete invitation records
    customer_user = accounts(:customer_user)
    invitation = Invitation.new
    policy = InvitationPolicy.new(customer_user, invitation)

    refute policy.destroy?, "Customer user should not be able to destroy invitations"
  end

  test "scope returns all invitations for amplifa admin" do
    # WHY: Amplifa admins should see all invitations across all organizations
    # for complete visibility and management
    admin = accounts(:amplifa_admin)
    scope = InvitationPolicy::Scope.new(admin, Invitation).resolve

    total_invitations = Invitation.count
    assert_equal total_invitations, scope.count,
      "Amplifa admin should see all invitations"
  end

  test "scope returns no invitations for customer admin" do
    # WHY: Customer admins should not have access to any invitations, so the
    # scope should return an empty collection
    customer_admin = accounts(:customer_admin)
    scope = InvitationPolicy::Scope.new(customer_admin, Invitation).resolve

    assert_equal 0, scope.count,
      "Customer admin should see no invitations"
  end

  test "scope returns no invitations for customer user" do
    # WHY: Regular customer users should not have access to any invitations
    customer_user = accounts(:customer_user)
    scope = InvitationPolicy::Scope.new(customer_user, Invitation).resolve

    assert_equal 0, scope.count,
      "Customer user should see no invitations"
  end
end
