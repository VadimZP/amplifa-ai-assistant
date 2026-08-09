require "test_helper"

class AdminActivityPolicyTest < ActiveSupport::TestCase
  test "amplifa admin can view activities index" do
    # WHY: Amplifa admins are the only ones who should have access to the
    # audit log for security and compliance purposes
    admin = accounts(:amplifa_admin)
    policy = AdminActivityPolicy.new(admin, AdminActivity)

    assert policy.index?, "Amplifa admin should be able to view activities index"
  end

  test "amplifa admin can view individual activity" do
    # WHY: Amplifa admins need to see detailed information about specific
    # activities for investigation purposes
    admin = accounts(:amplifa_admin)
    activity = admin_activities(:impersonation_recent)
    policy = AdminActivityPolicy.new(admin, activity)

    assert policy.show?, "Amplifa admin should be able to view activity details"
  end

  test "customer admin cannot view activities index" do
    # WHY: Customer admins should not have access to the system-wide audit log
    # as it contains sensitive information about other customers
    customer_admin = accounts(:customer_admin)
    policy = AdminActivityPolicy.new(customer_admin, AdminActivity)

    refute policy.index?, "Customer admin should not be able to view activities index"
  end

  test "customer admin cannot view individual activity" do
    # WHY: Even with direct access to an activity ID, customer admins should
    # not be able to view activity details
    customer_admin = accounts(:customer_admin)
    activity = admin_activities(:impersonation_recent)
    policy = AdminActivityPolicy.new(customer_admin, activity)

    refute policy.show?, "Customer admin should not be able to view activity details"
  end

  test "customer user cannot view activities index" do
    # WHY: Regular customer users should have no access to admin activities
    customer_user = accounts(:customer_user)
    policy = AdminActivityPolicy.new(customer_user, AdminActivity)

    refute policy.index?, "Customer user should not be able to view activities index"
  end

  test "customer user cannot view individual activity" do
    # WHY: Regular customer users should have no access to individual activities
    customer_user = accounts(:customer_user)
    activity = admin_activities(:impersonation_recent)
    policy = AdminActivityPolicy.new(customer_user, activity)

    refute policy.show?, "Customer user should not be able to view activity details"
  end

  test "scope returns all activities for amplifa admin" do
    # WHY: Amplifa admins should see all activities across all organizations
    # for complete audit visibility
    admin = accounts(:amplifa_admin)
    scope = AdminActivityPolicy::Scope.new(admin, AdminActivity).resolve

    total_activities = AdminActivity.count
    assert_equal total_activities, scope.count,
      "Amplifa admin should see all activities"
  end

  test "scope returns no activities for customer admin" do
    # WHY: Customer admins should not have access to any activities, so the
    # scope should return an empty collection
    customer_admin = accounts(:customer_admin)
    scope = AdminActivityPolicy::Scope.new(customer_admin, AdminActivity).resolve

    assert_equal 0, scope.count,
      "Customer admin should see no activities"
  end

  test "scope returns no activities for customer user" do
    # WHY: Regular customer users should not have access to any activities
    customer_user = accounts(:customer_user)
    scope = AdminActivityPolicy::Scope.new(customer_user, AdminActivity).resolve

    assert_equal 0, scope.count,
      "Customer user should see no activities"
  end
end
