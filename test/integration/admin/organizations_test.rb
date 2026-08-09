require 'test_helper'

class Admin::OrganizationsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  # WHY: This helper is needed to log in users before testing admin functions
  # because organization management is only available to authenticated admins
  def login_as(account)
    # amplifa_admin uses password123, customers use password
    password = account.amplifa_admin? ? 'password123' : 'password'

    perform_enqueued_jobs do
      post login_path, params: {
        email: account.email,
        password: password
      }
    end
    if account.requires_email_two_factor_authentication?
      verification_url = ActionMailer::Base.deliveries.last.text_part.body.to_s.match(%r{https?://\S+})[0]
      get URI.parse(verification_url).request_uri
    end
    assert_response :redirect
    follow_redirect!
  end

  test 'amplifa admin can view organizations index' do
    # WHY: The organizations list is a core admin feature for managing customer companies.
    # Amplifa admins should be able to see all organizations.
    admin = accounts(:amplifa_admin)
    login_as(admin)

    get admin_organizations_path, headers: inertia_headers
    assert_response :success

    # WHY: Response should contain organizations data in Inertia props
    body = JSON.parse(response.body)
    assert_equal 'Admin/Organizations/Index', body['component']
    assert body['props']['organizations'].is_a?(Array)
  end

  test 'amplifa admin can view organization lead sequence summaries' do
    admin = accounts(:amplifa_admin)
    organization = organizations(:acme)
    login_as(admin)

    agent_leads(:john_in_draft).update!(delivery_status: 'in_sequence', sequence_position: 2)
    agent_leads(:jane_in_draft).update!(delivery_status: 'in_sequence', sequence_position: 1)

    get admin_organization_path(organization), headers: inertia_headers
    assert_response :success

    body = JSON.parse(response.body)
    agent = body.dig('props', 'agents').find { |summary| summary['id'] == agents(:draft_agent).id }

    assert_equal 2, agent['total_leads_count']
    assert_equal 0, agent['not_contacted_leads_count']
    assert_equal 1, agent['all_reached_sequence_step']
    assert_equal true, agent['all_leads_contacted']
  end

  test 'organization lead sequence summaries do not mark unadvanced paused leads as contacted' do
    admin = accounts(:amplifa_admin)
    organization = organizations(:acme)
    login_as(admin)

    agent_leads(:john_in_draft).update!(delivery_status: 'paused', sequence_position: 0)
    agent_leads(:jane_in_draft).update!(delivery_status: 'in_sequence', sequence_position: 1)

    get admin_organization_path(organization), headers: inertia_headers
    assert_response :success

    body = JSON.parse(response.body)
    agent = body.dig('props', 'agents').find { |summary| summary['id'] == agents(:draft_agent).id }

    assert_equal 2, agent['total_leads_count']
    assert_equal 1, agent['not_contacted_leads_count']
    assert_nil agent['all_reached_sequence_step']
    assert_equal false, agent['all_leads_contacted']
  end

  test 'amplifa admin can access new organization form' do
    # WHY: Admins need to be able to create new organizations to onboard new customers.
    # This is the missing functionality from Week 1 implementation.
    admin = accounts(:amplifa_admin)
    login_as(admin)

    get new_admin_organization_path, headers: inertia_headers
    assert_response :success

    # WHY: Form should include size options for the dropdown
    body = JSON.parse(response.body)
    assert_equal 'Admin/Organizations/New', body['component']
    assert body['props']['size_options'].is_a?(Array)
  end

  test 'amplifa admin can create organization with valid params' do
    # WHY: Organization creation is fundamental to the platform. Admins must be able to
    # create customer organizations to set up new clients. This test ensures proper validation
    # and that the organization is created with correct attributes.
    admin = accounts(:amplifa_admin)
    login_as(admin)

    assert_difference 'Organization.count', 1 do
      post admin_organizations_path, params: {
        organization: {
          name: 'New Test Company',
          industry: 'Technology',
          size: '11-50',
          onboarded: false,
          two_factor_authentication_required: true
        }
      }
    end

    # WHY: After successful creation, admin should be redirected to organizations index
    assert_redirected_to admin_organizations_path
    follow_redirect!
    assert_match(/Organization created successfully/, flash[:notice])

    # WHY: Verify the organization was created with correct attributes
    new_org = Organization.find_by(name: 'New Test Company')
    assert_not_nil new_org
    assert_equal 'Technology', new_org.industry
    assert_equal '11-50', new_org.size
    assert_equal false, new_org.onboarded
    assert_equal true, new_org.two_factor_authentication_required
    assert_equal 'onboarding', new_org.status
  end

  test 'amplifa admin can create organization with minimal required params' do
    # WHY: Organizations should be creatable with just a name, other fields optional.
    # This allows admins to quickly create an org and fill in details later.
    admin = accounts(:amplifa_admin)
    login_as(admin)

    assert_difference 'Organization.count', 1 do
      post admin_organizations_path, params: {
        organization: {
          name: 'Minimal Org'
        }
      }
    end

    assert_redirected_to admin_organizations_path
    new_org = Organization.find_by(name: 'Minimal Org')
    assert_not_nil new_org
    assert_equal 'onboarding', new_org.status
  end

  test 'organization creation fails with blank name' do
    # WHY: Organization names are required fields.
    # This test verifies validation is working properly.
    admin = accounts(:amplifa_admin)
    login_as(admin)

    assert_no_difference 'Organization.count' do
      post admin_organizations_path, params: {
        organization: {
          name: '' # Blank name should fail
        }
      }
    end

    # WHY: Validation error should re-render form (status 200)
    assert_response :success
  end

  test 'organization creation fails with name too long' do
    # WHY: Organization names have a maximum length of 100 characters.
    # This test verifies the validation is enforced.
    admin = accounts(:amplifa_admin)
    login_as(admin)

    assert_no_difference 'Organization.count' do
      post admin_organizations_path, params: {
        organization: {
          name: 'A' * 101 # Too long (maximum is 100 characters)
        }
      }
    end

    # WHY: Validation error should re-render form (status 200)
    assert_response :success
  end

  test 'customer users cannot access new organization page' do
    # WHY: Only amplifa admins should be able to create organizations.
    # Customer users and customer admins should not have this access.
    customer = accounts(:growth_lab_admin)
    login_as(customer)

    get new_admin_organization_path, headers: inertia_headers
    # WHY: Should be redirected away (access denied)
    assert_response :redirect
    follow_redirect!
    assert_match(/Access denied|not authorized/i, flash[:alert] || '')
  end

  test 'customer users cannot create organizations' do
    # WHY: Only amplifa admins should be able to create organizations.
    # This test ensures authorization is properly enforced.
    customer = accounts(:growth_lab_admin)
    login_as(customer)

    assert_no_difference 'Organization.count' do
      post admin_organizations_path, params: {
        organization: {
          name: 'Unauthorized Org'
        }
      }
    end

    # WHY: Should be redirected away (access denied)
    assert_response :redirect
  end

  test 'amplifa admin can edit existing organization' do
    # WHY: Admins need to update organization details as they evolve.
    admin = accounts(:amplifa_admin)
    login_as(admin)

    org = organizations(:acme)
    get edit_admin_organization_path(org), headers: inertia_headers
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal 'Admin/Organizations/Edit', body['component']
    assert_equal org.name, body['props']['organization']['name']
  end

  test 'amplifa admin can update organization' do
    # WHY: Organization details should be updatable (industry, size, onboarding status).
    admin = accounts(:amplifa_admin)
    login_as(admin)

    org = organizations(:acme)
    patch admin_organization_path(org), params: {
      organization: {
        industry: 'Healthcare',
        size: '201-1000',
        onboarded: true,
        two_factor_authentication_required: true
      }
    }

    assert_redirected_to admin_organization_path(org)
    org.reload
    assert_equal 'Healthcare', org.industry
    assert_equal '201-1000', org.size
    assert_equal true, org.onboarded
    assert_equal true, org.two_factor_authentication_required
  end

  test 'amplifa admin can deactivate organization' do
    # WHY: Organizations that churn should be deactivatable (soft delete).
    admin = accounts(:amplifa_admin)
    login_as(admin)

    org = organizations(:acme)
    delete admin_organization_path(org)

    assert_redirected_to admin_organizations_path
    org.reload
    assert_not_nil org.deactivated_at
    assert_equal false, org.active?
  end

  test 'amplifa admin can archive a deactivated organization' do
    admin = accounts(:amplifa_admin)
    login_as(admin)

    org = organizations(:acme)
    org.deactivate!

    post archive_admin_organization_path(org)

    assert_redirected_to admin_organizations_path
    follow_redirect!
    assert_match(/Organization archived successfully/, flash[:notice] || '')

    org.reload
    assert_not_nil org.archived_at
  end

  test 'amplifa admin cannot archive an active organization' do
    admin = accounts(:amplifa_admin)
    login_as(admin)

    org = organizations(:growth_lab)

    post archive_admin_organization_path(org)

    assert_redirected_to admin_organization_path(org)
    follow_redirect!
    assert_match(/Only deactivated organizations can be archived/, flash[:alert] || '')

    org.reload
    assert_nil org.archived_at
  end

  test 'archived organizations are hidden from organizations index' do
    admin = accounts(:amplifa_admin)
    login_as(admin)

    org = organizations(:acme)
    org.deactivate!
    org.archive!

    get admin_organizations_path, headers: inertia_headers
    assert_response :success

    body = JSON.parse(response.body)
    organization_ids = body['props']['organizations'].map { |entry| entry['id'] }

    assert_not_includes organization_ids, org.id
  end

  test 'deactivated organizations are hidden from organizations index' do
    admin = accounts(:amplifa_admin)
    login_as(admin)

    org = organizations(:acme)
    org.deactivate!

    get admin_organizations_path, headers: inertia_headers
    assert_response :success

    body = JSON.parse(response.body)
    organization_ids = body['props']['organizations'].map { |entry| entry['id'] }

    assert_not_includes organization_ids, org.id
  end

  test 'archived filter shows archived organizations only' do
    admin = accounts(:amplifa_admin)
    login_as(admin)

    archived_org = organizations(:acme)
    archived_org.deactivate!
    archived_org.archive!

    visible_org = organizations(:growth_lab)

    get admin_organizations_path(status: 'archived'), headers: inertia_headers
    assert_response :success

    body = JSON.parse(response.body)
    organization_ids = body['props']['organizations'].map { |entry| entry['id'] }

    assert_includes organization_ids, archived_org.id
    assert_not_includes organization_ids, visible_org.id
    assert_equal 'archived', body['props']['filters']['status']
  end

  test 'deactivated filter shows only deactivated non-archived organizations' do
    admin = accounts(:amplifa_admin)
    login_as(admin)

    deactivated_org = organizations(:growth_lab)
    deactivated_org.deactivate!

    archived_org = organizations(:acme)
    archived_org.deactivate!
    archived_org.archive!

    active_org = organizations(:techcorp)

    get admin_organizations_path(status: 'deactivated'), headers: inertia_headers
    assert_response :success

    body = JSON.parse(response.body)
    organization_ids = body['props']['organizations'].map { |entry| entry['id'] }

    assert_includes organization_ids, deactivated_org.id
    assert_not_includes organization_ids, archived_org.id
    assert_not_includes organization_ids, active_org.id
    assert_equal 'deactivated', body['props']['filters']['status']
  end

  test 'amplifa admin can update organization with Week 2 fields' do
    # WHY: Week 2 added financial fields (ACV, meeting price, subscription),
    # integration fields (website, Calendly), and i18n fields (locale, currency).
    # The admin edit form should allow updating ALL of these fields.
    # This test verifies that all Week 2 fields can be updated through the admin interface.
    admin = accounts(:amplifa_admin)
    login_as(admin)

    org = organizations(:acme)
    patch admin_organization_path(org), params: {
      organization: {
        website: 'https://www.updated-acme.com',
        average_contract_value: 25_000.50,
        meeting_price: 1500.00,
        monthly_subscription: 299.99,
        monthly_meeting_limit: 15,
        plan_tier: 'growth',
        billing_cycle_started_on: '2026-02-17',
        calendly_url: 'https://calendly.com/updated-acme/demo',
        locale: 'de',
        currency: 'USD'
      }
    }

    assert_redirected_to admin_organization_path(org)
    follow_redirect!
    assert_match(/Organization updated successfully/, flash[:notice])

    # WHY: Verify all Week 2 fields were updated correctly
    org.reload
    assert_equal 'https://www.updated-acme.com', org.website
    assert_equal 25_000.50, org.average_contract_value.to_f
    assert_equal 1500.00, org.meeting_price.to_f
    assert_equal 299.99, org.monthly_subscription.to_f
    assert_equal 15, org.monthly_meeting_limit
    assert_equal 'growth', org.plan_tier
    assert_equal Date.new(2026, 2, 17), org.billing_cycle_started_on
    assert_equal 'https://calendly.com/updated-acme/demo', org.calendly_url
    assert_equal 'de', org.locale
    assert_equal 'USD', org.currency
  end

  test 'edit form includes Week 2 fields in props' do
    # WHY: The edit form must serialize ALL organization fields to the frontend,
    # including the Week 2 fields (website, financial fields, locale, currency).
    # This test ensures the controller sends complete data to the Inertia component.
    admin = accounts(:amplifa_admin)
    login_as(admin)

    org = organizations(:acme)
    get edit_admin_organization_path(org), headers: inertia_headers
    assert_response :success

    body = JSON.parse(response.body)
    props = body['props']['organization']

    # WHY: Verify all Week 2 fields are present in the props
    assert props.key?('website'), 'Missing website field'
    assert props.key?('average_contract_value'), 'Missing average_contract_value field'
    assert props.key?('meeting_price'), 'Missing meeting_price field'
    assert props.key?('monthly_subscription'), 'Missing monthly_subscription field'
    assert props.key?('monthly_meeting_limit'), 'Missing monthly_meeting_limit field'
    assert props.key?('plan_tier'), 'Missing plan_tier field'
    assert props.key?('billing_cycle_started_on'), 'Missing billing_cycle_started_on field'
    assert props.key?('calendly_url'), 'Missing calendly_url field'
    assert props.key?('locale'), 'Missing locale field'
    assert props.key?('currency'), 'Missing currency field'
    assert body['props']['plan_options'].is_a?(Array), 'Missing plan_options'
  end

  test 'organization update validates Calendly URL format' do
    # WHY: Calendly URLs must start with https://calendly.com/ to be valid.
    # This test ensures the validation is enforced when updating organizations.
    admin = accounts(:amplifa_admin)
    login_as(admin)

    org = organizations(:acme)
    patch admin_organization_path(org), params: {
      organization: {
        calendly_url: 'https://invalid-url.com/meeting'
      }
    }

    # WHY: Invalid Calendly URL should cause redirect with error
    assert_redirected_to edit_admin_organization_path(org)
    follow_redirect!
    assert_match(/calendly/i, flash[:alert] || '')
  end

  test 'organization update validates financial fields are positive' do
    # WHY: Financial fields (ACV, meeting price, subscription) must be >= 0.
    # Negative values don't make business sense and should be rejected.
    admin = accounts(:amplifa_admin)
    login_as(admin)

    org = organizations(:acme)
    patch admin_organization_path(org), params: {
      organization: {
        average_contract_value: -1000
      }
    }

    # WHY: Negative financial value should cause redirect with error
    assert_redirected_to edit_admin_organization_path(org)
    follow_redirect!
    assert_match(/greater than or equal to 0/, flash[:alert] || '')
  end

  test 'organization update validates locale is valid' do
    # Invalid locales should be rejected to prevent UI issues.
    admin = accounts(:amplifa_admin)
    login_as(admin)

    org = organizations(:acme)
    patch admin_organization_path(org), params: {
      organization: {
        locale: 'invalid_locale'
      }
    }

    # WHY: Invalid locale should cause redirect with error
    assert_redirected_to edit_admin_organization_path(org)
    follow_redirect!
    assert_match(/locale|not included/i, flash[:alert] || '')
  end

  test 'organization update validates currency is valid' do
    # WHY: Only EUR, USD, GBP, CHF currencies are currently supported.
    # Invalid currencies should be rejected.
    admin = accounts(:amplifa_admin)
    login_as(admin)

    org = organizations(:acme)
    patch admin_organization_path(org), params: {
      organization: {
        currency: 'INVALID'
      }
    }

    # WHY: Invalid currency should cause redirect with error
    assert_redirected_to edit_admin_organization_path(org)
    follow_redirect!
    assert_match(/currency|not included/i, flash[:alert] || '')
  end

  # WHY: Test product discovery workflow - scrapes website and uses AI to identify products
  # WHY: Test that discover_products caches scraped data for reuse during playbook generation
  # WHY: Test that clear_website_cache clears cached data and logs activity
  # WHY: Test that edit page shows website cache info when cache exists
  # WHY: Test that edit page shows null cache when no cache exists
  # WHY: Test that new organization form has all fields that edit form has
  # This ensures admins can set all organization properties during creation, not just name/industry/size
  test 'new organization form includes all organization fields' do
    admin = accounts(:amplifa_admin)
    login_as(admin)

    get new_admin_organization_path, headers: inertia_headers
    assert_response :success

    body = JSON.parse(response.body)
    props = body['props']

    # WHY: Form should include size, locale, and currency dropdowns like edit form
    assert props['size_options'].is_a?(Array), 'Missing size_options'
    assert props['locale_options'].is_a?(Array), 'Missing locale_options'
    assert props['currency_options'].is_a?(Array), 'Missing currency_options'

    # WHY: Verify expected options match edit form
    assert_includes props['size_options'], '1-10'
    assert_includes props['locale_options'], 'en'
    assert_includes props['locale_options'], 'de'
    assert_includes props['locale_options'], 'es'
    assert_includes props['locale_options'], 'pt-BR'
    assert_includes props['locale_options'], 'fr'
    assert_includes props['locale_options'], 'pl'
    assert_includes props['locale_options'], 'cs'
    assert_includes props['locale_options'], 'it'
    assert_includes props['currency_options'], 'EUR'
    assert_includes props['currency_options'], 'USD'
  end

  # WHY: Test that organization can be created with all Week 2 fields
  test 'amplifa admin can create organization with all fields including Week 2 fields' do
    admin = accounts(:amplifa_admin)
    login_as(admin)

    assert_difference 'Organization.count', 1 do
      post admin_organizations_path, params: {
        organization: {
          name: 'Full Test Company',
          industry: 'Technology',
          size: '51-200',
          onboarded: true,
          website: 'https://www.fulltest.com',
          average_contract_value: 15_000.00,
          meeting_price: 750.00,
          monthly_subscription: 399.99,
          calendly_url: 'https://calendly.com/fulltest/meeting',
          locale: 'de',
          currency: 'CHF'
        }
      }
    end

    assert_redirected_to admin_organizations_path
    follow_redirect!

    # WHY: Verify all fields were saved correctly
    new_org = Organization.find_by(name: 'Full Test Company')
    assert_not_nil new_org
    assert_equal 'Technology', new_org.industry
    assert_equal '51-200', new_org.size
    assert_equal true, new_org.onboarded
    assert_equal 'https://www.fulltest.com', new_org.website
    assert_equal 15_000.00, new_org.average_contract_value.to_f
    assert_equal 750.00, new_org.meeting_price.to_f
    assert_equal 399.99, new_org.monthly_subscription.to_f
    assert_equal 'https://calendly.com/fulltest/meeting', new_org.calendly_url
    assert_equal 'de', new_org.locale
    assert_equal 'CHF', new_org.currency
  end

  # WHY: Test that validation errors preserve all entered values when re-rendering form
  test 'organization creation failure preserves all entered values' do
    admin = accounts(:amplifa_admin)
    login_as(admin)

    # Post with invalid name (blank) but all other fields filled
    post admin_organizations_path, params: {
      organization: {
        name: '', # Invalid: blank name
        industry: 'Technology',
        size: '11-50',
        website: 'https://www.test.com',
        average_contract_value: 10_000,
        meeting_price: 500,
        calendly_url: 'https://calendly.com/test/meeting',
        locale: 'de',
        currency: 'USD'
      }
    }, headers: inertia_headers

    assert_response :success
    body = JSON.parse(response.body)
    props = body['props']

    # WHY: Verify form re-renders with all dropdown options for re-selection
    assert props['size_options'].is_a?(Array)
    assert props['locale_options'].is_a?(Array)
    assert props['currency_options'].is_a?(Array)

    # WHY: Verify entered values are preserved in organization prop
    org = props['organization']
    assert_equal 'Technology', org['industry']
    assert_equal '11-50', org['size']
    assert_equal 'https://www.test.com', org['website']
  end

  # WHY: Test that organization edit page has invite button and links to invitation form with org pre-selected
  test 'organization edit page has invite button that links to invitations with org preselected' do
    admin = accounts(:amplifa_admin)
    org = organizations(:acme)
    login_as(admin)

    # WHY: Clicking invite button from org edit page should go to invitation form with org_id in URL
    get new_admin_invitation_path(organization_id: org.id), headers: inertia_headers

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 'Admin/Invitations/New', body['component']

    # WHY: The preselected_organization_id should be passed to frontend for auto-selection
    assert_equal org.id, body['props']['preselected_organization_id']
  end

  private

  def inertia_headers
    # WHY: Inertia.js requires this header to return JSON responses instead of full page renders
    { 'X-Inertia' => 'true', 'X-Inertia-Version' => ViteRuby.digest }
  end

  def with_memory_cache
    cache = ActiveSupport::Cache::MemoryStore.new

    Rails.stub(:cache, cache) do
      PlaybookGenerationChannel.stub(:broadcast_to, true) do
        yield cache
      end
    end
  end
end
