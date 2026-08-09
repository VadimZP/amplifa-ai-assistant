require "test_helper"

class AdminActivityTest < ActiveSupport::TestCase
  # Why: AdminActivity provides an audit trail of all administrative actions,
  # which is critical for security, compliance, and debugging

  def setup
    @admin = accounts(:amplifa_admin)
    @organization = organizations(:acme)
  end

  # Validation tests
  # Why: We need to ensure all required fields are present for a complete audit trail
  test "should require account_id" do
    activity = AdminActivity.new(
      action: "test_action",
      details: {}
    )
    refute activity.valid?
    assert_includes activity.errors[:account_id], "can't be blank"
  end

  test "should require action" do
    activity = AdminActivity.new(
      account: @admin,
      details: {}
    )
    refute activity.valid?
    assert_includes activity.errors[:action], "can't be blank"
  end

  test "should require details" do
    activity = AdminActivity.new(
      account: @admin,
      action: "test_action",
      details: nil
    )
    refute activity.valid?
    assert_includes activity.errors[:details], "can't be blank"
  end

  test "should validate action length" do
    activity = AdminActivity.new(
      account: @admin,
      action: "a" * 101,
      details: {}
    )
    refute activity.valid?
    assert_includes activity.errors[:action], "is too long (maximum is 100 characters)"
  end

  test "should allow minimum action length" do
    activity = AdminActivity.new(
      account: @admin,
      action: "a",
      details: {}
    )
    assert activity.valid?
  end

  # Association tests
  # Why: Activities must be properly linked to accounts and optionally to organizations
  test "should belong to account" do
    activity = AdminActivity.new(account: @admin, action: "test", details: {})
    assert_equal @admin, activity.account
  end

  test "should belong to organization optionally" do
    activity = AdminActivity.new(
      account: @admin,
      organization: @organization,
      action: "test",
      details: {}
    )
    assert_equal @organization, activity.organization
  end

  test "should allow nil organization" do
    activity = AdminActivity.new(
      account: @admin,
      organization: nil,
      action: "test",
      details: {}
    )
    assert activity.valid?
  end

  # Scope tests
  # Why: Scopes are used to filter activities by organization, action type, etc.
  test "for_organization scope filters by organization" do
    activity1 = AdminActivity.create!(
      account: @admin,
      organization: @organization,
      action: "test_action",
      details: {}
    )

    other_org = organizations(:beta)
    activity2 = AdminActivity.create!(
      account: @admin,
      organization: other_org,
      action: "test_action",
      details: {}
    )

    activities = AdminActivity.for_organization(@organization)
    assert_includes activities, activity1
    refute_includes activities, activity2
  end

  test "by_action scope filters by action type" do
    activity1 = AdminActivity.create!(
      account: @admin,
      action: "create_organization",
      details: {}
    )

    activity2 = AdminActivity.create!(
      account: @admin,
      action: "update_organization",
      details: {}
    )

    activities = AdminActivity.by_action("create_organization")
    assert_includes activities, activity1
    refute_includes activities, activity2
  end

  test "recent scope orders by created_at descending" do
    # WHY: Use very recent timestamps (hours, not days) to ensure these activities
    # are more recent than fixture activities (which use days)
    activity1 = AdminActivity.create!(
      account: @admin,
      action: "test1",
      details: {},
      created_at: 2.hours.ago
    )

    activity2 = AdminActivity.create!(
      account: @admin,
      action: "test2",
      details: {},
      created_at: 1.hour.ago
    )

    recent = AdminActivity.recent.limit(2)
    assert_equal activity2.id, recent.first.id, "Most recent activity should be first"
    assert_equal activity1.id, recent.last.id, "Second most recent activity should be last"
  end

  test "impersonation_actions scope filters impersonation events" do
    activity1 = AdminActivity.create!(
      account: @admin,
      action: "login_as_customer",
      details: {}
    )

    activity2 = AdminActivity.create!(
      account: @admin,
      action: "exit_impersonation",
      details: {}
    )

    activity3 = AdminActivity.create!(
      account: @admin,
      action: "create_organization",
      details: {}
    )

    impersonation_activities = AdminActivity.impersonation_actions
    assert_includes impersonation_activities, activity1
    assert_includes impersonation_activities, activity2
    refute_includes impersonation_activities, activity3
  end

  # Class method tests
  # Why: The log_activity helper method provides a convenient way to create audit logs
  test "log_activity creates activity with all fields" do
    activity = AdminActivity.log_activity(
      account: @admin,
      action: "test_action",
      organization: @organization,
      details: { test: "value" },
      ip_address: "192.168.1.1",
      user_agent: "Test Browser"
    )

    assert activity.persisted?
    assert_equal @admin, activity.account
    assert_equal @organization, activity.organization
    assert_equal "test_action", activity.action
    assert_equal({ "test" => "value" }, activity.details)
    assert_equal "192.168.1.1", activity.ip_address
    assert_equal "Test Browser", activity.user_agent
  end

  test "log_activity works without optional fields" do
    activity = AdminActivity.log_activity(
      account: @admin,
      action: "test_action",
      details: {}
    )

    assert activity.persisted?
    assert_equal @admin, activity.account
    assert_nil activity.organization
    assert_nil activity.ip_address
    assert_nil activity.user_agent
  end

  # JSONB details field tests
  # Why: The details field stores flexible JSON data that varies by action type
  test "should store and retrieve JSON details" do
    activity = AdminActivity.create!(
      account: @admin,
      action: "create_organization",
      details: {
        organization_name: "Test Corp",
        website: "https://test.com",
        status: "onboarding"
      }
    )

    activity.reload
    assert_equal "Test Corp", activity.details["organization_name"]
    assert_equal "https://test.com", activity.details["website"]
    assert_equal "onboarding", activity.details["status"]
  end

  test "should handle empty details hash" do
    activity = AdminActivity.create!(
      account: @admin,
      action: "test_action",
      details: {}
    )

    activity.reload
    assert_equal({}, activity.details)
  end

  test "should handle nested JSON in details" do
    activity = AdminActivity.create!(
      account: @admin,
      action: "update_organization",
      details: {
        changes: {
          status: ["onboarding", "active"],
          website: [nil, "https://example.com"]
        }
      }
    )

    activity.reload
    assert_equal ["onboarding", "active"], activity.details["changes"]["status"]
    assert_equal [nil, "https://example.com"], activity.details["changes"]["website"]
  end
end
