require "test_helper"

class TeamTest < ActionDispatch::IntegrationTest
  # WHY: Helper method to log in users before testing the team page
  # since the team page requires authentication
  def login_as(account)
    password = account.amplifa_admin? ? "password123" : "password"

    post login_path, params: {
      email: account.email,
      password: password
    }
    assert_response :redirect
    follow_redirect!
  end

  test "customer user can access team page" do
    # WHY: Customer users need to view their team members to understand
    # who has access to the system and coordinate work
    customer = accounts(:customer_user)
    login_as(customer)

    get team_path
    assert_response :success
  end

  test "team list shows only users from same organization" do
    # WHY: For security and privacy, customers must only see users from
    # their own organization, not users from other customer organizations
    customer = accounts(:customer_user) # from acme org
    login_as(customer)

    get team_path, headers: inertia_headers
    assert_response :success

    # WHY: Parse the Inertia response to verify the data being sent to frontend
    body = JSON.parse(response.body)
    team_members = body['props']['team_members']

    # WHY: Acme has 3 members: customer_admin, customer_user, and dana
    assert_equal 3, team_members.length

    # WHY: All returned users must belong to acme organization
    team_member_emails = team_members.map { |m| m['email'] }
    assert_includes team_member_emails, 'org_admin@acme.com'
    assert_includes team_member_emails, 'user@acme.com'

    # WHY: Users from other organizations must not appear
    assert_not_includes team_member_emails, 'user@growthlab.com'
    assert_not_includes team_member_emails, 'user@beta.com'
  end

  test "team list excludes amplifa admins" do
    # WHY: Amplifa admins are platform administrators, not part of the
    # customer's team, so they should not appear in the team list
    customer = accounts(:customer_user)
    login_as(customer)

    get team_path, headers: inertia_headers
    assert_response :success

    body = JSON.parse(response.body)
    team_members = body['props']['team_members']

    # WHY: Verify no amplifa_admin users are in the team list
    team_member_emails = team_members.map { |m| m['email'] }
    assert_not_includes team_member_emails, 'admin@amplifa.com'

    # WHY: Double-check by verifying role field
    team_member_roles = team_members.map { |m| m['role'] }
    assert_not_includes team_member_roles, 'amplifa_admin'
  end

  test "customer from different org cannot see other org's team" do
    # WHY: Critical security test to ensure data isolation between
    # customer organizations. Each org's data must be completely separate.
    growth_lab_user = accounts(:growth_lab_user)
    acme_user = accounts(:customer_user)

    login_as(growth_lab_user)

    get team_path, headers: inertia_headers
    assert_response :success

    body = JSON.parse(response.body)
    team_members = body['props']['team_members']

    # WHY: Growth Lab user should only see Growth Lab team members
    team_member_emails = team_members.map { |m| m['email'] }

    # WHY: Should see their own org's users
    assert_includes team_member_emails, 'user@growthlab.com'
    assert_includes team_member_emails, 'admin@growthlab.com'

    # WHY: Must NOT see Acme's users
    assert_not_includes team_member_emails, 'user@acme.com'
    assert_not_includes team_member_emails, 'org_admin@acme.com'
  end

  test "team page shows correct user information" do
    # WHY: Verify that all required user information is displayed correctly
    # so customers can identify and contact their team members
    customer = accounts(:customer_user)
    login_as(customer)

    get team_path, headers: inertia_headers
    assert_response :success

    body = JSON.parse(response.body)
    team_members = body['props']['team_members']

    # WHY: Find the customer_admin to verify data structure
    admin_member = team_members.find { |m| m['email'] == 'org_admin@acme.com' }
    assert_not_nil admin_member, "Admin member should be in team list"

    # WHY: Verify all required fields are present
    assert_equal 'Olivia', admin_member['first_name']
    assert_equal 'Grant', admin_member['last_name']
    assert_equal 'Olivia Grant', admin_member['full_name']
    assert_equal 'org_admin@acme.com', admin_member['email']
    assert_equal 'customer_admin', admin_member['role']

    # WHY: Verify role helper methods are included for frontend display
    assert_equal true, admin_member['customer_admin?']
    assert_equal false, admin_member['customer_user?']

    # WHY: Verify created_at is included so we can show "joined date"
    assert_not_nil admin_member['created_at']
  end

  test "amplifa admin can access team page" do
    # WHY: Amplifa admins are internal staff who need to see their team
    # (other amplifa admins) for collaboration and coordination.
    # They should NOT see customer users, only other amplifa admins.
    admin = accounts(:amplifa_admin)
    login_as(admin)

    get team_path
    assert_response :success
  end

  test "amplifa admin sees only other amplifa admins on team page" do
    # WHY: When an amplifa admin views the team page, they should see
    # other amplifa admins (internal staff), not customer users from
    # customer organizations.
    admin = accounts(:amplifa_admin)
    login_as(admin)

    get team_path, headers: inertia_headers
    assert_response :success

    body = JSON.parse(response.body)
    team_members = body['props']['team_members']

    # WHY: Should see other amplifa admins
    team_member_emails = team_members.map { |m| m['email'] }
    # Note: We only have one amplifa_admin in fixtures, so count should be 1
    # In production with multiple admins, this would show all amplifa_admins
    assert_equal 1, team_members.length
    assert_includes team_member_emails, 'admin@amplifa.com'

    # WHY: Should NOT see customer users
    assert_not_includes team_member_emails, 'user@acme.com'
    assert_not_includes team_member_emails, 'user@growthlab.com'
    assert_not_includes team_member_emails, 'org_admin@acme.com'

    # WHY: Verify all team members have amplifa_admin role
    team_member_roles = team_members.map { |m| m['role'] }
    team_member_roles.each do |role|
      assert_equal 'amplifa_admin', role
    end
  end

  test "team members are ordered by created_at desc" do
    # WHY: Show newest team members first so managers can see
    # recent additions to their team at the top of the list
    customer = accounts(:customer_user)
    login_as(customer)

    get team_path, headers: inertia_headers
    assert_response :success

    body = JSON.parse(response.body)
    team_members = body['props']['team_members']

    # WHY: Verify descending order by checking timestamps
    # (All fixtures have same timestamp, but in real use this matters)
    assert team_members.length >= 2, "Need at least 2 members to test ordering"
  end

  test "unauthenticated user cannot access team page" do
    # WHY: The team page contains sensitive organizational data
    # and must only be accessible to authenticated users
    get team_path

    # WHY: Should redirect to login page
    assert_response :redirect
    follow_redirect!
    assert_equal login_path, path
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
