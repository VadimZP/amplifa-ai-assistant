# frozen_string_literal: true

require "test_helper"

# Tests for Admin::BaseController authorization
# WHY: These tests verify that the centralized admin authorization works correctly
# for all controllers that inherit from Admin::BaseController. This is critical
# because improper authorization could expose admin functionality to unauthorized users.
class Admin::BaseControllerTest < ActionDispatch::IntegrationTest
  # WHY: Helper method to log in users for testing authenticated endpoints
  def login_as(account)
    password = account.amplifa_admin? ? "password123" : "password"

    post login_path, params: {
      email: account.email,
      password: password
    }
    assert_response :redirect
    follow_redirect!
  end

  # WHY: Test that amplifa admins can access admin pages.
  # This is the positive case - admins should have full access.
  test "amplifa admin can access admin organizations" do
    admin = accounts(:amplifa_admin)
    login_as(admin)

    get admin_organizations_path, headers: inertia_headers
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal "Admin/Organizations/Index", body["component"]
  end

  # WHY: Test that customer admins cannot access admin pages.
  # Customer admins have organization-level admin access but not platform-level access.
  # Admin::BaseController.require_amplifa_admin! redirects with 'Access denied' flash.
  test "customer admin cannot access admin organizations" do
    customer_admin = accounts(:customer_admin)
    login_as(customer_admin)

    get admin_organizations_path, headers: inertia_headers
    assert_response :redirect
    assert_redirected_to root_path
    assert_equal "Access denied", flash[:alert]
  end

  # WHY: Test that regular customer users cannot access admin pages.
  # Regular users should have the most restricted access level.
  # Admin::BaseController.require_amplifa_admin! redirects with 'Access denied' flash.
  test "customer user cannot access admin organizations" do
    customer_user = accounts(:customer_user)
    login_as(customer_user)

    get admin_organizations_path, headers: inertia_headers
    assert_response :redirect
    assert_redirected_to root_path
    assert_equal "Access denied", flash[:alert]
  end

  # WHY: Test that unauthenticated users are redirected to login.
  # This is handled by ApplicationController's authenticate method, but we should
  # ensure the chain works correctly with Admin::BaseController.
  test "unauthenticated user is redirected to login for admin pages" do
    get admin_organizations_path
    assert_response :redirect
  end

  # WHY: Test that the admin authorization check is null-safe.
  # When current_account is nil (should be prevented by authentication),
  # the code should not raise a NoMethodError.
  test "admin authorization handles nil current_account gracefully" do
    get admin_organizations_path
    assert_response :redirect
  end
end
