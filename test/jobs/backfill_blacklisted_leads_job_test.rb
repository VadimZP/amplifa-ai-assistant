# frozen_string_literal: true

require 'test_helper'

class BackfillBlacklistedLeadsJobTest < ActiveJob::TestCase
  setup do
    @org = organizations(:acme)
    @admin = accounts(:customer_admin)
  end

  test 'marks lead as blacklisted when email matches' do
    lead = leads(:john_doe)
    assert_not lead.blacklisted?

    blacklist = Blacklist.create!(
      organization: @org,
      created_by: @admin,
      value: lead.email,
      value_type: 'email',
      source: 'manual',
      reason: 'Testing email blacklist'
    )

    BackfillBlacklistedLeadsJob.perform_now(blacklist.id)

    lead.reload
    assert lead.blacklisted?
    assert_equal 'Testing email blacklist', lead.blacklist_reason
    assert_equal 'other', lead.blacklist_reason_category
    assert_not_nil lead.blacklisted_at
  end

  test 'marks leads as blacklisted when domain matches' do
    lead = leads(:john_doe)
    domain = lead.email.split('@').last
    assert_not lead.blacklisted?

    blacklist = Blacklist.create!(
      organization: @org,
      created_by: @admin,
      value: domain,
      value_type: 'domain',
      source: 'manual',
      reason: 'Testing domain blacklist'
    )

    BackfillBlacklistedLeadsJob.perform_now(blacklist.id)

    lead.reload
    assert lead.blacklisted?
    assert_equal 'Testing domain blacklist', lead.blacklist_reason
  end

  test 'marks leads as blacklisted when company website domain matches' do
    lead = leads(:john_doe)
    lead.update!(email: 'alice@different-domain.ch', company_website: 'https://www.freshblocked.com/team')

    blacklist = Blacklist.create!(
      organization: @org,
      created_by: @admin,
      value: 'freshblocked.com',
      value_type: 'domain',
      source: 'manual',
      reason: 'Testing company website domain blacklist'
    )

    BackfillBlacklistedLeadsJob.perform_now(blacklist.id)

    lead.reload
    assert lead.blacklisted?
    assert_equal 'Testing company website domain blacklist', lead.blacklist_reason
  end

  test 'marks leads as blacklisted when wildcard domain matches email or company website' do
    email_domain_lead = leads(:john_doe)
    website_domain_lead = leads(:jane_smith)

    email_domain_lead.update!(email: 'alice@kienbaum.de', company_website: 'https://www.allowed.com')
    website_domain_lead.update!(email: 'jane@allowed.ch', company_website: 'https://www.kienbaum.ch/team')

    blacklist = Blacklist.create!(
      organization: @org,
      created_by: @admin,
      value: 'kienbaum.*',
      value_type: 'domain',
      source: 'manual',
      reason: 'Testing wildcard domain blacklist'
    )

    BackfillBlacklistedLeadsJob.perform_now(blacklist.id)

    assert email_domain_lead.reload.blacklisted?
    assert website_domain_lead.reload.blacklisted?
    assert_equal 'Testing wildcard domain blacklist', email_domain_lead.blacklist_reason
    assert_equal 'Testing wildcard domain blacklist', website_domain_lead.blacklist_reason
  end

  test 'skips already blacklisted leads' do
    lead = leads(:blacklisted_lead)
    original_reason = lead.blacklist_reason
    assert lead.blacklisted?

    blacklist = Blacklist.create!(
      organization: @org,
      created_by: @admin,
      value: lead.email,
      value_type: 'email',
      source: 'manual',
      reason: 'New reason'
    )

    BackfillBlacklistedLeadsJob.perform_now(blacklist.id)

    lead.reload
    assert_equal original_reason, lead.blacklist_reason
  end

  test 'global blacklist marks leads across all organizations' do
    acme_lead = leads(:john_doe)
    beta_lead = leads(:beta_lead)
    shared_domain = 'cross-org-test.com'
    acme_lead.update!(email: "alice@#{shared_domain}")
    beta_lead.update!(email: "bob@#{shared_domain}")

    blacklist = Blacklist.create!(
      organization: nil,
      created_by: accounts(:amplifa_admin),
      value: shared_domain,
      value_type: 'domain',
      source: 'manual',
      reason: 'Global domain ban'
    )

    BackfillBlacklistedLeadsJob.perform_now(blacklist.id)

    assert acme_lead.reload.blacklisted?
    assert beta_lead.reload.blacklisted?
  end

  test 'org-specific blacklist only marks leads in that organization' do
    acme_lead = leads(:john_doe)
    beta_lead = leads(:beta_lead)
    shared_domain = 'shared-test.com'
    acme_lead.update!(email: "alice@#{shared_domain}")
    beta_lead.update!(email: "bob@#{shared_domain}")

    blacklist = Blacklist.create!(
      organization: @org,
      created_by: @admin,
      value: shared_domain,
      value_type: 'domain',
      source: 'manual',
      reason: 'Org-specific ban'
    )

    BackfillBlacklistedLeadsJob.perform_now(blacklist.id)

    assert acme_lead.reload.blacklisted?
    assert_not beta_lead.reload.blacklisted?
  end

  test 'uses default reason when blacklist entry has no reason' do
    lead = leads(:john_doe)

    blacklist = Blacklist.create!(
      organization: @org,
      created_by: @admin,
      value: lead.email,
      value_type: 'email',
      source: 'manual'
    )

    BackfillBlacklistedLeadsJob.perform_now(blacklist.id)

    lead.reload
    assert lead.blacklisted?
    assert_equal 'Email address on organization blacklist', lead.blacklist_reason
    assert_equal 'other', lead.blacklist_reason_category
  end

  test 'discards gracefully when blacklist entry is deleted' do
    assert_nothing_raised do
      BackfillBlacklistedLeadsJob.perform_now(-1)
    end
  end

  test 'creating a blacklist entry enqueues the backfill job' do
    assert_enqueued_with(job: BackfillBlacklistedLeadsJob) do
      Blacklist.create!(
        organization: @org,
        created_by: @admin,
        value: 'enqueue-test@example.com',
        value_type: 'email',
        source: 'manual'
      )
    end
  end
end
