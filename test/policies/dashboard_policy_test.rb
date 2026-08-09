require "test_helper"

class DashboardPolicyTest < ActiveSupport::TestCase
  def setup
    @amplifa_admin = accounts(:amplifa_admin)
    @customer_admin = accounts(:customer_admin)
    @customer_user = accounts(:customer_user)
  end

  test "index? returns true for customer_admin" do
    # WHY: Customer admins need access to the dashboard to see
    # campaign stats, team info, and manage their organization
    policy = DashboardPolicy.new(@customer_admin, :dashboard)
    assert policy.index?, "Customer admin should be able to view dashboard"
  end

  test "index? returns true for customer_user" do
    # WHY: Regular customer users need access to the dashboard to
    # view campaign performance and lead information
    policy = DashboardPolicy.new(@customer_user, :dashboard)
    assert policy.index?, "Customer user should be able to view dashboard"
  end

  test "index? returns true for amplifa_admin" do
    # WHY: Amplifa admins access the dashboard route, which redirects
    # them to the admin dashboard. The policy allows access, and the
    # controller handles the redirect logic.
    policy = DashboardPolicy.new(@amplifa_admin, :dashboard)
    assert policy.index?, "Amplifa admin should be able to access dashboard (redirects to admin version)"
  end

  test "index? returns false for nil user" do
    # WHY: Unauthenticated users should not be able to access
    # any dashboard - they should be redirected to login
    policy = DashboardPolicy.new(nil, :dashboard)
    assert_not policy.index?, "Nil user should not access dashboard"
  end

  # AMP-435 §8 / bug B2-fallback: org_admin? must not use the legacy global
  # Account#role when no current-workspace membership is resolved (unreachable in
  # real requests). Membership-driven behavior is pinned by the sibling test below.
  test "org_admin? returns false for a customer_admin with no active workspace membership" do
    policy = DashboardPolicy.new(@customer_admin, :dashboard)
    assert_not policy.org_admin?, "customer_admin must not pass org_admin? without an active workspace membership"
  end

  test "org_admin? returns true for amplifa_admin" do
    policy = DashboardPolicy.new(@amplifa_admin, :dashboard)
    assert policy.org_admin?, "amplifa_admin is a global platform check and should always pass org_admin?"
  end

  test "org_admin? returns false for customer_user" do
    policy = DashboardPolicy.new(@customer_user, :dashboard)
    assert_not policy.org_admin?, "customer_user should not pass org_admin?"
  end

  test "org_admin? follows current-workspace membership role not global account role" do
    # WHY: AMP-435 §8 / bug B5 — org_admin? must reflect the CURRENT workspace
    # membership role. The account is customer_admin in org_a but only
    # customer_user in org_b, so org_admin? must flip with the active workspace.
    scenario = build_multi_org_scenario
    policy = DashboardPolicy.new(scenario.account, :dashboard)

    Current.organization_membership = scenario.membership_b
    assert_not policy.org_admin?,
               "org_admin? must be false when the active workspace membership is customer_user"

    Current.organization_membership = scenario.membership_a
    assert policy.org_admin?,
           "org_admin? must be true when the active workspace membership is customer_admin"
  ensure
    Current.organization_membership = nil
  end
end
