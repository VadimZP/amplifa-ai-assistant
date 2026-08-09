require 'test_helper'

class DashboardTest < ActionDispatch::IntegrationTest
  # WHY: Helper method to log in users before testing the dashboard
  # since the dashboard requires authentication
  def login_as(account)
    password = account.amplifa_admin? ? 'password123' : 'password'

    post login_path, params: {
      email: account.email,
      password: password
    }
    assert_response :redirect
    follow_redirect!
  end

  test 'customer user can access dashboard' do
    # WHY: Customer users need to access their dashboard to see their
    # organization's data and manage campaigns
    customer = accounts(:customer_user)
    login_as(customer)

    get dashboard_path
    assert_response :success
  end

  test 'amplifa admin is redirected to admin dashboard' do
    # WHY: When an amplifa admin visits the customer dashboard route,
    # they should be redirected to the admin dashboard instead.
    # This test ensures the redirect works without causing Pundit errors.
    # The DashboardController must call skip_policy_scope before redirecting
    # to avoid PolicyScopingNotPerformedError.
    admin = accounts(:amplifa_admin)
    login_as(admin)

    get dashboard_path

    # WHY: Should redirect to admin dashboard
    assert_response :redirect
    assert_redirected_to admin_dashboard_path
  end

  test 'customer user sees team member count' do
    # WHY: The dashboard should display basic organization metrics
    # like the number of team members to give customers visibility
    customer = accounts(:customer_user)
    login_as(customer)

    get dashboard_path, headers: inertia_headers
    assert_response :success

    # WHY: Parse the Inertia response to verify the data
    body = JSON.parse(response.body)
    user_count = body['props']['user_count']

    # WHY: Acme has 3 members (customer_admin, customer_user, and dana's membership)
    assert_equal 3, user_count
  end

  test 'dashboard blacklist is paginated at 10 entries' do
    customer = accounts(:customer_admin)
    login_as(customer)

    30.times do |i|
      Blacklist.create!(
        organization: customer.organization,
        created_by: customer,
        source: 'import',
        value: "dashboard-domain-#{i}.example",
        value_type: 'domain'
      )
    end

    get dashboard_path, headers: inertia_headers
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal 10, body.dig('props', 'blacklists').length
    assert_equal 10, body.dig('props', 'blacklist_pagination', 'per_page')
    assert_operator body.dig('props', 'blacklist_pagination', 'total_pages'), :>, 1
  end

  test 'dashboard provides enough domains and mailboxes for homepage see all lists' do
    customer = accounts(:customer_admin)
    organization = customer.organization
    sender = senders(:acme_john)
    login_as(customer)

    10.times do |i|
      domain = EmailDomain.create!(
        organization: organization,
        provider_type: 'google',
        domain: "dashboard-extra-#{i}.example.com",
        status: 'active'
      )

      3.times do |j|
        Mailbox.create!(
          organization: organization,
          email_domain: domain,
          sender: sender,
          email: "mailbox-#{i}-#{j}@dashboard-extra-#{i}.example.com",
          status: 'active',
          daily_send_limit: 100
        )
      end
    end

    get dashboard_path, headers: inertia_headers
    assert_response :success

    body = JSON.parse(response.body)
    assert_operator body.dig('props', 'domains').length, :>, 10
    assert_operator body.dig('props', 'mailboxes').length, :>, 25
    assert_operator body.dig('props', 'senders').find { |entry| entry['id'] == sender.id }['mailboxes'].length, :>, 20
  end

  test 'dashboard blacklist supports search filter' do
    customer = accounts(:customer_admin)
    login_as(customer)

    expected_total_entries = Blacklist.where(organization_id: customer.organization_id).count

    get dashboard_path(blacklist_search: 'competitor'), headers: inertia_headers
    assert_response :success

    body = JSON.parse(response.body)
    values = body.dig('props', 'blacklists').map { |entry| entry['value'] }

    assert_equal 'competitor', body.dig('props', 'blacklist_filters', 'search')
    assert_equal ['competitor@rival.com'], values
    assert_equal 1, body.dig('props', 'blacklist_count')
    assert_equal expected_total_entries, body.dig('props', 'blacklist_total_entries')
  end

  test 'customer user only sees count from their organization' do
    # WHY: Critical security test - ensure data scoping works correctly
    # so customers can only see data from their own organization
    growth_lab_user = accounts(:growth_lab_user)
    login_as(growth_lab_user)

    get dashboard_path, headers: inertia_headers
    assert_response :success

    body = JSON.parse(response.body)
    user_count = body['props']['user_count']

    # WHY: Growth Lab has 3 members (growth_lab_admin, growth_lab_user, and dana's secondary membership)
    assert_equal 3, user_count
  end

  test 'unauthenticated user cannot access dashboard' do
    # WHY: The dashboard contains sensitive organizational data
    # and must only be accessible to authenticated users
    get dashboard_path

    # WHY: Should redirect to login page
    assert_response :redirect
    follow_redirect!
    assert_equal login_path, path
  end

  test 'amplifa admin account data includes role methods in shared props' do
    # WHY: The frontend AuthenticatedLayout checks account['amplifa_admin?']
    # to determine whether to show admin or customer navigation.
    # This test verifies that Rails serializes the amplifa_admin? method
    # correctly so the frontend receives the correct boolean value.
    admin = accounts(:amplifa_admin)
    login_as(admin)

    # WHY: Make an Inertia request to admin organizations to check shared data
    get admin_organizations_path, headers: inertia_headers
    assert_response :success

    body = JSON.parse(response.body)
    account = body.dig('props', 'auth', 'account')

    # WHY: Verify the role methods are serialized with question marks
    # as Rails does by default when calling as_json with methods
    assert_not_nil account, 'Account should be present in shared props'
    assert_equal true, account['amplifa_admin?'], 'amplifa_admin? should be true for admin account'
    assert_equal false, account['customer_admin?'], 'customer_admin? should be false for admin account'
    assert_equal false, account['customer_user?'], 'customer_user? should be false for admin account'
    assert_equal 'amplifa_admin', account['role'], "role field should be 'amplifa_admin'"
  end

  test 'role-gated flags follow current-workspace membership role not global account role' do
    # WHY: AMP-435 §8 / bug B4 — can_edit and can_delete must reflect the CURRENT
    # workspace membership role, not the legacy global Account#role. The account
    # below is customer_admin in org_a but only customer_user in org_b, so the
    # dashboard flags must flip when the active workspace changes.
    scenario = build_multi_org_scenario

    # WHY: ensure_onboarded redirects to onboarding unless the active org is
    # onboarded, so both workspaces must be onboarded for the dashboard to render.
    scenario.org_a.update!(onboarded: true)
    scenario.org_b.update!(onboarded: true)

    # WHY: give each workspace a non-global blacklist entry so can_delete
    # (guarded by !bl.global?) is exercised alongside can_edit.
    Blacklist.create!(organization: scenario.org_a, created_by: scenario.account,
                      source: 'manual', value: 'org-a-block.example', value_type: 'domain')
    Blacklist.create!(organization: scenario.org_b, created_by: scenario.account,
                      source: 'manual', value: 'org-b-block.example', value_type: 'domain')

    login_as(scenario.account)

    # Active workspace = org_b, where the account is only a customer_user.
    post workspace_switch_path,
         params: { organization_id: scenario.org_b.id },
         headers: { 'HTTP_REFERER' => dashboard_url }

    get dashboard_path, headers: inertia_headers
    assert_response :success
    assert_equal scenario.org_b.id, inertia_props.dig('organization', 'id')
    assert_equal false, inertia_props['can_edit'],
                 'can_edit must be false for a customer_user in the active workspace'
    assert_equal [false], inertia_props['blacklists'].map { |entry| entry['can_delete'] }.uniq,
                 'can_delete must be false for a customer_user in the active workspace'

    # Active workspace = org_a, where the account is a customer_admin.
    post workspace_switch_path,
         params: { organization_id: scenario.org_a.id },
         headers: { 'HTTP_REFERER' => dashboard_url }

    get dashboard_path, headers: inertia_headers
    assert_response :success
    assert_equal scenario.org_a.id, inertia_props.dig('organization', 'id')
    assert_equal true, inertia_props['can_edit'],
                 'can_edit must be true for a customer_admin in the active workspace'
    assert_equal [true], inertia_props['blacklists'].map { |entry| entry['can_delete'] }.uniq,
                 'can_delete must be true for a customer_admin in the active workspace'
  end

  private

  def inertia_headers
    {
      'HTTP_X_INERTIA' => 'true',
      'HTTP_X_INERTIA_VERSION' => ViteRuby.digest,
      'HTTP_ACCEPT' => 'text/html, application/xhtml+xml',
      'HTTP_X_REQUESTED_WITH' => 'XMLHttpRequest'
    }
  end
end
