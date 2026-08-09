# frozen_string_literal: true

require 'test_helper'

# Safety-net coverage that every kept customer/admin GET route renders instead
# of returning 404/500. Guards against dangling references to stripped features.
class RouteSmokeTest < ActionDispatch::IntegrationTest
  setup do
    login_as(accounts(:customer_admin))
  end

  test 'dashboard loads' do
    get dashboard_path, headers: inertia_headers
    assert_response :success
  end

  test 'inbox loads' do
    get replies_path, headers: inertia_headers
    assert_response :success
  end

  test 'playbooks loads' do
    get playbooks_path, headers: inertia_headers
    assert_response :success
  end

  test 'agents loads' do
    get customer_agents_path, headers: inertia_headers
    assert_response :success
  end

  test 'meetings loads' do
    get meetings_path, headers: inertia_headers
    assert_response :success
  end

  test 'roi loads' do
    get roi_path, headers: inertia_headers
    assert_response :success
  end

  test 'team loads' do
    get team_path, headers: inertia_headers
    assert_response :success
  end

  test 'settings billing loads' do
    get settings_billing_path, headers: inertia_headers
    assert_response :success
  end

  test 'admin dashboard loads for amplifa admin' do
    login_as(accounts(:amplifa_admin))
    get admin_dashboard_path, headers: inertia_headers
    assert_response :success
  end
end
