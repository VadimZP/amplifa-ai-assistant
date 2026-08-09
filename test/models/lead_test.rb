# frozen_string_literal: true

require 'test_helper'

class LeadTest < ActiveSupport::TestCase
  # Tests cover email validation, format, uniqueness, and normalization (WHY: email is the primary identifier for leads)
  test 'requires email' do
    lead = Lead.new(organization: organizations(:acme))
    assert_not lead.valid?
    assert_includes lead.errors[:email], "can't be blank"
  end

  test 'requires valid email format' do
    lead = Lead.new(organization: organizations(:acme), email: 'not-an-email')
    assert_not lead.valid?
    assert_includes lead.errors[:email], 'must be a valid email address'
  end

  test 'accepts valid email format' do
    lead = Lead.new(organization: organizations(:acme), email: 'valid@example.com')
    assert lead.valid?
  end

  test 'email is unique per organization' do
    # WHY: Same email can exist in different orgs but not within the same org
    existing = leads(:john_doe)
    duplicate = Lead.new(organization: existing.organization, email: existing.email)
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:email], 'has already been taken'
  end

  test 'same email allowed in different organizations' do
    # WHY: Multi-tenant support - leads are org-scoped
    lead = Lead.new(organization: organizations(:beta), email: leads(:john_doe).email)
    assert lead.valid?
  end

  test 'normalizes email to lowercase' do
    # WHY: Prevent duplicate entries with different casing
    lead = Lead.new(organization: organizations(:acme), email: '  UPPER@CASE.COM  ')
    lead.valid?
    assert_equal 'upper@case.com', lead.email
  end

  # Tests cover linkedin_url validation (WHY: ensure proper LinkedIn profile URLs)
  test 'validates linkedin_url format when present' do
    lead = Lead.new(organization: organizations(:acme), email: 'test@test.com', linkedin_url: 'not-a-linkedin-url')
    assert_not lead.valid?
    assert_includes lead.errors[:linkedin_url], 'must be a LinkedIn URL'
  end

  test 'accepts valid linkedin_url' do
    lead = Lead.new(organization: organizations(:acme), email: 'test@test.com', linkedin_url: 'https://www.linkedin.com/in/johndoe')
    assert lead.valid?
  end

  test 'allows blank linkedin_url' do
    lead = Lead.new(organization: organizations(:acme), email: 'test@test.com', linkedin_url: '')
    assert lead.valid?
  end

  # Tests cover company_website validation (WHY: ensure valid URLs for company websites)
  test 'validates company_website format when present' do
    lead = Lead.new(organization: organizations(:acme), email: 'test@test.com', company_website: 'not-a-url')
    assert_not lead.valid?
    assert_includes lead.errors[:company_website], 'must be a valid URL or domain'
  end

  test 'accepts valid company_website with https' do
    lead = Lead.new(organization: organizations(:acme), email: 'test@test.com', company_website: 'https://example.com')
    assert lead.valid?
  end

  # WHY: CSV imports commonly contain domain-only values without protocol
  test 'accepts domain-only company_website without protocol' do
    lead = Lead.new(organization: organizations(:acme), email: 'test@test.com', company_website: 'example.com')
    assert lead.valid?
  end

  # WHY: Real-world imports have domains like "soorty.com", "maseksport.com"
  test 'accepts various domain formats for company_website' do
    valid_domains = %w[
      soorty.com
      maseksport.com
      jawandson.com
      www.example.com
      sub.domain.co.uk
      my-company.io
    ]

    valid_domains.each do |domain|
      lead = Lead.new(organization: organizations(:acme), email: "test#{rand(1000)}@test.com", company_website: domain)
      assert lead.valid?, "Expected '#{domain}' to be valid, but got errors: #{lead.errors.full_messages.join(', ')}"
    end
  end

  # WHY: Still reject clearly invalid values
  test 'rejects invalid company_website values' do
    invalid_values = %w[
      not-valid
      just-text
      .startswithdot.com
    ]

    invalid_values.each do |value|
      lead = Lead.new(organization: organizations(:acme), email: 'test@test.com', company_website: value)
      assert_not lead.valid?, "Expected '#{value}' to be invalid"
      assert lead.errors[:company_website].any?, "Expected errors on company_website for '#{value}'"
    end
  end

  # Tests cover display_name method (WHY: provides fallback chain for displaying lead name)
  test 'display_name returns full_name when present' do
    lead = leads(:john_doe)
    lead.full_name = 'John Full Doe'
    assert_equal 'John Full Doe', lead.display_name
  end

  test 'display_name returns first and last name when full_name blank' do
    lead = leads(:john_doe)
    lead.full_name = nil
    lead.first_name = 'John'
    lead.last_name = 'Doe'
    assert_equal 'John Doe', lead.display_name
  end

  test 'display_name returns email when names blank' do
    lead = leads(:john_doe)
    lead.full_name = nil
    lead.first_name = nil
    lead.last_name = nil
    assert_equal lead.email, lead.display_name
  end

  # Tests cover blacklist!/unblacklist! methods (WHY: critical for managing lead outreach eligibility)
  test 'blacklist! marks lead as blacklisted with reason' do
    lead = leads(:john_doe)
    assert_not lead.blacklisted?

    lead.blacklist!(reason: 'Customer request')

    assert lead.blacklisted?
    assert_equal 'Customer request', lead.blacklist_reason
    assert_equal 'other', lead.blacklist_reason_category
    assert_not_nil lead.blacklisted_at
  end

  test 'blacklist! infers reply-interest category from system reason text' do
    lead = leads(:john_doe)

    lead.blacklist!(reason: Blacklist.reply_interest_reason('interested'))

    assert_equal 'reply_interested', lead.blacklist_reason_category
  end

  test 'blacklist! infers reply-interest category from manual system reason text' do
    lead = leads(:john_doe)

    lead.blacklist!(reason: Blacklist.reply_interest_reason('interested', manual: true))

    assert_equal 'reply_interested', lead.blacklist_reason_category
  end

  test 'unblacklist! removes blacklist flag' do
    lead = leads(:blacklisted_lead)
    assert lead.blacklisted?

    lead.unblacklist!

    assert_not lead.blacklisted?
    assert_nil lead.blacklist_reason
    assert_nil lead.blacklist_reason_category
    assert_nil lead.blacklisted_at
  end

  # Tests cover email_domain method (WHY: used for domain-based blacklist checking)
  test 'email_domain extracts domain from email' do
    lead = leads(:john_doe)
    assert_equal 'example.com', lead.email_domain
  end

  test 'email_domain returns nil for nil email' do
    lead = Lead.new
    assert_nil lead.email_domain
  end

  # Tests cover scopes (WHY: efficient querying for common use cases)
  test 'not_blacklisted scope excludes blacklisted leads' do
    results = Lead.not_blacklisted
    assert_includes results, leads(:john_doe)
    assert_not_includes results, leads(:blacklisted_lead)
  end

  test 'blacklisted scope includes only blacklisted leads' do
    results = Lead.blacklisted
    assert_not_includes results, leads(:john_doe)
    assert_includes results, leads(:blacklisted_lead)
  end

  test 'effectively_not_blacklisted_for matches stored blacklist flag semantics' do
    lead = leads(:john_doe)

    Blacklist.create!(
      organization: lead.organization,
      created_by: accounts(:customer_admin),
      value: lead.email,
      value_type: 'email',
      source: 'manual',
      reason: 'Blocked for samples'
    )

    results = Lead.effectively_not_blacklisted_for(lead.organization)

    assert_not lead.blacklisted?
    assert_includes results, lead
  end

  test 'effectively_not_blacklisted_for excludes stored blacklisted leads' do
    lead = leads(:john_doe)
    lead.blacklist!(reason: 'Stored blacklist flag')

    results = Lead.effectively_not_blacklisted_for(lead.organization)

    assert_not_includes results, lead
  end

  test 'visible_in_customer_agents includes blacklisted lead with qualifying blacklist reason category' do
    lead = leads(:john_doe)
    lead.blacklist!(
      reason: Blacklist.reply_interest_reason('interested'),
      category: Blacklist.reply_interest_reason_category('interested')
    )

    results = Lead.visible_in_customer_agents_for(lead.organization)

    assert_includes results, lead
  end

  test 'visible_in_customer_agents excludes blacklisted lead without qualifying blacklist reason category' do
    lead = leads(:john_doe)
    lead.blacklist!(reason: 'Manual blacklist')

    results = Lead.visible_in_customer_agents_for(lead.organization)

    assert_not_includes results, lead
  end

  test 'for_organization scope filters by org' do
    results = Lead.for_organization(organizations(:acme))
    assert_includes results, leads(:john_doe)
    assert_not_includes results, leads(:beta_lead)
  end

  test 'with_email_domain scope finds leads by domain' do
    results = Lead.with_email_domain('example.com')
    assert_includes results, leads(:john_doe)
    assert_not_includes results, leads(:jane_smith)
  end

  test 'by_company scope filters by company name' do
    results = Lead.by_company('Example Corp')
    assert_includes results, leads(:john_doe)
    assert_not_includes results, leads(:jane_smith)
  end

  # Tests cover associations (WHY: ensure proper relationships between models)
  test 'belongs to organization' do
    lead = leads(:john_doe)
    assert_equal organizations(:acme), lead.organization
  end

  test 'belongs to lead_import optionally' do
    lead_with_import = leads(:john_doe)
    lead_without_import = leads(:growth_lab_lead)

    assert_not_nil lead_with_import.lead_import
    assert_nil lead_without_import.lead_import
  end

  test 'has many agent_leads' do
    lead = leads(:john_doe)
    assert lead.agent_leads.count >= 1
  end

  test 'has many agents through agent_leads' do
    lead = leads(:john_doe)
    assert lead.agents.include?(agents(:draft_agent))
  end

  # ============================================================================
  # Person Association Tests
  # WHY: Global Person records enable cross-organization deduplication and
  # centralized enrichment data sharing
  # ============================================================================

  test 'belongs to person optionally' do
    # WHY: Existing leads may not yet have person associations
    lead = leads(:john_doe)
    assert lead.respond_to?(:person)
    # Lead can be valid without a person
    lead.person = nil
    assert lead.valid?
  end

  test 'with_person scope returns leads with person_id' do
    # WHY: Identify leads that have been linked to global Person records
    lead_with_person = leads(:john_doe)
    lead_with_person.update!(person: people(:john_doe_person))

    results = Lead.with_person
    assert_includes results, lead_with_person
  end

  test 'without_person scope returns leads without person_id' do
    # WHY: Identify leads that need Person records created
    lead_without = leads(:jane_smith)
    lead_without.update!(person_id: nil)

    results = Lead.without_person
    assert_includes results, lead_without
  end

  # ============================================================================
  # DISC Profile Validation Tests
  # WHY: Consistent DISC profile codes ensure reliable personalization
  # ============================================================================

  test 'disc_profile delegates to person' do
    person = Person.create!(email: 'disc@test.com', disc_profile: 'D')
    lead = Lead.create!(organization: organizations(:acme), email: person.email, person: person)
    assert_equal 'D', lead.disc_profile
  end

  test 'disc_profile returns nil when no person linked' do
    lead = Lead.new(organization: organizations(:acme), email: 'nodisc@test.com')
    assert_nil lead.disc_profile
  end

  # ============================================================================
  # create_from_person! Tests
  # WHY: Creating leads from Person records ensures data consistency
  # ============================================================================

  test 'create_from_person! creates lead with person data' do
    person = people(:john_doe_person)
    org = organizations(:beta)

    lead = Lead.create_from_person!(organization: org, person: person)

    assert_equal person.email, lead.email
    assert_equal person.first_name, lead.first_name
    assert_equal person.last_name, lead.last_name
    assert_equal person.full_name, lead.full_name
    assert_equal person.job_title, lead.job_title
    assert_equal person.company, lead.company
    assert_equal person.linkedin_url, lead.linkedin_url
    assert_equal person, lead.person
    assert lead.persisted?
  end

  test 'create_from_person! delegates enrichment to person' do
    person = people(:john_doe_person)
    org = organizations(:beta)

    lead = Lead.create_from_person!(organization: org, person: person)

    assert_equal person, lead.person
    assert_equal person.disc_profile, lead.disc_profile
    assert_equal person.linkedin_scraped_data, lead.linkedin_scraped_data
    assert_equal person.linkedin_scraped_at, lead.linkedin_scraped_at
    assert_equal person.company_website_scraped_data, lead.company_website_scraped_data
  end

  test 'create_from_person! accepts additional attributes' do
    person = people(:jane_smith_person)
    org = organizations(:beta)

    lead = Lead.create_from_person!(
      organization: org,
      person: person,
      additional_attrs: { custom_fields: { source: 'manual' } }
    )

    assert_equal({ 'source' => 'manual' }, lead.custom_fields)
  end

  # ============================================================================
  # find_or_create_with_person! Tests
  # WHY: Single entry point for lead creation with automatic Person handling
  # ============================================================================

  test 'find_or_create_with_person! returns existing lead' do
    existing = leads(:john_doe)

    lead = Lead.find_or_create_with_person!(
      organization: existing.organization,
      email: existing.email,
      attributes: { first_name: 'Different' }
    )

    assert_equal existing.id, lead.id
    assert_equal existing.first_name, lead.first_name # Not updated
  end

  test 'find_or_create_with_person! creates new lead and person' do
    # WHY: New email should create both Person and Lead records
    org = organizations(:acme)
    email = 'brand.new@newperson.com'

    assert_difference ['Lead.count', 'Person.count'], 1 do
      lead = Lead.find_or_create_with_person!(
        organization: org,
        email: email,
        attributes: {
          first_name: 'Brand',
          last_name: 'New',
          job_title: 'CEO'
        }
      )

      assert_equal email, lead.email
      assert_equal 'Brand', lead.first_name
      assert_not_nil lead.person
      assert_equal email, lead.person.email
    end
  end

  test 'find_or_create_with_person! links to existing person' do
    # WHY: If Person exists globally, Lead should link to it
    person = people(:john_doe_person)
    org = organizations(:growth_lab) # Different org than john_doe's lead

    assert_no_difference 'Person.count' do
      lead = Lead.find_or_create_with_person!(
        organization: org,
        email: person.email
      )

      assert_equal person, lead.person
    end
  end

  # ============================================================================
  # Enrichment Data Delegation Tests
  # ============================================================================

  test 'enrichment accessors return empty/nil when no person linked' do
    lead = Lead.new(organization: organizations(:acme), email: 'noperson@test.com')

    assert_nil lead.linkedin_headline
    assert_nil lead.linkedin_summary
    assert_nil lead.company_website_content
    assert_nil lead.company_website_summary
    assert_equal [], lead.linkedin_posts
    assert_equal({}, lead.linkedin_scraped_data)
    assert_equal({}, lead.company_website_scraped_data)
  end

  test 'company_website_summary delegates nil when person has no website scrape summary' do
    person = Person.create!(
      email: 'no-summary@test.com',
      company_website_scraped_data: { 'content' => 'Legacy-only website content' }
    )
    lead = Lead.create!(organization: organizations(:acme), email: person.email, person: person)

    assert_nil lead.company_website_summary
  end

  test 'linkedin_posts returns empty array when person has no posts' do
    person = Person.create!(email: 'noposts@test.com', linkedin_posts_scraped_data: {})
    lead = Lead.create!(organization: organizations(:acme), email: person.email, person: person)

    assert_equal [], lead.linkedin_posts
  end

  private

  def create_active_ooo_period(lead, effective_return_date:)
    lead.out_of_office_periods.create!(
      organization: lead.organization,
      detected_at: Time.current,
      effective_return_date: effective_return_date
    )
  end
end
