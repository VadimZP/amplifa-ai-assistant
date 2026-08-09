require 'test_helper'

class WorkspaceSwitchesControllerTest < ActionDispatch::IntegrationTest
  def setup
    @account = accounts(:customer_user)
    @primary_organization = organizations(:acme)
    @secondary_organization = organizations(:growth_lab)
    @unauthorized_organization = organizations(:techcorp)

    OrganizationMembership.find_or_create_by!(
      account: @account,
      organization: @secondary_organization
    ) do |membership|
      membership.role = 'customer_user'
      membership.status = 'active'
    end
  end

  test 'switches to an active membership organization' do
    login_as @account

    post workspace_switch_path,
         params: { organization_id: @secondary_organization.id },
         headers: { 'HTTP_REFERER' => dashboard_url }

    assert_redirected_to dashboard_url

    get dashboard_path, headers: inertia_headers

    assert_equal @secondary_organization.id, inertia_props.dig('auth', 'current_organization', 'id')
    assert_equal @secondary_organization.id, inertia_props.dig('organization', 'id')
  end

  test 'rejects switching to an organization without membership' do
    login_as @account

    post workspace_switch_path, params: { organization_id: @unauthorized_organization.id }

    assert_response :forbidden
  end

  test 'rejects switching to an inactive membership' do
    inactive_organization = organizations(:beta)
    OrganizationMembership.find_or_create_by!(account: @account, organization: inactive_organization) do |membership|
      membership.role = 'customer_user'
    end.update!(status: 'inactive', deactivated_at: Time.current)

    login_as @account

    post workspace_switch_path, params: { organization_id: inactive_organization.id }

    assert_response :forbidden
  end

  test 'shares switchable organizations through inertia auth props' do
    login_as @account

    get dashboard_path, headers: inertia_headers

    organizations = inertia_props.dig('auth', 'organizations')

    assert_equal @primary_organization.id, inertia_props.dig('auth', 'current_organization', 'id')
    assert_includes organizations.map { |organization| organization['id'] }, @primary_organization.id
    assert_includes organizations.map { |organization| organization['id'] }, @secondary_organization.id
  end

  test 'shares enough workspace context for multi-workspace sidebar label' do
    login_as @account

    get dashboard_path, headers: inertia_headers

    organizations = inertia_props.dig('auth', 'organizations')
    current_organization = inertia_props.dig('auth', 'current_organization')

    assert_operator organizations.length, :>, 1
    assert_equal @primary_organization.name, current_organization['name']
  end

  test 'AMP-435 §9/B7: archived org with active membership is absent from auth.organizations' do
    archived_organization = build_archived_membership_org

    login_as @account
    get dashboard_path, headers: inertia_headers

    organization_ids = inertia_props.dig('auth', 'organizations').map { |organization| organization['id'] }

    assert_not_includes organization_ids, archived_organization.id
    assert_includes organization_ids, @primary_organization.id
    assert_includes organization_ids, @secondary_organization.id
  end

  test 'AMP-435 §8: deactivated org with active membership is absent from auth.organizations' do
    deactivated_organization = build_deactivated_membership_org

    login_as @account
    get dashboard_path, headers: inertia_headers

    organization_ids = inertia_props.dig('auth', 'organizations').map { |organization| organization['id'] }

    assert_not_includes organization_ids, deactivated_organization.id
    assert_includes organization_ids, @primary_organization.id
    assert_includes organization_ids, @secondary_organization.id
  end

  test 'AMP-435 §9/B7: switching to an archived org is forbidden despite active membership' do
    archived_organization = build_archived_membership_org

    login_as @account
    post workspace_switch_path, params: { organization_id: archived_organization.id }

    assert_response :forbidden
  end

  test 'AMP-435 §9/B7: resolution falls back to an active workspace when the current org is archived' do
    login_as @account

    post workspace_switch_path,
         params: { organization_id: @secondary_organization.id },
         headers: { 'HTTP_REFERER' => dashboard_url }
    assert_redirected_to dashboard_url

    @secondary_organization.archive!

    get dashboard_path, headers: inertia_headers

    current_organization_id = inertia_props.dig('auth', 'current_organization', 'id')
    assert_not_equal @secondary_organization.id, current_organization_id
    assert_equal @primary_organization.id, current_organization_id
  end

  test 'AMP-435 §1: a stale session org is ignored and resolution falls back to the primary membership' do
    scenario = build_multi_org_scenario
    scenario.org_a.update!(onboarded: true)
    scenario.org_b.update!(onboarded: true)

    login_as scenario.account

    post workspace_switch_path,
         params: { organization_id: scenario.org_b.id },
         headers: { 'HTTP_REFERER' => dashboard_url }
    assert_equal scenario.org_b.id, session[:current_organization_id]

    scenario.membership_b.destroy!

    get dashboard_path, headers: inertia_headers
    assert_response :success

    resolved_id = inertia_props.dig('auth', 'current_organization', 'id')
    assert_equal scenario.org_a.id, resolved_id, 'stale session org must be ignored, primary membership resolved'
    assert_not_equal scenario.org_b.id, resolved_id
    assert_equal scenario.org_a.id, session[:current_organization_id]
  end

  test 'AMP-435 §1: a session pointing at an inactive membership is excluded and resolution falls back' do
    scenario = build_multi_org_scenario
    scenario.org_a.update!(onboarded: true)
    scenario.org_b.update!(onboarded: true)

    login_as scenario.account

    post workspace_switch_path,
         params: { organization_id: scenario.org_b.id },
         headers: { 'HTTP_REFERER' => dashboard_url }
    assert_equal scenario.org_b.id, session[:current_organization_id]

    scenario.membership_b.update!(status: 'inactive', deactivated_at: Time.current)

    get dashboard_path, headers: inertia_headers
    assert_response :success

    resolved_id = inertia_props.dig('auth', 'current_organization', 'id')
    assert_equal scenario.org_a.id, resolved_id, 'inactive membership must be excluded, primary membership resolved'
    assert_not_equal scenario.org_b.id, resolved_id
    assert_equal scenario.org_a.id, session[:current_organization_id]
  end

  test 'AMP-435 §1: a session pointing at a deactivated org membership is excluded and resolution falls back' do
    scenario = build_multi_org_scenario
    scenario.org_a.update!(onboarded: true)
    scenario.org_b.update!(onboarded: true)

    login_as scenario.account

    post workspace_switch_path,
         params: { organization_id: scenario.org_b.id },
         headers: { 'HTTP_REFERER' => dashboard_url }
    assert_equal scenario.org_b.id, session[:current_organization_id]

    scenario.org_b.deactivate!

    get dashboard_path, headers: inertia_headers
    assert_response :success

    resolved_id = inertia_props.dig('auth', 'current_organization', 'id')
    assert_equal scenario.org_a.id, resolved_id, 'deactivated-org membership excluded, primary resolved'
    assert_not_equal scenario.org_b.id, resolved_id
    assert_equal scenario.org_a.id, session[:current_organization_id]
  end

  test 'AMP-435 §1: a session at an archived org membership is excluded via the switchable scope and falls back' do
    scenario = build_multi_org_scenario
    scenario.org_a.update!(onboarded: true)
    scenario.org_b.update!(onboarded: true)

    login_as scenario.account

    post workspace_switch_path,
         params: { organization_id: scenario.org_b.id },
         headers: { 'HTTP_REFERER' => dashboard_url }
    assert_equal scenario.org_b.id, session[:current_organization_id]

    scenario.org_b.archive!

    get dashboard_path, headers: inertia_headers
    assert_response :success

    resolved_id = inertia_props.dig('auth', 'current_organization', 'id')
    assert_equal scenario.org_a.id, resolved_id, 'archived-org membership must be excluded, primary membership resolved'
    assert_not_equal scenario.org_b.id, resolved_id
    assert_equal scenario.org_a.id, session[:current_organization_id]
  end

  test 'AMP-435 §1: an inactive primary membership is skipped so resolution falls back to another active membership' do
    scenario = build_multi_org_scenario
    scenario.org_a.update!(onboarded: true)
    scenario.org_b.update!(onboarded: true)

    login_as scenario.account
    assert_equal scenario.org_a.id, session[:current_organization_id]

    scenario.membership_a.update!(status: 'inactive', deactivated_at: Time.current)

    get dashboard_path, headers: inertia_headers
    assert_response :success

    resolved_id = inertia_props.dig('auth', 'current_organization', 'id')
    assert_equal scenario.org_b.id, resolved_id, 'inactive primary must be skipped, other active membership resolved'
    assert_not_equal scenario.org_a.id, resolved_id
    assert_equal scenario.org_b.id, session[:current_organization_id]
  end

  private

  def build_archived_membership_org
    organization = Organization.create!(name: "Archived Co #{SecureRandom.hex(4)}", status: 'active')
    OrganizationMembership.create!(
      account: @account, organization: organization, role: 'customer_user', status: 'active'
    )
    organization.archive!
    organization
  end

  def build_deactivated_membership_org
    organization = Organization.create!(name: "Deactivated Co #{SecureRandom.hex(4)}", status: 'active')
    OrganizationMembership.create!(
      account: @account, organization: organization, role: 'customer_user', status: 'active'
    )
    organization.deactivate!
    organization
  end
end
