require 'test_helper'

class OrganizationTest < ActiveSupport::TestCase
  # Why: Organizations are the core entity that customers belong to, and we need to ensure
  # proper validation and that the new status/website fields work correctly

  def setup
    @organization = organizations(:acme)
  end

  # Why: welcome-back prompt config mirrors autoreply, with FKs that nullify on prompt deletion
  test 'welcome-back email toggle defaults to enabled and must be boolean' do
    organization = Organization.new(
      name: 'Welcome Back Toggle Org',
      status: 'active',
      monthly_meeting_limit: 5,
      plan_tier: 'basic',
      locale: 'en',
      currency: 'EUR'
    )

    assert_equal false, organization.welcome_back_email_enabled

    @organization.welcome_back_email_enabled = nil
    refute @organization.valid?
    assert_includes @organization.errors[:welcome_back_email_enabled], 'is not included in the list'
  end

  # Why: standard mode must ALWAYS resolve to the global slug prompts and IGNORE any
  # stored refs (truth table row 1) — even when stale org-owned refs are populated.
  # Why: custom mode with both org-owned refs returns each ref (truth table rows 2 + 4).
  # Why: custom is valid when partial — a set subject uses the ref, a nil body falls
  # back to the global independently (truth table rows 2 + 5). Partial custom is a valid steady state.
  # Why: custom with both refs nil is valid and both sides fall back to globals (truth table rows 3 + 5).
  # Why: a body ref must be a welcome_back_body prompt; a welcome_back_subject prompt is rejected.
  # Why: a ref owned by another organization is neither global nor owned by this org.
  # Why: mode is constrained to the known set.
  # Why: deleting an org-owned selected prompt must NULLIFY the ref (FK on_delete: :nullify)
  # and the org must survive and fall back to the global — no cascade delete, no exception.
  # Name validation tests
  # Why: Organization name is the primary identifier and must be valid
  test 'should require name to be present' do
    organization = Organization.new
    refute organization.valid?
    assert_includes organization.errors[:name], "can't be blank"
  end

  test 'should validate name length' do
    organization = Organization.new(name: 'a' * 101)
    refute organization.valid?
    assert_includes organization.errors[:name], 'is too long (maximum is 100 characters)'
  end

  # Industry validation tests
  # Why: Industry is optional but should have length limits
  test 'should allow blank industry' do
    organization = Organization.new(name: 'Test Org', industry: nil)
    assert organization.valid?
  end

  test 'should validate industry length' do
    organization = Organization.new(name: 'Test Org', industry: 'a' * 101)
    refute organization.valid?
    assert_includes organization.errors[:industry], 'is too long (maximum is 100 characters)'
  end

  # Size validation tests
  # Why: Size must be from a predefined list if provided
  test 'should allow blank size' do
    organization = Organization.new(name: 'Test Org', size: nil)
    assert organization.valid?
  end

  test 'should validate size is in list' do
    organization = Organization.new(name: 'Test Org', size: 'invalid')
    refute organization.valid?
    assert_includes organization.errors[:size], 'is not included in the list'
  end

  test 'should accept valid sizes' do
    valid_sizes = %w[1-10 11-50 51-200 201-1000 1000+]
    valid_sizes.each do |size|
      organization = Organization.new(name: 'Test Org', size: size)
      assert organization.valid?, "#{size} should be valid"
    end
  end

  # Website validation tests
  # Why: Website URLs must be properly formatted if provided
  test 'should allow blank website' do
    organization = Organization.new(name: 'Test Org', website: nil)
    assert organization.valid?
  end

  test 'should validate website format' do
    organization = Organization.new(name: 'Test Org', website: 'not-a-url')
    refute organization.valid?
    assert_includes organization.errors[:website], 'must be a valid URL'
  end

  test 'should accept valid http website' do
    organization = Organization.new(name: 'Test Org', website: 'http://example.com')
    assert organization.valid?
  end

  test 'should accept valid https website' do
    organization = Organization.new(name: 'Test Org', website: 'https://example.com')
    assert organization.valid?
  end

  test 'should auto-add organization website domain to blacklist on create' do
    organization = Organization.create!(
      name: 'Own Domain Org',
      status: 'onboarding',
      locale: 'en',
      currency: 'EUR',
      website: 'https://www.own-domain.org'
    )

    entry = Blacklist.find_by(
      organization: organization,
      value: 'own-domain.org',
      value_type: 'domain'
    )

    assert_not_nil entry
    assert_equal 'manual', entry.source
    assert_equal accounts(:amplifa_admin), entry.created_by
  end

  test 'should auto-add organization website domain to blacklist on website update' do
    organization = organizations(:acme)

    assert_difference lambda {
      Blacklist.where(organization: organization, value: 'new-acme.com', value_type: 'domain').count
    }, 1 do
      organization.update!(website: 'https://www.new-acme.com')
    end

    entry = Blacklist.find_by!(organization: organization, value: 'new-acme.com', value_type: 'domain')
    assert_equal 'manual', entry.source
    assert_equal accounts(:customer_admin), entry.created_by
  end

  test 'should not duplicate own-domain blacklist when domain already exists' do
    organization = organizations(:acme)

    Blacklist.create!(
      organization: organization,
      created_by: accounts(:customer_admin),
      value: 'acme.com',
      value_type: 'domain',
      source: 'manual'
    )

    assert_no_difference lambda {
      Blacklist.where(organization: organization, value: 'acme.com', value_type: 'domain').count
    } do
      organization.update!(website: 'https://www.acme.com/about')
    end
  end

  # Status validation tests
  # Why: Status is required and must be from the predefined list
  test 'should require status' do
    organization = Organization.new(name: 'Test Org', status: nil)
    refute organization.valid?
    assert_includes organization.errors[:status], 'is not included in the list'
  end

  test 'should validate status is in list' do
    organization = Organization.new(name: 'Test Org', status: 'invalid')
    refute organization.valid?
    assert_includes organization.errors[:status], 'is not included in the list'
  end

  test 'should accept valid statuses' do
    valid_statuses = %w[onboarding active paused churned]
    valid_statuses.each do |status|
      organization = Organization.new(name: 'Test Org', status: status)
      assert organization.valid?, "#{status} should be valid"
    end
  end

  test 'should have many accounts' do
    assert_respond_to @organization, :accounts
  end

  test 'has accounts through memberships' do
    OrganizationMembership.create!(
      account: accounts(:growth_lab_user),
      organization: @organization,
      role: 'customer_user',
      status: 'active'
    )

    assert_includes @organization.accounts, accounts(:customer_admin)
    assert_includes @organization.accounts, accounts(:growth_lab_user)
  end

  test 'should have many admin_activities' do
    assert_respond_to @organization, :admin_activities
  end

  test 'should have many playbooks' do
    assert_respond_to @organization, :playbooks
  end

  test 'should have many meetings' do
    assert_respond_to @organization, :meetings
    assert_nothing_raised { @organization.meetings.to_a }
  end

  test 'should return playbooks for organization' do
    # Why: Need to ensure the association actually returns playbooks
    organization = organizations(:acme)
    # The association should be callable without error
    assert_nothing_raised { organization.playbooks.to_a }
  end

  # Account method tests
  # Why: These methods are used to get different types of users from an organization
  test 'admin_users returns customer_admin accounts' do
    non_admin_membership = OrganizationMembership.create!(
      account: accounts(:growth_lab_user),
      organization: @organization,
      role: 'customer_user',
      status: 'active'
    )
    non_admin_membership.account.update!(role: 'customer_admin')

    admin_users = @organization.admin_users
    assert_includes admin_users, accounts(:customer_admin)
    assert_not_includes admin_users, non_admin_membership.account
  end

  test 'regular_users returns customer_user accounts' do
    admin_role_membership = OrganizationMembership.create!(
      account: accounts(:growth_lab_user),
      organization: @organization,
      role: 'customer_user',
      status: 'active'
    )
    admin_role_membership.account.update!(role: 'customer_admin')

    regular_users = @organization.regular_users
    assert_includes regular_users, accounts(:customer_user)
    assert_includes regular_users, admin_role_membership.account
  end

  test 'all_users returns both customer_admin and customer_user accounts' do
    # This will work after fixtures are updated
    all_users = @organization.all_users
    assert(all_users.all? { |a| a.role.in?(%w[customer_admin customer_user]) })
  end

  # Status method tests
  # Why: These methods control soft delete functionality
  test 'active? returns true when not deactivated' do
    organization = Organization.new(name: 'Test Org', deactivated_at: nil)
    assert organization.active?
  end

  test 'active? returns false when deactivated' do
    organization = Organization.new(name: 'Test Org', deactivated_at: Time.current)
    refute organization.active?
  end

  test 'deactivate! sets deactivated_at' do
    organization = organizations(:acme)
    assert_nil organization.deactivated_at
    organization.deactivate!
    assert_not_nil organization.deactivated_at
  end

  # Scope tests
  # Why: Scopes are used to filter organizations throughout the app
  test 'active scope returns only non-deactivated organizations' do
    active_orgs = Organization.active
    assert(active_orgs.all? { |o| o.deactivated_at.nil? })
  end

  test 'by_status scope returns organizations with given status' do
    # This will work after the migration adds status field
    onboarding_orgs = Organization.by_status('onboarding')
    assert(onboarding_orgs.all? { |o| o.status == 'onboarding' })
  end

  # Financial field validation tests (Week 2)
  # Why: Financial fields must be non-negative if provided for ROI calculations
  test 'should allow nil monthly_subscription' do
    organization = Organization.new(name: 'Test Org', status: 'onboarding', locale: 'en', currency: 'EUR',
                                    monthly_subscription: nil)
    assert organization.valid?
  end

  test 'should accept positive monthly_subscription' do
    organization = Organization.new(name: 'Test Org', status: 'onboarding', locale: 'en', currency: 'EUR',
                                    monthly_subscription: 499.99)
    assert organization.valid?
  end

  test 'should reject negative monthly_subscription' do
    # Why: Negative prices don't make sense
    organization = Organization.new(name: 'Test Org', status: 'onboarding', locale: 'en', currency: 'EUR',
                                    monthly_subscription: -100)
    refute organization.valid?
    assert_includes organization.errors[:monthly_subscription], 'must be greater than or equal to 0'
  end

  test 'should allow zero monthly_subscription' do
    # Why: Some orgs might have free trials or special pricing
    organization = Organization.new(name: 'Test Org', status: 'onboarding', locale: 'en', currency: 'EUR',
                                    monthly_subscription: 0)
    assert organization.valid?
  end

  test 'should allow nil meeting_price' do
    organization = Organization.new(name: 'Test Org', status: 'onboarding', locale: 'en', currency: 'EUR',
                                    meeting_price: nil)
    assert organization.valid?
  end

  test 'should accept positive meeting_price' do
    organization = Organization.new(name: 'Test Org', status: 'onboarding', locale: 'en', currency: 'EUR',
                                    meeting_price: 750.00)
    assert organization.valid?
  end

  test 'should reject negative meeting_price' do
    organization = Organization.new(name: 'Test Org', status: 'onboarding', locale: 'en', currency: 'EUR',
                                    meeting_price: -50)
    refute organization.valid?
    assert_includes organization.errors[:meeting_price], 'must be greater than or equal to 0'
  end

  test 'should allow nil average_contract_value' do
    organization = Organization.new(name: 'Test Org', status: 'onboarding', locale: 'en', currency: 'EUR',
                                    average_contract_value: nil)
    assert organization.valid?
  end

  test 'should accept positive average_contract_value' do
    organization = Organization.new(name: 'Test Org', status: 'onboarding', locale: 'en', currency: 'EUR',
                                    average_contract_value: 15_000.00)
    assert organization.valid?
  end

  test 'should reject negative average_contract_value' do
    organization = Organization.new(name: 'Test Org', status: 'onboarding', locale: 'en', currency: 'EUR',
                                    average_contract_value: -1000)
    refute organization.valid?
    assert_includes organization.errors[:average_contract_value], 'must be greater than or equal to 0'
  end

  # Calendly URL validation tests (Week 2)
  # Why: Calendly URL must be valid for meeting bookings to work
  test 'should allow nil calendly_url' do
    organization = Organization.new(name: 'Test Org', status: 'onboarding', locale: 'en', currency: 'EUR',
                                    calendly_url: nil)
    assert organization.valid?
  end

  test 'should accept valid calendly_url' do
    organization = Organization.new(name: 'Test Org', status: 'onboarding', locale: 'en', currency: 'EUR',
                                    calendly_url: 'https://calendly.com/acme/meeting')
    assert organization.valid?
  end

  test 'should reject calendly_url without correct domain' do
    # Why: Only calendly.com URLs are valid
    organization = Organization.new(name: 'Test Org', status: 'onboarding', locale: 'en', currency: 'EUR',
                                    calendly_url: 'https://wrongdomain.com/meeting')
    refute organization.valid?
    assert_includes organization.errors[:calendly_url], 'must start with https://calendly.com/'
  end

  test 'should reject calendly_url without https' do
    # Why: Calendly requires HTTPS
    organization = Organization.new(name: 'Test Org', status: 'onboarding', locale: 'en', currency: 'EUR',
                                    calendly_url: 'http://calendly.com/meeting')
    refute organization.valid?
    assert_includes organization.errors[:calendly_url], 'must start with https://calendly.com/'
  end

  # Locale and currency validation tests (Week 2)
  # Why: Locale and currency are required for i18n and proper financial display
  test 'should require locale' do
    organization = Organization.new(name: 'Test Org', status: 'onboarding', locale: nil, currency: 'EUR')
    refute organization.valid?
    assert_includes organization.errors[:locale], 'is not included in the list'
  end

  test 'should accept en locale' do
    organization = Organization.new(name: 'Test Org', status: 'onboarding', locale: 'en', currency: 'EUR')
    assert organization.valid?
  end

  test 'should accept de locale' do
    organization = Organization.new(name: 'Test Org', status: 'onboarding', locale: 'de', currency: 'EUR')
    assert organization.valid?
  end

  test 'should accept pt-BR locale' do
    organization = Organization.new(name: 'Test Org', status: 'onboarding', locale: 'pt-BR', currency: 'EUR')
    assert organization.valid?
  end

  test 'should reject invalid locale' do
    organization = Organization.new(name: 'Test Org', status: 'onboarding', locale: 'xx', currency: 'EUR')
    refute organization.valid?
    assert_includes organization.errors[:locale], 'is not included in the list'
  end

  test 'should require currency' do
    organization = Organization.new(name: 'Test Org', status: 'onboarding', locale: 'en', currency: nil)
    refute organization.valid?
    assert_includes organization.errors[:currency], 'is not included in the list'
  end

  test 'should accept valid currencies' do
    # Why: Support for multiple currencies (EUR, USD, GBP, CHF)
    %w[EUR USD GBP CHF].each do |currency|
      organization = Organization.new(name: 'Test Org', status: 'onboarding', locale: 'en', currency: currency)
      assert organization.valid?, "#{currency} should be valid"
    end
  end

  test 'should reject invalid currency' do
    organization = Organization.new(name: 'Test Org', status: 'onboarding', locale: 'en', currency: 'JPY')
    refute organization.valid?
    assert_includes organization.errors[:currency], 'is not included in the list'
  end

  # Onboarding methods tests (Week 2)
  # Why: Onboarding tracking is critical for guiding customers through setup
  test 'onboarding_steps_completed returns array of completed step keys' do
    # Why: Need to track which onboarding steps are done
    org = Organization.new(
      name: 'Test Org',
      status: 'onboarding',
      locale: 'en',
      currency: 'EUR',
      website: 'https://example.com',
      average_contract_value: 10_000,
      calendly_url: 'https://calendly.com/test/meeting'
    )
    completed_steps = org.onboarding_steps_completed
    assert completed_steps.is_a?(Array)
    # Profile step should be completed with website, ACV, and calendly
    assert_includes completed_steps, :profile_completed
  end

  test 'onboarding_steps_pending returns array of pending step keys' do
    # Why: Need to show which onboarding steps remain
    org = Organization.new(
      name: 'Test Org',
      status: 'onboarding',
      locale: 'en',
      currency: 'EUR'
    )
    pending_steps = org.onboarding_steps_pending
    assert pending_steps.is_a?(Array)
    # Profile step should be pending (no website, ACV, calendly)
    assert_includes pending_steps, :profile_completed
    # Language step is complete because locale.present? is true
    refute_includes pending_steps, :language_selected
  end

  test 'onboarding_complete? returns false when steps pending' do
    # Why: Need to know if onboarding is fully complete
    org = Organization.new(
      name: 'Test Org',
      status: 'onboarding',
      locale: 'en',
      currency: 'EUR'
    )
    refute org.onboarding_complete?
  end

  test 'onboarding_complete? returns true when all steps completed' do
    org = Organization.new(
      name: 'Test Org',
      status: 'onboarding',
      locale: 'en',
      currency: 'EUR',
      website: 'https://example.com',
      average_contract_value: 10_000,
      calendly_url: 'https://calendly.com/test/meeting'
    )
    # NOTE: language_selected check passes because locale.present? is true
    assert org.onboarding_complete?
  end

  test 'onboarding_completion_percentage calculates correctly' do
    # Why: Need to show progress to users
    org = Organization.new(
      name: 'Test Org',
      status: 'onboarding',
      locale: 'en',
      currency: 'EUR',
      website: 'https://example.com',
      average_contract_value: 10_000,
      calendly_url: 'https://calendly.com/test/meeting'
    )
    # Both steps completed (profile + language)
    assert_equal 100, org.onboarding_completion_percentage
  end

  test 'onboarding_completion_percentage returns 50 when one of two steps completed' do
    org = Organization.new(
      name: 'Test Org',
      status: 'onboarding',
      locale: 'en',
      currency: 'EUR',
      website: 'https://example.com',
      average_contract_value: 10_000,
      calendly_url: 'https://calendly.com/test/meeting'
    )
    # Override locale check to simulate language not being explicitly selected
    OnboardingSteps::STEPS[:language_selected][:check] = ->(_o) { false }
    assert_equal 50, org.onboarding_completion_percentage
  ensure
    # Reset the check to original
    OnboardingSteps::STEPS[:language_selected][:check] = ->(o) { o.locale.present? }
  end

  test 'onboarding_completion_percentage returns 0 when no steps completed' do
    org = Organization.new(
      name: 'Test Org',
      status: 'onboarding',
      locale: nil,
      currency: 'EUR'
    )
    # Override default locale to simulate no locale set
    org.define_singleton_method(:locale) { nil }
    assert_equal 0, org.onboarding_completion_percentage
  end

  # ============================================================================
  # Description and People Association Tests
  # WHY: Description is auto-generated for downstream personalization, needs cache management
  # ============================================================================

  test 'has many people through leads' do
    # WHY: Organizations can access global Person records via their leads
    org = organizations(:acme)
    assert org.respond_to?(:people)
  end

  # WHY: Conversations association enables Reply Center organization-scoped view
  test 'has many conversations' do
    org = organizations(:acme)
    assert org.respond_to?(:conversations)
    assert_nothing_raised { org.conversations.to_a }
  end

  # WHY: Slack webhook URL validation ensures only valid Slack URLs are accepted
  test 'should allow nil slack_webhook_url' do
    organization = Organization.new(name: 'Test Org', status: 'onboarding', locale: 'en', currency: 'EUR',
                                    slack_webhook_url: nil)
    assert organization.valid?
  end

  test 'should accept valid slack_webhook_url' do
    organization = Organization.new(name: 'Test Org', status: 'onboarding', locale: 'en', currency: 'EUR',
                                    slack_webhook_url: 'https://hooks.slack.com/services/T123/B456/abc123')
    assert organization.valid?
  end

  test 'should reject invalid slack_webhook_url' do
    organization = Organization.new(name: 'Test Org', status: 'onboarding', locale: 'en', currency: 'EUR',
                                    slack_webhook_url: 'https://example.com/webhook')
    refute organization.valid?
    assert_includes organization.errors[:slack_webhook_url], 'must start with https://hooks.slack.com/'
  end

  # WHY: slack_configured? enables conditional Slack notifications
  test 'slack_configured? returns true when webhook_url present and notify enabled' do
    org = Organization.new(
      name: 'Test Org',
      status: 'onboarding',
      locale: 'en',
      currency: 'EUR',
      slack_webhook_url: 'https://hooks.slack.com/services/T123/B456/abc123',
      slack_notify_on_reply: true
    )
    assert org.slack_configured?
  end

  test 'slack_configured? returns false when webhook_url blank' do
    org = Organization.new(
      name: 'Test Org',
      status: 'onboarding',
      locale: 'en',
      currency: 'EUR',
      slack_webhook_url: nil,
      slack_notify_on_reply: true
    )
    refute org.slack_configured?
  end

  test 'slack_configured? returns false when notify disabled' do
    org = Organization.new(
      name: 'Test Org',
      status: 'onboarding',
      locale: 'en',
      currency: 'EUR',
      slack_webhook_url: 'https://hooks.slack.com/services/T123/B456/abc123',
      slack_notify_on_reply: false
    )
    refute org.slack_configured?
  end
end
