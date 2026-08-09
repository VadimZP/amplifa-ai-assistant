require 'test_helper'

class SettingsCompanyTest < ActionDispatch::IntegrationTest
  # WHY: Helper method to log in users before testing settings
  # since company settings require authentication
  def login_as(account)
    password = account.amplifa_admin? ? 'password123' : 'password'

    post login_path, params: {
      email: account.email,
      password: password
    }
    assert_response :redirect
    follow_redirect!
  end

  # WHY: Helper to create Inertia headers for testing Inertia.js responses
  # which use JSON format with component and props structure
  def inertia_headers
    {
      'HTTP_X_INERTIA' => 'true',
      'HTTP_X_INERTIA_VERSION' => ViteRuby.digest,
      'HTTP_ACCEPT' => 'text/html, application/xhtml+xml',
      'HTTP_X_REQUESTED_WITH' => 'XMLHttpRequest'
    }
  end

  test 'customer admin can access company settings page' do
    # WHY: Customer admins need to be able to view their company settings
    # to complete onboarding and manage their organization profile
    customer_admin = accounts(:customer_admin)
    login_as(customer_admin)

    get edit_settings_company_path, headers: inertia_headers
    assert_response :success

    # WHY: Response should contain organization data and edit permissions
    body = JSON.parse(response.body)
    assert_equal 'Customer/Settings/Company', body['component']
    assert_not_nil body['props']['organization']
    assert body['props']['canEdit'], 'Customer admin should have edit permissions'
  end

  test 'customer user can view but not edit company settings' do
    # WHY: Customer users should be able to see their company settings
    # for transparency, but should not be able to edit them (read-only view)
    customer_user = accounts(:customer_user)
    login_as(customer_user)

    get edit_settings_company_path, headers: inertia_headers
    assert_response :success

    # WHY: Response should show canEdit as false for customer users
    body = JSON.parse(response.body)
    assert_equal 'Customer/Settings/Company', body['component']
    assert_equal false, body['props']['canEdit'], 'Customer user should not have edit permissions'
  end

  test 'customer admin can update company settings with valid data' do
    # WHY: Customer admins must be able to update their company profile
    # to complete the onboarding checklist and configure their organization
    customer_admin = accounts(:customer_admin)
    login_as(customer_admin)

    organization = customer_admin.organization

    # WHY: Test updating multiple fields at once to ensure the controller
    # properly handles all company profile attributes
    patch settings_company_path, params: {
      organization: {
        website: 'https://www.updated-company.com',
        average_contract_value: 25_000.00,
        calendly_url: 'https://calendly.com/updated-company/meeting'
      }
    }

    # WHY: Should redirect back to settings page after successful update
    assert_response :redirect
    assert_redirected_to edit_settings_company_path

    # WHY: Verify all fields were actually updated in the database
    organization.reload
    assert_equal 'https://www.updated-company.com', organization.website
    assert_equal 25_000.00, organization.average_contract_value.to_f
    assert_equal 'https://calendly.com/updated-company/meeting', organization.calendly_url
  end

  test 'customer user cannot update company settings' do
    # WHY: Customer users should not be able to modify company settings
    # even if they attempt to POST to the update endpoint directly
    # This ensures proper authorization is enforced at the controller level
    customer_user = accounts(:customer_user)
    login_as(customer_user)

    organization = customer_user.organization
    original_website = organization.website

    # WHY: Attempt to update should be rejected with redirect and flash alert
    # (ApplicationController rescues Pundit::NotAuthorizedError and redirects)
    patch settings_company_path, params: {
      organization: {
        website: 'https://www.should-not-update.com'
      }
    }

    # WHY: Should redirect with authorization error message
    assert_response :redirect
    assert_match(/not authorized/, flash[:alert])

    # WHY: Verify data was NOT changed in database
    organization.reload
    assert_equal original_website, organization.website
  end

  test 'update with invalid data shows validation errors' do
    # WHY: The controller must return validation errors to the user
    # when they submit invalid data, so they can correct it
    customer_admin = accounts(:customer_admin)
    login_as(customer_admin)

    # WHY: Submit invalid Calendly URL (must start with https://calendly.com/)
    patch settings_company_path, params: {
      organization: {
        calendly_url: 'https://wrongsite.com/meeting'
      }
    }, headers: inertia_headers

    # WHY: Should re-render the form with errors rather than redirecting
    assert_response :success
    body = JSON.parse(response.body)
    assert body['props']['errors'], 'Should include validation errors'
    assert body['props']['errors']['calendly_url'], 'Should have calendly_url error'
  end

  test 'update with negative financial values shows validation errors' do
    # WHY: Financial fields must be validated to ensure only positive values
    # are accepted (negative ACV or meeting price doesn't make business sense)
    customer_admin = accounts(:customer_admin)
    login_as(customer_admin)

    patch settings_company_path, params: {
      organization: {
        average_contract_value: -5000.00
      }
    }, headers: inertia_headers

    # WHY: Should reject negative values with validation error
    assert_response :success
    body = JSON.parse(response.body)
    assert body['props']['errors'], 'Should include validation errors'
    assert body['props']['errors']['average_contract_value'], 'Should have ACV error for negative value'
  end

  test 'completing profile fields marks onboarding step as complete' do
    # WHY: When a customer admin completes their profile by filling in required fields
    # (website, ACV, Calendly URL), the onboarding checklist should automatically
    # update to show the profile_completed step as done. This test verifies the
    # onboarding logic is working correctly.
    customer_admin = accounts(:customer_admin)
    login_as(customer_admin)

    organization = customer_admin.organization

    # WHY: Start with incomplete profile (missing required onboarding fields)
    organization.update!(website: nil, average_contract_value: nil, calendly_url: nil)
    refute organization.onboarding_steps_completed.include?(:profile_completed),
           'Profile should not be complete initially'

    # WHY: Submit all required fields for onboarding
    patch settings_company_path, params: {
      organization: {
        website: 'https://www.newcompany.com',
        average_contract_value: 15_000.00,
        calendly_url: 'https://calendly.com/newcompany/demo'
      }
    }

    # WHY: Verify the onboarding step is now marked as completed
    organization.reload
    assert organization.onboarding_steps_completed.include?(:profile_completed),
           'Profile should be complete after adding required fields'
  end

  test 'amplifa admin cannot access customer settings route' do
    # WHY: Amplifa admins should use the admin panel to edit organizations
    # not the customer-facing settings pages. This test ensures proper
    # route access control and prevents admins from accidentally using
    # the wrong interface.
    admin = accounts(:amplifa_admin)
    login_as(admin)

    # WHY: Should be redirected away from customer settings
    get edit_settings_company_path
    assert_response :redirect
    # WHY: Could redirect to admin dashboard or show error
  end

  test 'unauthenticated user cannot access settings' do
    # WHY: Company settings contain sensitive business data and must
    # require authentication. This test ensures the authentication
    # requirement is properly enforced.
    get edit_settings_company_path

    # WHY: Should redirect to login page
    assert_response :redirect
    # WHY: Rodauth will redirect to login when user is not authenticated
  end

  test 'monthly_subscription field is not updated by customers' do
    # WHY: Per the spec, monthly_subscription should be admin-only (read-only for customers)
    # This test ensures customers cannot modify their subscription amount
    # even if they attempt to submit it
    customer_admin = accounts(:customer_admin)
    login_as(customer_admin)

    organization = customer_admin.organization
    organization.update!(monthly_subscription: 499.00)
    original_subscription = organization.monthly_subscription

    # WHY: Attempt to update subscription via customer settings
    patch settings_company_path, params: {
      organization: {
        monthly_subscription: 999.00,
        website: 'https://www.test.com'
      }
    }

    # WHY: Subscription should not change (not in permitted params)
    organization.reload
    assert_equal original_subscription.to_f, organization.monthly_subscription.to_f,
                 'Monthly subscription should not be updatable by customers'
    # WHY: But website should update (proving the request went through)
    assert_equal 'https://www.test.com', organization.website
  end
end
