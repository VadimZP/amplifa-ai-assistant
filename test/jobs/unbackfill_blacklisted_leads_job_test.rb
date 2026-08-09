# frozen_string_literal: true

require 'test_helper'

class UnbackfillBlacklistedLeadsJobTest < ActiveJob::TestCase
  setup do
    @org = organizations(:acme)
    @admin = accounts(:customer_admin)
  end

  test 'unblacklists lead when removed email entry was the only remaining match' do
    lead = leads(:john_doe)
    blacklist = Blacklist.create!(
      organization: @org,
      created_by: @admin,
      value: lead.email,
      value_type: 'email',
      source: 'manual',
      reason: 'Do not contact'
    )

    lead.blacklist!(reason: 'Do not contact')

    blacklist.destroy!

    UnbackfillBlacklistedLeadsJob.perform_now(
      organization_id: @org.id,
      value: lead.email,
      value_type: 'email'
    )

    lead.reload
    assert_not lead.blacklisted?
    assert_nil lead.blacklist_reason
    assert_nil lead.blacklist_reason_category
    assert_nil lead.blacklisted_at
  end

  test 'unblacklists leads across organizations when removed entry was global' do
    acme_lead = leads(:john_doe)
    beta_lead = leads(:beta_lead)
    shared_domain = 'global-unbackfill.example'

    acme_lead.update!(email: "alice@#{shared_domain}")
    beta_lead.update!(email: "bob@#{shared_domain}")

    blacklist = Blacklist.create!(
      organization: nil,
      created_by: accounts(:amplifa_admin),
      value: shared_domain,
      value_type: 'domain',
      source: 'manual',
      reason: 'Global block'
    )

    acme_lead.blacklist!(reason: 'Global block')
    beta_lead.blacklist!(reason: 'Global block')

    blacklist.destroy!

    UnbackfillBlacklistedLeadsJob.perform_now(
      organization_id: nil,
      value: shared_domain,
      value_type: 'domain'
    )

    assert_not acme_lead.reload.blacklisted?
    assert_not beta_lead.reload.blacklisted?
  end

  test 'keeps lead blacklisted and refreshes reason when another entry still matches' do
    lead = leads(:john_doe)
    lead.update!(email: 'alice@overlap.example')

    global_blacklist = Blacklist.create!(
      organization: nil,
      created_by: accounts(:amplifa_admin),
      value: 'overlap.example',
      value_type: 'domain',
      source: 'manual',
      reason: 'Global fallback block'
    )

    org_blacklist = Blacklist.create!(
      organization: @org,
      created_by: @admin,
      value: 'overlap.example',
      value_type: 'domain',
      source: 'manual',
      reason: 'Organization-specific block'
    )

    lead.blacklist!(reason: 'Organization-specific block')

    org_blacklist.destroy!

    UnbackfillBlacklistedLeadsJob.perform_now(
      organization_id: @org.id,
      value: 'overlap.example',
      value_type: 'domain'
    )

    lead.reload
    assert lead.blacklisted?
    assert_equal 'Global fallback block', lead.blacklist_reason
    assert_equal 'other', lead.blacklist_reason_category

    global_blacklist.destroy!
  end

  test 'unblacklists lead even when its email changes before entry removal' do
    lead = leads(:john_doe)
    original_email = lead.email
    blacklist = Blacklist.create!(
      organization: @org,
      created_by: @admin,
      value: original_email,
      value_type: 'email',
      source: 'manual',
      reason: 'Original email block'
    )

    lead.blacklist!(reason: 'Original email block')
    lead.update!(email: 'changed-address@example.com')

    blacklist.destroy!

    UnbackfillBlacklistedLeadsJob.perform_now(
      organization_id: @org.id,
      value: original_email,
      value_type: 'email'
    )

    lead.reload
    assert_not lead.blacklisted?
    assert_nil lead.blacklist_reason
    assert_nil lead.blacklist_reason_category
  end

  test 'refreshes to deterministic same-scope reason when multiple entries remain' do
    lead = leads(:john_doe)
    lead.update!(email: 'alice@samepriority.example')

    exact_domain_blacklist = Blacklist.create!(
      organization: @org,
      created_by: @admin,
      value: 'samepriority.example',
      value_type: 'domain',
      source: 'manual',
      reason: 'Exact domain block'
    )

    wildcard_domain_blacklist = Blacklist.create!(
      organization: @org,
      created_by: @admin,
      value: 'samepriority.*',
      value_type: 'domain',
      source: 'manual',
      reason: 'Wildcard domain block'
    )

    email_blacklist = Blacklist.create!(
      organization: @org,
      created_by: @admin,
      value: lead.email,
      value_type: 'email',
      source: 'manual',
      reason: 'Specific email block'
    )

    lead.blacklist!(reason: 'Specific email block')

    email_blacklist.destroy!

    UnbackfillBlacklistedLeadsJob.perform_now(
      organization_id: @org.id,
      value: lead.email,
      value_type: 'email'
    )

    lead.reload
    assert lead.blacklisted?
    assert_equal 'Exact domain block', lead.blacklist_reason
    assert_equal 'other', lead.blacklist_reason_category

    exact_domain_blacklist.destroy!
    wildcard_domain_blacklist.destroy!
  end

  test 'destroying a blacklist entry enqueues the unbackfill job' do
    blacklist = Blacklist.create!(
      organization: @org,
      created_by: @admin,
      value: 'enqueue-unbackfill@example.com',
      value_type: 'email',
      source: 'manual'
    )

    clear_enqueued_jobs

    assert_enqueued_with(job: UnbackfillBlacklistedLeadsJob,
                         args: [{ organization_id: @org.id, value: 'enqueue-unbackfill@example.com',
                                  value_type: 'email' }]) do
      blacklist.destroy!
    end
  end
end
