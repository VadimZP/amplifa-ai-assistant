require 'test_helper'

class NoWorkspacesControllerTest < ActionDispatch::IntegrationTest
  test 'customer with no active memberships is sent to no-workspace page after login' do
    account = Account.new(
      email: 'nomembership@example.com',
      first_name: 'No',
      last_name: 'Membership',
      role: 'customer_user',
      status: :verified,
      password_hash: RodauthApp.rodauth.allocate.password_hash('password')
    )
    account.save!(validate: false)

    assert_empty account.active_organization_memberships

    post login_path, params: { email: account.email, password: 'password' }

    assert_redirected_to no_workspace_path
    get no_workspace_path, headers: inertia_headers
    assert_inertia_component 'Customer/NoWorkspace'
  end

  test 'AMP-435 §1: a customer whose every membership is inactive, deactivated, or archived resolves no workspace' do
    scenario = build_multi_org_scenario

    scenario.membership_a.update!(status: 'inactive', deactivated_at: Time.current)
    scenario.membership_b.update!(status: 'inactive', deactivated_at: Time.current)

    assert_empty scenario.account.switchable_organization_memberships,
                 'setup precondition: no switchable membership remains'

    login_as scenario.account

    get dashboard_path, headers: inertia_headers
    assert_redirected_to no_workspace_path
    assert_nil session[:current_organization_id], 'resolution must delete the unresolvable session org key'

    get no_workspace_path, headers: inertia_headers
    assert_inertia_component 'Customer/NoWorkspace'
  end
end
