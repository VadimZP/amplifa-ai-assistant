require 'test_helper'

class LocaleControllerTest < ActionDispatch::IntegrationTest
  # WHY: These tests verify that users can successfully change their language preference
  # and that the system properly validates locale choices and updates organization locale
  # for customer admins when appropriate

  def login_as(account)
    # WHY: Helper to authenticate users before making locale change requests
    password = account.amplifa_admin? ? 'password123' : 'password'
    post login_path, params: { email: account.email, password: password }
    assert_response :redirect
    follow_redirect!
  end

  setup do
    @customer_admin = accounts(:customer_admin)  # customer_admin role
    @customer_user = accounts(:customer_user)    # customer_user role
    @organization = @customer_admin.organization
  end

  test 'customer admin can update their locale to German' do
    # WHY: Customer admins should be able to change their language preference
    login_as @customer_admin

    post locale_path, params: { locale: 'de' }, as: :json

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal true, json['success']
    assert_equal 'de', json['locale']

    @customer_admin.reload
    assert_equal 'de', @customer_admin.locale
  end

  test 'customer admin can update their locale to Portuguese (Brazil)' do
    login_as @customer_admin

    post locale_path, params: { locale: 'pt-BR' }, as: :json

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal true, json['success']
    assert_equal 'pt-BR', json['locale']

    @customer_admin.reload
    assert_equal 'pt-BR', @customer_admin.locale
  end

  test 'customer admin can update their locale to English' do
    # WHY: Users should be able to switch back to English
    @customer_admin.update!(locale: 'de')
    login_as @customer_admin

    post locale_path, params: { locale: 'en' }, as: :json

    assert_response :success
    @customer_admin.reload
    assert_equal 'en', @customer_admin.locale
  end

  test 'customer user can update their locale' do
    # WHY: Regular users should also be able to change their language preference
    login_as @customer_user

    post locale_path, params: { locale: 'de' }, as: :json

    assert_response :success
    @customer_user.reload
    assert_equal 'de', @customer_user.locale
  end

  test 'customer admin updates organization locale when org locale is default' do
    # WHY: When a customer admin changes language and the org is still using the default,
    # we should update the org locale too so it becomes the new default for the organization
    @organization.update!(locale: 'en')
    login_as @customer_admin

    post locale_path, params: { locale: 'de' }, as: :json

    assert_response :success
    @organization.reload
    assert_equal 'de', @organization.locale
  end

  test 'customer admin does not update organization locale when org locale is already customized' do
    # WHY: If the organization has already chosen German, and admin switches to English,
    # we shouldn't override the org preference
    @organization.update!(locale: 'de')
    login_as @customer_admin

    post locale_path, params: { locale: 'en' }, as: :json

    assert_response :success
    @organization.reload
    assert_equal 'de', @organization.locale # Org stays German
  end

  test 'customer user cannot update organization locale' do
    # WHY: Regular users shouldn't be able to change organization-wide settings
    @organization.update!(locale: 'en')
    login_as @customer_user

    post locale_path, params: { locale: 'de' }, as: :json

    assert_response :success
    @customer_user.reload
    assert_equal 'de', @customer_user.locale

    @organization.reload
    assert_equal 'en', @organization.locale # Org unchanged
  end

  test 'rejects invalid locale' do
    # WHY: We should only accept supported locales to prevent errors
    login_as @customer_admin

    post locale_path, params: { locale: 'xx' }, as: :json

    assert_response :unprocessable_entity
    json = JSON.parse(response.body)
    assert_equal 'Invalid locale', json['error']
  end

  test 'rejects empty locale' do
    # WHY: Locale parameter is required
    login_as @customer_admin

    post locale_path, params: { locale: '' }, as: :json

    assert_response :unprocessable_entity
  end

  test 'unauthenticated user can set locale via session' do
    post locale_path, params: { locale: 'de' }, as: :json

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal 'de', json['locale']
  end

  test 'amplifa admin can update their locale' do
    # WHY: Admin users should also be able to set language preferences
    admin = accounts(:amplifa_admin)
    login_as admin

    post locale_path, params: { locale: 'de' }, as: :json

    assert_response :success
    admin.reload
    assert_equal 'de', admin.locale
  end

  test 'amplifa admin updating locale does not affect any organization' do
    # WHY: Amplifa admins don't belong to an organization, so shouldn't update one
    admin = accounts(:amplifa_admin)
    login_as admin

    original_locales = Organization.pluck(:id, :locale).to_h

    post locale_path, params: { locale: 'de' }, as: :json

    assert_response :success

    # Verify no organization locales changed
    Organization.find_each do |org|
      assert_equal original_locales[org.id], org.locale
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # AMP-435 §8: org-locale update must be gated by the CURRENT-WORKSPACE
  # membership role, not the legacy global account.role.
  #
  # Failing-first (before the locale_controller fix): the account has a
  # GLOBAL customer_admin role, so current_account.customer_admin? is true in
  # EVERY workspace. Updating locale while switched into org_b (where the
  # membership is customer_user) leaks the org-locale write into org_b.
  # ──────────────────────────────────────────────────────────────────────────
  test 'org locale update is gated by current-workspace membership role' do
    scenario = build_multi_org_scenario
    scenario.org_a.update!(onboarded: true, locale: 'en')
    scenario.org_b.update!(onboarded: true, locale: 'en')

    login_as scenario.account

    # In workspace B the current membership is customer_user -> org-locale write must be BLOCKED.
    post workspace_switch_path, params: { organization_id: scenario.org_b.id }
    post locale_path, params: { locale: 'de' }, as: :json
    assert_response :success

    assert_equal 'en', scenario.org_b.reload.locale,
                 'customer_user in the current workspace must NOT update the org locale (leak)'

    # In workspace A the current membership is customer_admin -> org-locale write is ALLOWED.
    post workspace_switch_path, params: { organization_id: scenario.org_a.id }
    post locale_path, params: { locale: 'de' }, as: :json
    assert_response :success

    assert_equal 'de', scenario.org_a.reload.locale,
                 'customer_admin in the current workspace must update the org locale'
  end
end
