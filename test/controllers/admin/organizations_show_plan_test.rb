require 'test_helper'

class Admin::OrganizationsShowPlanTest < ActionDispatch::IntegrationTest
  setup do
    @admin = accounts(:amplifa_admin)
    @organization = organizations(:acme)
  end

  test 'show includes current plan data for sidebar card' do
    login_as(@admin)

    get admin_organization_path(@organization), headers: inertia_headers

    assert_response :success
    assert_inertia_component('Admin/Organizations/Show')

    organization_props = inertia_props['organization']

    assert_equal @organization.plan_tier, organization_props['plan_tier']
    assert_equal @organization.monthly_meeting_limit, organization_props['monthly_meeting_limit']
    assert organization_props.key?('monthly_subscription')
    assert organization_props.key?('billing_cycle_started_on')
    assert organization_props.key?('current_plan')

    current_plan = organization_props['current_plan']
    assert current_plan.is_a?(Hash)
    assert_equal @organization.plan_tier, current_plan['identifier']
    assert current_plan['name'].present?
    assert current_plan['monthly_meeting_limit'].is_a?(Integer)
  end
end
