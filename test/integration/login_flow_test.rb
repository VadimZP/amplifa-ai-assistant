# frozen_string_literal: true

require 'test_helper'

# Safety-net coverage for the login surface: every seeded-fixture role can
# authenticate and lands on the expected page, and bad credentials are rejected.
# 2FA is disabled for these fixtures, so no email challenge is triggered.
class LoginFlowTest < ActionDispatch::IntegrationTest
  test 'customer_admin can log in and reaches the customer dashboard' do
    post login_path, params: { email: accounts(:customer_admin).email, password: 'password' }

    assert_redirected_to dashboard_path
    assert_nil session[:email_two_factor_challenge_id]
  end

  test 'customer_user can log in and reaches the customer dashboard' do
    post login_path, params: { email: accounts(:customer_user).email, password: 'password' }

    assert_redirected_to dashboard_path
    assert_nil session[:email_two_factor_challenge_id]
  end

  test 'amplifa_admin can log in and reaches the admin dashboard' do
    post login_path, params: { email: accounts(:amplifa_admin).email, password: 'password123' }

    assert_redirected_to admin_dashboard_path
    assert_nil session[:email_two_factor_challenge_id]
  end

  test 'unknown email is rejected and does not authenticate' do
    post login_path, params: { email: 'nobody@example.com', password: 'wrong' }

    refute_equal dashboard_path, response.location
    get dashboard_path
    assert_redirected_to login_path
  end

  test 'wrong password for a real account is rejected and does not authenticate' do
    post login_path, params: { email: accounts(:customer_admin).email, password: 'definitely-wrong' }

    refute_equal dashboard_path, response.location
    get dashboard_path
    assert_redirected_to login_path
  end
end
