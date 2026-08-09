require "test_helper"

class Admin::ActivitiesTest < ActionDispatch::IntegrationTest
  # WHY: This helper is needed to log in users before testing admin functions
  # because the activities list is only available to authenticated admins
  def login_as(account)
    # amplifa_admin uses password123, customers use password
    password = account.amplifa_admin? ? "password123" : "password"

    post login_path, params: {
      email: account.email,
      password: password
    }
    assert_response :redirect
    follow_redirect!
  end

  test "amplifa admin can view activities index" do
    # WHY: The activity log is a core admin feature for audit and compliance.
    # Amplifa admins should be able to see all administrative actions.
    admin = accounts(:amplifa_admin)
    login_as(admin)

    get admin_activities_path, headers: inertia_headers
    assert_response :success

    # WHY: Response should contain activity data in Inertia props
    body = JSON.parse(response.body)
    assert_equal 'Admin/Activities/Index', body['component']
    assert body['props']['activities'].is_a?(Array)
  end

  test "activities index shows recent activities by default" do
    # WHY: The default view should show recent activities (last 7 days) ordered
    # by newest first, making it easy for admins to see recent actions
    admin = accounts(:amplifa_admin)
    login_as(admin)

    get admin_activities_path, headers: inertia_headers
    assert_response :success

    body = JSON.parse(response.body)
    activities = body['props']['activities']

    # WHY: Should include recent activities (within 7 days)
    recent_activity_ids = [
      admin_activities(:impersonation_recent),
      admin_activities(:user_creation_recent),
      admin_activities(:org_update_recent),
      admin_activities(:impersonation_exit),
      admin_activities(:growth_lab_activity)
    ].map(&:id)

    returned_ids = activities.map { |a| a['id'] }
    recent_activity_ids.each do |id|
      assert_includes returned_ids, id, "Should include recent activity #{id}"
    end

    # WHY: Should NOT include old activities (older than 7 days)
    old_activity = admin_activities(:old_activity)
    refute_includes returned_ids, old_activity.id, "Should not include old activity by default"

    # WHY: Activities should be sorted newest first
    timestamps = activities.map { |a| Time.parse(a['created_at']) }
    assert_equal timestamps, timestamps.sort.reverse, "Activities should be sorted newest first"
  end

  test "can filter activities by organization" do
    # WHY: Admins need to filter activities by organization to investigate
    # actions related to a specific customer
    admin = accounts(:amplifa_admin)
    login_as(admin)

    acme_org = organizations(:acme)
    get admin_activities_path, params: { organization_id: acme_org.id }, headers: inertia_headers
    assert_response :success

    body = JSON.parse(response.body)
    activities = body['props']['activities']

    # WHY: All returned activities should belong to the filtered organization
    activities.each do |activity|
      assert_equal acme_org.id, activity['organization_id'],
        "Activity should belong to filtered organization"
    end

    # WHY: Should not include activities from other organizations
    growth_lab_activity = admin_activities(:growth_lab_activity)
    returned_ids = activities.map { |a| a['id'] }
    refute_includes returned_ids, growth_lab_activity.id,
      "Should not include activities from other organizations"
  end

  test "can filter activities by action type" do
    # WHY: Admins need to filter by action type to find specific types of
    # activities, like all impersonations or all user creations
    admin = accounts(:amplifa_admin)
    login_as(admin)

    get admin_activities_path, params: { action_type: 'impersonate_user' }, headers: inertia_headers
    assert_response :success

    body = JSON.parse(response.body)
    activities = body['props']['activities']

    # WHY: All returned activities should match the filtered action
    activities.each do |activity|
      assert_equal 'impersonate_user', activity['action'],
        "Activity should match filtered action type"
    end

    # WHY: Should only include impersonation activities
    assert activities.any?, "Should have at least one impersonation activity"
    impersonation_activity = admin_activities(:impersonation_recent)
    returned_ids = activities.map { |a| a['id'] }
    assert_includes returned_ids, impersonation_activity.id
  end

  test "can filter activities by date range" do
    # WHY: Admins need to filter by date range to investigate activities
    # during a specific time period
    admin = accounts(:amplifa_admin)
    login_as(admin)

    # WHY: Request activities from 10 days ago to 2 days ago
    start_date = 10.days.ago.to_date
    end_date = 2.days.ago.to_date

    get admin_activities_path, params: {
      start_date: start_date.iso8601,
      end_date: end_date.iso8601
    }, headers: inertia_headers
    assert_response :success

    body = JSON.parse(response.body)
    activities = body['props']['activities']

    # WHY: All activities should be within the date range
    activities.each do |activity|
      activity_date = Date.parse(activity['created_at'])
      assert activity_date >= start_date, "Activity should be after start date"
      assert activity_date <= end_date, "Activity should be before end date"
    end

    # WHY: Should include activities within range
    org_update = admin_activities(:org_update_recent)  # 3 days ago
    exit_imp = admin_activities(:impersonation_exit)    # 4 days ago
    growth_lab = admin_activities(:growth_lab_activity) # 5 days ago

    returned_ids = activities.map { |a| a['id'] }
    [org_update.id, exit_imp.id, growth_lab.id].each do |id|
      assert_includes returned_ids, id, "Should include activity within date range"
    end

    # WHY: Should NOT include activities outside range
    recent = admin_activities(:impersonation_recent) # 1 day ago (too recent)
    old = admin_activities(:old_activity)            # 30 days ago (too old)

    refute_includes returned_ids, recent.id, "Should not include too recent activity"
    refute_includes returned_ids, old.id, "Should not include too old activity"
  end

  test "can filter by multiple criteria simultaneously" do
    # WHY: Admins should be able to combine filters to narrow down activities,
    # e.g., "show me all impersonations for Acme in the last 30 days"
    admin = accounts(:amplifa_admin)
    login_as(admin)

    acme_org = organizations(:acme)
    get admin_activities_path, params: {
      organization_id: acme_org.id,
      action_type: 'impersonate_user',
      start_date: 7.days.ago.to_date.iso8601
    }, headers: inertia_headers
    assert_response :success

    body = JSON.parse(response.body)
    activities = body['props']['activities']

    # WHY: All activities should match ALL filter criteria
    activities.each do |activity|
      assert_equal acme_org.id, activity['organization_id']
      assert_equal 'impersonate_user', activity['action']
      activity_date = Date.parse(activity['created_at'])
      assert activity_date >= 7.days.ago.to_date
    end
  end

  test "activities are paginated" do
    # WHY: With many activities, pagination prevents performance issues and
    # improves user experience by loading data in chunks
    admin = accounts(:amplifa_admin)

    # WHY: Create enough activities to trigger pagination (50 per page)
    60.times do |i|
      AdminActivity.create!(
        account: admin,
        action: "test_action_#{i}",
        details: { test: true },
        created_at: Time.current - i.hours
      )
    end

    login_as(admin)

    get admin_activities_path, headers: inertia_headers
    assert_response :success

    body = JSON.parse(response.body)
    activities = body['props']['activities']

    # WHY: First page should have maximum of 50 activities
    assert activities.length <= 50, "Should have at most 50 activities per page"

    # WHY: Should include pagination metadata
    assert body['props']['pagination'], "Should include pagination metadata"
    assert body['props']['pagination']['total'] > 50, "Total should be more than 50"
  end

  test "amplifa admin can view individual activity details" do
    # WHY: Admins need to see detailed information about specific activities
    # for investigation and compliance purposes
    admin = accounts(:amplifa_admin)
    login_as(admin)

    activity = admin_activities(:impersonation_recent)
    get admin_activity_path(activity), headers: inertia_headers
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal 'Admin/Activities/Show', body['component']

    # WHY: Should show full activity details
    activity_data = body['props']['activity']
    assert_equal activity.id, activity_data['id']
    assert_equal activity.action, activity_data['action']
    assert_equal activity.details, activity_data['details']
    assert_equal activity.ip_address, activity_data['ip_address']
    assert_equal activity.user_agent, activity_data['user_agent']

    # WHY: Should include related account and organization data
    assert activity_data['account'], "Should include account data"
    assert_equal activity.account.full_name, activity_data['account']['name']

    if activity.organization
      assert activity_data['organization'], "Should include organization data"
      assert_equal activity.organization.name, activity_data['organization']['name']
    end
  end

  test "customer admin cannot access activities list" do
    # WHY: Activity logs contain sensitive audit information and should only
    # be accessible to Amplifa admins, not customer admins
    customer_admin = accounts(:customer_admin)
    login_as(customer_admin)

    get admin_activities_path, headers: inertia_headers
    # WHY: Admin::BaseController redirects non-admins with access denied message
    assert_response :redirect
    assert_redirected_to root_path
    assert_equal 'Access denied', flash[:alert]
  end

  test "customer user cannot access activities list" do
    # WHY: Regular customer users should have no access to the activity log
    customer_user = accounts(:customer_user)
    login_as(customer_user)

    get admin_activities_path, headers: inertia_headers
    # WHY: Admin::BaseController redirects non-admins with access denied message
    assert_response :redirect
    assert_redirected_to root_path
    assert_equal 'Access denied', flash[:alert]
  end

  test "customer admin cannot access individual activity" do
    # WHY: Even with direct ID access, customer admins should not be able
    # to view activity details
    customer_admin = accounts(:customer_admin)
    login_as(customer_admin)

    activity = admin_activities(:impersonation_recent)
    get admin_activity_path(activity), headers: inertia_headers
    # WHY: Admin::BaseController redirects non-admins with access denied message
    assert_response :redirect
    assert_redirected_to root_path
    assert_equal 'Access denied', flash[:alert]
  end

  test "activity list includes all necessary data for display" do
    # WHY: The frontend needs complete data to display activities without
    # additional requests, including account names and organization names
    admin = accounts(:amplifa_admin)
    login_as(admin)

    get admin_activities_path, headers: inertia_headers
    assert_response :success

    body = JSON.parse(response.body)
    activities = body['props']['activities']

    # WHY: Check first activity has all required fields for display
    first_activity = activities.first
    assert first_activity['id'], "Should have ID"
    assert first_activity['action'], "Should have action"
    assert first_activity['details'], "Should have details"
    assert first_activity['created_at'], "Should have timestamp"
    assert first_activity['account'], "Should have account info"
    assert first_activity['account']['name'], "Should have account name"
    assert first_activity['account']['email'], "Should have account email"

    # WHY: Organization may be null for some actions, but if present should have data
    if first_activity['organization_id']
      assert first_activity['organization'], "Should have organization info if org_id present"
      assert first_activity['organization']['name'], "Should have organization name"
    end
  end

  test "filter options are included in response" do
    # WHY: The frontend needs lists of available organizations and action types
    # to populate filter dropdowns without additional requests
    admin = accounts(:amplifa_admin)
    login_as(admin)

    get admin_activities_path, headers: inertia_headers
    assert_response :success

    body = JSON.parse(response.body)

    # WHY: Should include organizations for filter dropdown
    assert body['props']['organizations'], "Should include organizations list"
    assert body['props']['organizations'].is_a?(Array)
    assert body['props']['organizations'].length > 0, "Should have at least one organization"

    # WHY: Should include action types for filter dropdown
    assert body['props']['action_types'], "Should include action types list"
    assert body['props']['action_types'].is_a?(Array)
    assert body['props']['action_types'].length > 0, "Should have at least one action type"
  end

  private

  def inertia_headers
    {
      "HTTP_X_INERTIA" => "true",
      "HTTP_X_INERTIA_VERSION" => ViteRuby.digest,
      "HTTP_ACCEPT" => "text/html, application/xhtml+xml",
      "HTTP_X_REQUESTED_WITH" => "XMLHttpRequest"
    }
  end
end
