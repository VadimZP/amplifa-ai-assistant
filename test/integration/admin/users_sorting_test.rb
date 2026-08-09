require 'test_helper'

class Admin::UsersSortingTest < ActionDispatch::IntegrationTest
  def login_as(account)
    password = account.amplifa_admin? ? 'password123' : 'password'

    post login_path, params: {
      email: account.email,
      password: password
    }
    assert_response :redirect
    follow_redirect!
  end

  test 'users index sorts by name and returns sort params' do
    admin = accounts(:amplifa_admin)
    login_as(admin)

    get admin_users_path, params: { sort: 'name', direction: 'asc' }, headers: inertia_headers
    assert_response :success

    props = JSON.parse(response.body)['props']
    returned_accounts = props['accounts']

    assert_equal 'name', props['sort']
    assert_equal 'asc', props['direction']

    names = returned_accounts.map { |account| [account['first_name'].to_s, account['last_name'].to_s, account['id']] }
    assert_equal names.sort, names
  end

  test 'users index sorts by email descending' do
    admin = accounts(:amplifa_admin)
    login_as(admin)

    get admin_users_path, params: { sort: 'email', direction: 'desc' }, headers: inertia_headers
    assert_response :success

    props = JSON.parse(response.body)['props']
    returned_accounts = props['accounts']

    assert_equal 'email', props['sort']
    assert_equal 'desc', props['direction']

    emails = returned_accounts.map { |account| account['email'] }
    assert_equal emails.sort.reverse, emails
  end

  test 'users index sorts by organization ascending with nil organizations last' do
    admin = accounts(:amplifa_admin)
    login_as(admin)

    get admin_users_path, params: { sort: 'organization', direction: 'asc' }, headers: inertia_headers
    assert_response :success

    props = JSON.parse(response.body)['props']
    returned_accounts = props['accounts']

    assert_equal 'organization', props['sort']
    assert_equal 'asc', props['direction']

    organization_names = returned_accounts.map { |account| account.dig('organization', 'name') }
    non_nil_organization_names = organization_names.compact

    assert_equal non_nil_organization_names.sort, non_nil_organization_names

    nil_start_index = organization_names.index(nil)
    assert organization_names[nil_start_index..].all?(&:nil?) if nil_start_index
  end

  test 'users index sorts by role ascending' do
    admin = accounts(:amplifa_admin)
    login_as(admin)

    get admin_users_path, params: { sort: 'role', direction: 'asc' }, headers: inertia_headers
    assert_response :success

    props = JSON.parse(response.body)['props']
    returned_accounts = props['accounts']

    assert_equal 'role', props['sort']
    assert_equal 'asc', props['direction']

    roles = returned_accounts.map { |account| account['role'] }
    assert_equal roles.sort, roles
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
