require "test_helper"

class ImpersonationTest < ActionDispatch::IntegrationTest
  # WHY: We need this helper to log in users before testing impersonation
  # because impersonation is only available to authenticated admins
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

  test "amplifa admin can start impersonation of a customer user" do
    # WHY: This is the core functionality - admins need to be able to impersonate
    # customers for support purposes. This tests the happy path.
    admin = accounts(:amplifa_admin)
    customer = accounts(:customer_user)

    login_as(admin)

    # Start impersonation
    post admin_impersonate_path(customer)
    assert_response :redirect

    # WHY: We need to verify the session now contains both the impersonated
    # account and the original admin ID so we can restore later
    assert_equal customer.id, session[:account_id]
    assert_equal admin.id, session[:impersonating_admin_id]

    # WHY: After impersonation, the admin should see the customer's dashboard
    # not the admin dashboard
    follow_redirect!
    assert_equal dashboard_path, path
  end

  test "impersonation creates audit log entry" do
    # WHY: For security and compliance, every impersonation must be logged
    # so we can track which admins accessed which customer accounts
    admin = accounts(:amplifa_admin)
    customer = accounts(:customer_user)

    login_as(admin)

    assert_difference "AdminActivity.count", 1 do
      post admin_impersonate_path(customer)
    end

    activity = AdminActivity.last
    # WHY: The audit log must record who performed the action (the admin)
    assert_equal admin.id, activity.account_id
    # WHY: The audit log must show which customer was impersonated
    assert_equal "impersonate_user", activity.action
    # WHY: Details should include the target account for investigation purposes
    assert_equal customer.id, activity.details["target_account_id"]
    assert_equal customer.email, activity.details["target_email"]
  end

  test "while impersonating current_account returns customer account" do
    # WHY: When impersonating, all authorization and scoping must use the
    # customer's account, not the admin's, so the admin sees exactly what
    # the customer sees
    admin = accounts(:amplifa_admin)
    customer = accounts(:customer_user)

    login_as(admin)
    post admin_impersonate_path(customer)

    # WHY: We check the dashboard to ensure current_account is working
    # properly during impersonation
    get dashboard_path, headers: inertia_headers
    assert_response :success

    # WHY: The Inertia props should show the customer's data, not admin's
    body = JSON.parse(response.body)
    assert_equal customer.id, body["props"]["auth"]["account"]["id"]
    assert_equal customer.email, body["props"]["auth"]["account"]["email"]
  end

  test "impersonation banner data is present in shared props" do
    # WHY: The frontend needs to know when impersonation is active so it can
    # display the banner and provide the exit button
    admin = accounts(:amplifa_admin)
    customer = accounts(:customer_user)

    login_as(admin)
    post admin_impersonate_path(customer)

    get dashboard_path, headers: inertia_headers
    assert_response :success

    body = JSON.parse(response.body)
    # WHY: Shared props must include impersonation flag so banner can show
    assert_equal true, body["props"]["impersonating"]
    # WHY: Banner needs original admin name to display "Acting as X on behalf of Y"
    assert_equal admin.full_name, body["props"]["impersonating_admin"]["name"]
  end

  test "exiting impersonation returns to admin session" do
    # WHY: Admins must be able to cleanly exit impersonation and return to
    # their own admin session without needing to log in again
    admin = accounts(:amplifa_admin)
    customer = accounts(:customer_user)

    login_as(admin)
    post admin_impersonate_path(customer)

    # Exit impersonation
    post admin_exit_impersonation_path
    assert_response :redirect

    # WHY: Session should be restored to the original admin
    assert_equal admin.id, session[:account_id]
    # WHY: Impersonation tracking should be cleared
    assert_nil session[:impersonating_admin_id]

    # WHY: After exiting, admin should be redirected back to admin dashboard
    follow_redirect!
    assert_equal admin_dashboard_path, path
  end

  test "exit impersonation creates audit log entry" do
    # WHY: For security audit trail, we need to log both start AND end of
    # impersonation sessions to track duration and verify proper exit
    admin = accounts(:amplifa_admin)
    customer = accounts(:customer_user)

    login_as(admin)
    post admin_impersonate_path(customer)

    assert_difference "AdminActivity.count", 1 do
      post admin_exit_impersonation_path
    end

    activity = AdminActivity.last
    # WHY: Exit action should be logged under the original admin's ID
    assert_equal admin.id, activity.account_id
    assert_equal "exit_impersonation", activity.action
    # WHY: Details should show which customer account was being impersonated
    assert_equal customer.id, activity.details["customer_account_id"]
  end

  test "customer admin cannot impersonate anyone" do
    # WHY: Only amplifa_admin users should be able to impersonate. Customer
    # admins should not be able to impersonate their own users - this prevents
    # privilege escalation
    customer_admin = accounts(:customer_admin)
    customer_user = accounts(:customer_user)

    login_as(customer_admin)

    # WHY: Attempting to impersonate should result in authorization failure.
    # Admin::BaseController.require_amplifa_admin! redirects non-admins.
    post admin_impersonate_path(customer_user), headers: inertia_headers
    assert_response :redirect
    assert_redirected_to root_path
    assert_equal "Access denied", flash[:alert]

    # WHY: No audit log should be created for failed authorization attempts
    # (though we might want to log these separately for security monitoring)
    refute AdminActivity.exists?(action: "impersonate_user", account_id: customer_admin.id)
  end

  test "customer user cannot impersonate anyone" do
    # WHY: Regular customer users should have no impersonation capability
    # This ensures the feature is properly locked down to amplifa admins only
    customer1 = accounts(:customer_user)
    customer2 = accounts(:growth_lab_user)

    login_as(customer1)

    # WHY: Customer users shouldn't even be able to access impersonation routes.
    # Admin::BaseController.require_amplifa_admin! redirects non-admins.
    post admin_impersonate_path(customer2), headers: inertia_headers
    assert_response :redirect
    assert_redirected_to root_path
    assert_equal "Access denied", flash[:alert]
  end

  test "cannot impersonate while already impersonating" do
    # WHY: Nested impersonation would create session management complexity and
    # security issues. We should prevent impersonating while already impersonating.
    admin = accounts(:amplifa_admin)
    customer1 = accounts(:customer_user)
    customer2 = accounts(:growth_lab_user)

    login_as(admin)
    post admin_impersonate_path(customer1)

    # WHY: When impersonating, current_account is the impersonated customer,
    # which is not an amplifa_admin. The base controller's require_amplifa_admin!
    # runs before ensure_not_impersonating, so this results in a redirect.
    # This is actually correct behavior - if someone tries to access admin routes
    # while impersonating a customer, they should be denied access.
    post admin_impersonate_path(customer2), headers: inertia_headers
    assert_response :redirect
    assert_redirected_to root_path
    assert_equal "Access denied", flash[:alert]

    # WHY: Session should still show first impersonation
    assert_equal customer1.id, session[:account_id]
  end

  test "session data is correct during impersonation" do
    # WHY: Throughout the impersonation session, we need to maintain both
    # the impersonated account ID and the original admin ID for proper
    # tracking and ability to exit
    admin = accounts(:amplifa_admin)
    customer = accounts(:customer_user)

    login_as(admin)

    # Before impersonation
    assert_equal admin.id, session[:account_id]
    assert_nil session[:impersonating_admin_id]

    # Start impersonation
    post admin_impersonate_path(customer)

    # During impersonation
    assert_equal customer.id, session[:account_id]
    assert_equal admin.id, session[:impersonating_admin_id]

    # Exit impersonation
    post admin_exit_impersonation_path

    # After exit
    assert_equal admin.id, session[:account_id]
    assert_nil session[:impersonating_admin_id]
  end

  test "cannot impersonate another amplifa admin" do
    # WHY: Admins should only be able to impersonate customers, not other admins.
    # This prevents lateral movement between admin accounts and maintains
    # accountability.
    admin1 = accounts(:amplifa_admin)
    # Create second admin for test
    admin2 = Account.create!(
      email: "admin2@amplifa.com",
      first_name: "Admin",
      last_name: "Two",
      password_hash: RodauthApp.rodauth.allocate.password_hash("password123"),
      status: :verified,
      role: "amplifa_admin"
    )

    login_as(admin1)

    # WHY: Attempting to impersonate another admin should be rejected
    post admin_impersonate_path(admin2), headers: inertia_headers
    # Inertia renders with 200 OK but includes error in props
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal "Error", body["component"]
    assert_equal "Can only impersonate customer users", body["props"]["message"]
    assert_equal 422, body["props"]["status"]
  end

  test "logging out while impersonating ends both sessions" do
    # WHY: If an admin logs out while impersonating, we should end both the
    # impersonation and the admin session completely. This prevents security
    # issues where the customer session might remain active.
    admin = accounts(:amplifa_admin)
    customer = accounts(:customer_user)

    login_as(admin)
    post admin_impersonate_path(customer)

    # Logout while impersonating
    post logout_path
    assert_response :redirect

    # WHY: All session data should be cleared on logout
    assert_nil session[:impersonating_admin_id]

    # WHY: Rodauth logout redirects to login page, which is expected
    follow_redirect!
    assert_match /login/, path
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
