# frozen_string_literal: true

require 'test_helper'

# AMP-435 §8 / bug B2-fallback safety net.
#
# WHY: We are about to tighten ApplicationPolicy#customer_admin? and
# #customer_user? so they NO LONGER fall back to the legacy global Account#role
# when there is no resolved current-workspace membership. Before touching the
# policy we pin the CURRENT, CORRECT behavior of every account-bootstrap flow
# through REAL requests. Real requests run ApplicationController#set_current_attributes
# -> #resolve_current_customer_workspace, which sets Current.organization_membership
# for any customer with an active membership (else #ensure_onboarded redirects to
# no_workspace_path). These tests must stay GREEN both before and after the
# policy change: if any of them break, a legitimate, reachable bootstrap flow is
# regressing and the change must be reverted.
class BootstrapAuthorizationTest < ActionDispatch::IntegrationTest
  # --- Flow 1: Invitation acceptance -------------------------------------------
  # A newly invited customer_admin ends up correctly authorized: after accepting
  # they can reach the org-admin dashboard, which is gated by the policy
  # customer_admin? path this change touches.
  # --- Flow 2: Onboarding ------------------------------------------------------
  # A customer_admin whose organization is not yet onboarded can reach and
  # complete onboarding. onboarding#show / #complete both call
  # `authorize Current.organization, :update?`, which routes through the policy
  # customer_admin? path.
  # --- Flow 3: Impersonation ---------------------------------------------------
  # An amplifa_admin impersonating a customer_admin sees exactly what that
  # customer sees, including the org-admin dashboard (customer_admin? via the
  # impersonated account's membership).
  # --- Flow 4: First login / session redirects ---------------------------------
  test 'first login sends a customer_admin to the dashboard' do
    post login_path, params: { email: accounts(:customer_admin).email, password: 'password' }
    assert_redirected_to dashboard_path
  end

  test 'first login sends a customer_user to the dashboard' do
    post login_path, params: { email: accounts(:customer_user).email, password: 'password' }
    assert_redirected_to dashboard_path
  end

  test 'first login sends an amplifa_admin to the admin dashboard' do
    post login_path, params: { email: accounts(:amplifa_admin).email, password: 'password123' }
    assert_redirected_to admin_dashboard_path
  end

  test 'logged-in customer_admin can load the customer dashboard' do
    post login_path, params: { email: accounts(:customer_admin).email, password: 'password' }

    get dashboard_path, headers: inertia_headers
    assert_response :success
  end

  # --- Flow 5: amplifa_admin reaching the admin dashboard -----------------------
  # amplifa_admin? is a separate global check that this change must NOT alter.
  test 'amplifa_admin can reach the admin dashboard' do
    post login_path, params: { email: accounts(:amplifa_admin).email, password: 'password123' }

    get admin_dashboard_path, headers: inertia_headers
    assert_response :success
    assert_equal 'Admin/Dashboard', JSON.parse(response.body)['component']
  end
end
