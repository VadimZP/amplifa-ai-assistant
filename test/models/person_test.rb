# frozen_string_literal: true

require 'test_helper'

class PersonTest < ActiveSupport::TestCase
  # ============================================================================
  # Email Validation Tests
  # WHY: Email is the primary globally unique identifier for Person records
  # ============================================================================

  test 'requires email' do
    person = Person.new
    assert_not person.valid?
    assert_includes person.errors[:email], "can't be blank"
  end

  test 'requires valid email format' do
    person = Person.new(email: 'not-an-email')
    assert_not person.valid?
    assert_includes person.errors[:email], 'must be a valid email address'
  end

  test 'accepts valid email format' do
    person = Person.new(email: 'valid@example.com')
    assert person.valid?
  end

  test 'email must be globally unique' do
    # WHY: Person is global, not org-scoped - one person per email worldwide
    existing = people(:john_doe_person)
    duplicate = Person.new(email: existing.email)
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:email], 'has already been taken'
  end

  test 'email uniqueness is case-insensitive' do
    # WHY: Prevent duplicate entries with different casing
    existing = people(:john_doe_person)
    duplicate = Person.new(email: existing.email.upcase)
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:email], 'has already been taken'
  end

  test 'normalizes email to lowercase and strips whitespace' do
    # WHY: Consistent email format for reliable deduplication
    person = Person.new(email: '  UPPER@CASE.COM  ')
    person.valid?
    assert_equal 'upper@case.com', person.email
  end

  # ============================================================================
  # LinkedIn URL Validation Tests
  # WHY: LinkedIn data is used for enrichment and DISC profile inference
  # ============================================================================

  test 'validates linkedin_url format when present' do
    person = Person.new(email: 'test@test.com', linkedin_url: 'not-a-linkedin-url')
    assert_not person.valid?
    assert_includes person.errors[:linkedin_url], 'must be a LinkedIn URL'
  end

  test 'accepts valid linkedin_url' do
    person = Person.new(email: 'test@test.com', linkedin_url: 'https://www.linkedin.com/in/unique-test-profile')
    assert person.valid?
  end

  test 'accepts linkedin_url without www' do
    person = Person.new(email: 'test@test.com', linkedin_url: 'https://linkedin.com/in/unique-no-www-profile')
    assert person.valid?
  end

  test 'allows blank linkedin_url' do
    person = Person.new(email: 'test@test.com', linkedin_url: '')
    assert person.valid?
  end

  test 'linkedin_url must be unique when present' do
    # WHY: Prevent duplicate Person records for same LinkedIn profile
    existing = people(:john_doe_person)
    duplicate = Person.new(email: 'different@email.com', linkedin_url: existing.linkedin_url)
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:linkedin_url], 'has already been taken'
  end

  test 'allows multiple people with blank linkedin_url' do
    # WHY: Only non-null URLs need uniqueness, blank is fine
    Person.create!(email: 'person1@test.com', linkedin_url: nil)
    person2 = Person.new(email: 'person2@test.com', linkedin_url: nil)
    assert person2.valid?
  end

  # ============================================================================
  # DISC Profile Validation Tests
  # WHY: Valid DISC profiles required for personalized outreach
  # ============================================================================

  test 'accepts valid disc_profile values' do
    # WHY: Only standard DISC profile codes should be stored
    Person::DISC_PROFILES.each do |profile|
      person = Person.new(email: "test#{profile.downcase}@test.com", disc_profile: profile)
      assert person.valid?, "Expected DISC profile '#{profile}' to be valid"
    end
  end

  test 'rejects invalid disc_profile values' do
    person = Person.new(email: 'test@test.com', disc_profile: 'X')
    assert_not person.valid?
    assert_includes person.errors[:disc_profile], 'is not included in the list'
  end

  test 'allows blank disc_profile' do
    # WHY: DISC profile is populated via enrichment, not required
    person = Person.new(email: 'test@test.com', disc_profile: nil)
    assert person.valid?
  end

  # ============================================================================
  # Display Name Tests
  # WHY: Provides fallback chain for displaying person name in UI
  # ============================================================================

  test 'display_name returns full_name when present' do
    person = people(:john_doe_person)
    person.full_name = 'John Full Doe'
    assert_equal 'John Full Doe', person.display_name
  end

  test 'display_name returns first and last name when full_name blank' do
    person = people(:john_doe_person)
    person.full_name = nil
    person.first_name = 'John'
    person.last_name = 'Doe'
    assert_equal 'John Doe', person.display_name
  end

  test 'display_name returns email when names blank' do
    person = people(:john_doe_person)
    person.full_name = nil
    person.first_name = nil
    person.last_name = nil
    assert_equal person.email, person.display_name
  end

  # Tests cover alias learning (WHY: trusted inbound reply matches should teach future address variants)
  test 'learn_email_alias! creates a normalized alias' do
    person = people(:john_doe_person)

    assert_difference 'person.email_aliases.count', 1 do
      person.learn_email_alias!('  Alias@Other.com  ')
    end

    assert_equal 'alias@other.com', person.email_aliases.order(:id).last.email
  end

  test 'learn_email_alias! ignores the primary email' do
    person = people(:john_doe_person)

    assert_no_difference 'person.email_aliases.count' do
      person.learn_email_alias!(person.email)
    end
  end

  test 'matches_email? returns true for learned aliases' do
    person = people(:john_doe_person)
    person.learn_email_alias!('alias@other.com')

    assert person.matches_email?('ALIAS@OTHER.COM')
    assert person.matches_email?(person.email)
    assert_not person.matches_email?('someone-else@example.com')
  end

  # ============================================================================
  # LinkedIn Scrape Cache Tests
  # WHY: Cached scrapes reduce API costs and improve performance
  # ============================================================================

  test 'linkedin_scrape_fresh? returns true when recently scraped' do
    person = people(:john_doe_person)
    person.linkedin_scraped_at = 1.day.ago
    assert person.linkedin_scrape_fresh?
  end

  test 'linkedin_scrape_fresh? returns false when stale' do
    person = people(:john_doe_person)
    person.linkedin_scraped_at = 61.days.ago
    assert_not person.linkedin_scrape_fresh?
  end

  test 'linkedin_scrape_fresh? returns false when never scraped' do
    person = people(:john_doe_person)
    person.linkedin_scraped_at = nil
    assert_not person.linkedin_scrape_fresh?
  end

  test 'linkedin_scrape_stale? is inverse of fresh' do
    person = people(:john_doe_person)
    person.linkedin_scraped_at = 1.day.ago
    assert_not person.linkedin_scrape_stale?

    person.linkedin_scraped_at = 61.days.ago
    assert person.linkedin_scrape_stale?
  end

  # ============================================================================
  # Company Website Scrape Cache Tests
  # WHY: Company data used for context in message generation
  # ============================================================================

  test 'company_website_scrape_fresh? returns true when recently scraped' do
    person = people(:john_doe_person)
    person.company_website_scraped_at = 1.day.ago
    assert person.company_website_scrape_fresh?
  end

  test 'company_website_scrape_fresh? returns false when stale' do
    person = Person.create!(email: 'stale-company-website@test.com')
    person.company_website_scraped_at = 61.days.ago
    assert_not person.company_website_scrape_fresh?
  end

  test 'company_website_scrape_fresh? returns false when never scraped' do
    person = Person.create!(email: 'never-scraped-company-website@test.com')
    person.company_website_scraped_at = nil
    assert_not person.company_website_scrape_fresh?
  end

  # ============================================================================
  # Update Enrichment Methods Tests
  # WHY: Standardized methods for updating enrichment data with timestamps
  # ============================================================================

  test 'update_company_website_scrape! sets data and timestamp' do
    person = people(:jane_smith_person)
    data = { 'content' => 'We build software', 'title' => 'Acme Corp' }

    person.update_company_website_scrape!(data)

    assert_equal data, person.company_website_scraped_data
    assert_in_delta Time.current, person.company_website_scraped_at, 2.seconds
    assert_nil person.company_website_scrape_error
  end

  test 'update_disc_profile! sets profile with metadata' do
    person = people(:jane_smith_person)

    person.update_disc_profile!('DI', source: 'linkedin_inferred',
                                      data: { confidence: 0.85, reasoning: 'High energy language' })

    assert_equal 'DI', person.disc_profile
    assert_equal 'linkedin_inferred', person.disc_profile_source
    assert_equal({ 'confidence' => 0.85, 'reasoning' => 'High energy language' }, person.disc_profile_data)
    assert_in_delta Time.current, person.disc_profile_assessed_at, 2.seconds
  end

  # ============================================================================
  # LinkedIn Data Accessor Tests
  # WHY: Convenient accessors for commonly used scraped fields
  # ============================================================================

  test 'linkedin_headline returns headline from scraped data' do
    person = people(:john_doe_person)
    person.linkedin_scraped_data = { 'headline' => 'Sales Leader | Enterprise SaaS' }
    assert_equal 'Sales Leader | Enterprise SaaS', person.linkedin_headline
  end

  test 'linkedin_headline returns nil when no data' do
    person = people(:jane_smith_person)
    person.linkedin_scraped_data = {}
    assert_nil person.linkedin_headline
  end

  test 'linkedin_summary returns summary from scraped data' do
    person = people(:john_doe_person)
    person.linkedin_scraped_data = { 'summary' => '15 years of sales experience...' }
    assert_equal '15 years of sales experience...', person.linkedin_summary
  end

  test 'company_website_content returns content from scraped data' do
    person = Person.create!(email: 'legacy-company-website-content@test.com')
    person.company_website_scraped_data = { 'content' => 'We are Acme Corp...' }
    assert_equal 'We are Acme Corp...', person.company_website_content
  end

  # ============================================================================
  # Scopes Tests
  # WHY: Efficient querying for common use cases
  # ============================================================================

  test 'with_linkedin scope returns people with linkedin_url' do
    results = Person.with_linkedin
    assert_includes results, people(:john_doe_person)
    assert_not_includes results, people(:no_linkedin_person)
  end

  test 'needs_linkedin_scrape scope returns stale or unscrapped people' do
    # Create person that needs scraping
    fresh_person = people(:john_doe_person)
    fresh_person.update!(linkedin_scraped_at: 1.day.ago)

    stale_person = people(:jane_smith_person)
    stale_person.update!(linkedin_scraped_at: 61.days.ago)

    results = Person.needs_linkedin_scrape
    assert_includes results, stale_person
    assert_not_includes results, fresh_person
  end

  test 'needs_disc_profile scope returns people with linkedin data but no disc profile' do
    # WHY: DISC inference requires LinkedIn data
    person_with_data_no_disc = people(:john_doe_person)
    person_with_data_no_disc.update!(
      linkedin_scraped_data: { 'headline' => 'Test' },
      disc_profile: nil
    )

    person_with_disc = people(:jane_smith_person)
    person_with_disc.update!(
      linkedin_scraped_data: { 'headline' => 'Test' },
      disc_profile: 'D'
    )

    results = Person.needs_disc_profile
    assert_includes results, person_with_data_no_disc
    assert_not_includes results, person_with_disc
  end

  # ============================================================================
  # Association Tests
  # WHY: Verify relationships with Lead records
  # ============================================================================

  test 'has many leads' do
    person = people(:john_doe_person)
    assert person.respond_to?(:leads)
  end

  test 'has many organizations through leads' do
    person = people(:john_doe_person)
    assert person.respond_to?(:organizations)
  end

  # ============================================================================
  # Timezone Resolution Tests
  # ============================================================================

  test 'resolves timezone when location is set on creation' do
    person = Person.create!(
      email: 'timezone_test@example.com',
      location: 'San Francisco, CA'
    )

    assert_equal 'America/Los_Angeles', person.timezone
    assert_equal 'location', person.timezone_source
    assert_not_nil person.timezone_resolved_at
  end

  test 'resolves timezone when location is updated' do
    person = people(:john_doe_person)
    person.update!(location: 'Berlin, Germany')

    assert_equal 'Europe/Berlin', person.timezone
    assert_equal 'location', person.timezone_source
    assert_not_nil person.timezone_resolved_at
  end

  test 'clears timezone when location is cleared' do
    person = people(:john_doe_person)
    person.update!(location: 'New York', timezone: 'America/New_York', timezone_source: 'location')

    person.update!(location: nil)

    assert_nil person.timezone
    assert_nil person.timezone_source
    assert_nil person.timezone_resolved_at
  end

  test 'keeps existing timezone when location cannot be resolved' do
    person = people(:john_doe_person)
    person.update!(location: 'New York', timezone: 'America/New_York', timezone_source: 'location')

    person.update!(location: 'Unknown Village, Nowhere')

    assert_equal 'America/New_York', person.timezone
  end

  test 'does not resolve timezone when location is not changed' do
    person = people(:john_doe_person)
    person.update!(location: 'New York', timezone: 'America/New_York', timezone_source: 'location')
    original_resolved_at = person.timezone_resolved_at

    person.update!(first_name: 'Updated Name')

    assert_equal original_resolved_at, person.timezone_resolved_at
  end

  test 'resolve_timezone! manually resolves timezone' do
    person = people(:john_doe_person)
    person.update_columns(location: 'Chicago, IL', timezone: nil, timezone_source: nil)

    person.resolve_timezone!

    assert_equal 'America/Chicago', person.timezone
    assert_equal 'location', person.timezone_source
  end

  test 'resolved_timezone returns the cached timezone' do
    person = people(:john_doe_person)
    person.update!(timezone: 'Europe/London')

    assert_equal 'Europe/London', person.resolved_timezone
  end
end
