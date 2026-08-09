# frozen_string_literal: true

require 'test_helper'

class BlacklistTest < ActiveSupport::TestCase
  # Tests cover basic validation (WHY: ensure blacklist entries are valid)
  test 'requires value' do
    blacklist = Blacklist.new(created_by: accounts(:amplifa_admin), value_type: 'email', source: 'manual')
    assert_not blacklist.valid?
    assert_includes blacklist.errors[:value], "can't be blank"
  end

  test 'requires value_type' do
    blacklist = Blacklist.new(created_by: accounts(:amplifa_admin), value: 'test@test.com', source: 'manual')
    assert_not blacklist.valid?
    assert_includes blacklist.errors[:value_type], "can't be blank"
  end

  test 'requires source' do
    blacklist = Blacklist.new(created_by: accounts(:amplifa_admin), value: 'test@test.com', value_type: 'email')
    assert_not blacklist.valid?
    assert_includes blacklist.errors[:source], "can't be blank"
  end

  # Tests cover value_type validation (WHY: only email and domain are valid types)
  test 'validates value_type inclusion' do
    blacklist = Blacklist.new(created_by: accounts(:amplifa_admin), value: 'test@test.com', value_type: 'invalid',
                              source: 'manual')
    assert_not blacklist.valid?
    assert_includes blacklist.errors[:value_type], 'is not included in the list'
  end

  test 'allows email and domain value types' do
    %w[email domain].each do |type|
      blacklist = Blacklist.new(
        created_by: accounts(:amplifa_admin),
        value: type == 'email' ? 'test@example.com' : 'example.com',
        value_type: type,
        source: 'manual'
      )
      assert blacklist.valid?, "Expected value_type '#{type}' to be valid"
    end
  end

  # Tests cover source validation (WHY: track how blacklist entry was created)
  test 'validates source inclusion' do
    blacklist = Blacklist.new(created_by: accounts(:amplifa_admin), value: 'test@test.com', value_type: 'email',
                              source: 'invalid')
    assert_not blacklist.valid?
    assert_includes blacklist.errors[:source], 'is not included in the list'
  end

  test 'allows valid sources' do
    %w[manual import unsubscribe interested].each do |source|
      blacklist = Blacklist.new(created_by: accounts(:amplifa_admin), value: "unique-#{source}@example.com",
                                value_type: 'email', source: source)
      assert blacklist.valid?, "Expected source '#{source}' to be valid"
    end
  end

  test 'upsert_reply_interest_entry updates existing mixed case email entry' do
    lead = leads(:john_doe)
    existing = Blacklist.create!(
      organization: lead.organization,
      created_by: accounts(:customer_admin),
      value: 'John.Doe@Example.com',
      value_type: 'email',
      source: 'manual',
      reason: 'Original reason'
    )

    assert_no_difference 'Blacklist.count' do
      Blacklist.upsert_reply_interest_entry!(
        lead: lead,
        interest_status: 'interested',
        actor: accounts(:amplifa_admin)
      )
    end

    existing.reload
    assert_equal 'John.Doe@Example.com', existing.value
    assert_equal 'interested', existing.source
    assert_equal 'Auto-blacklisted from reply interest tag: Interested', existing.reason
    assert_equal 'reply_interested', existing.reason_category
  end

  test 'upsert_reply_interest_entry stores manual reason when provided' do
    lead = leads(:john_doe)

    Blacklist.upsert_reply_interest_entry!(
      lead: lead,
      interest_status: 'not_interested',
      actor: accounts(:customer_admin),
      reason: Blacklist.reply_interest_reason('not_interested', manual: true)
    )

    entry = Blacklist.find_by!(organization: lead.organization, value_type: 'email', value: lead.email)
    assert_equal 'unsubscribe', entry.source
    assert_equal 'Auto-blacklisted from manually set interest tag: Not interested', entry.reason
    assert_equal 'reply_not_interested', entry.reason_category
  end

  test 'upsert_reply_interest_email_entry creates entry for arbitrary email' do
    organization = organizations(:acme)

    Blacklist.upsert_reply_interest_email_entry!(
      organization: organization,
      email: ' Assistant@Other-Domain.example ',
      interest_status: 'wrong_person',
      actor: accounts(:customer_admin)
    )

    entry = Blacklist.find_by!(organization: organization, value_type: 'email', value: 'assistant@other-domain.example')
    assert_equal 'unsubscribe', entry.source
    assert_equal 'Auto-blacklisted from reply interest tag: Wrong person', entry.reason
    assert_equal 'reply_wrong_person', entry.reason_category
  end

  test 'reason_category_for_reason does not infer reply categories for manual sources' do
    assert_equal 'other', Blacklist.reason_category_for_reason(
      Blacklist.reply_interest_reason('interested'),
      source: 'manual'
    )
  end

  test 'reason_category_for_reason infers manual interested copy when source is interested' do
    assert_equal 'reply_interested', Blacklist.reason_category_for_reason(
      Blacklist.reply_interest_reason('interested', manual: true),
      source: 'interested'
    )
  end

  # Tests cover value format validation (WHY: ensure proper email/domain format)
  test 'validates email format for email type' do
    blacklist = Blacklist.new(created_by: accounts(:amplifa_admin), value: 'not-an-email', value_type: 'email',
                              source: 'manual')
    assert_not blacklist.valid?
    assert_includes blacklist.errors[:value], 'must be a valid email address'
  end

  test 'accepts valid email for email type' do
    blacklist = Blacklist.new(created_by: accounts(:amplifa_admin), value: 'valid@example.com', value_type: 'email',
                              source: 'manual')
    assert blacklist.valid?
  end

  test 'validates domain format for domain type' do
    blacklist = Blacklist.new(created_by: accounts(:amplifa_admin), value: 'not a domain!', value_type: 'domain',
                              source: 'manual')
    assert_not blacklist.valid?
    assert_includes blacklist.errors[:value], 'must be a valid domain'
  end

  test 'accepts valid domain for domain type' do
    blacklist = Blacklist.new(created_by: accounts(:amplifa_admin), value: 'example.com', value_type: 'domain',
                              source: 'manual')
    assert blacklist.valid?
  end

  test 'accepts subdomain for domain type' do
    blacklist = Blacklist.new(created_by: accounts(:amplifa_admin), value: 'mail.example.com', value_type: 'domain',
                              source: 'manual')
    assert blacklist.valid?
  end

  test 'accepts wildcard domain for domain type' do
    blacklist = Blacklist.new(created_by: accounts(:amplifa_admin), value: 'kienbaum.*', value_type: 'domain',
                              source: 'manual')
    assert blacklist.valid?
  end

  test 'accepts leading wildcard subdomain for domain type' do
    blacklist = Blacklist.new(created_by: accounts(:amplifa_admin), value: '*.example.com', value_type: 'domain',
                              source: 'manual')
    assert blacklist.valid?
  end

  test 'rejects leading wildcard apex domain for domain type' do
    blacklist = Blacklist.new(created_by: accounts(:amplifa_admin), value: '*.com', value_type: 'domain',
                              source: 'manual')
    assert_not blacklist.valid?
    assert_includes blacklist.errors[:value], 'must be a valid domain'
  end

  # Tests cover uniqueness (WHY: prevent duplicate blacklist entries)
  test 'prevents duplicate value for same org and type' do
    existing = blacklists(:acme_email_blacklist)
    duplicate = Blacklist.new(
      organization: existing.organization,
      created_by: accounts(:customer_admin),
      value: existing.value,
      value_type: existing.value_type,
      source: 'manual'
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:value], 'is already blacklisted'
  end

  test 'allows same value in different organizations' do
    # WHY: Org-specific blacklists are independent
    blacklist = Blacklist.new(
      organization: organizations(:beta),
      created_by: accounts(:beta_user),
      value: blacklists(:acme_email_blacklist).value,
      value_type: 'email',
      source: 'manual'
    )
    assert blacklist.valid?
  end

  # Tests cover global? method (WHY: distinguish global vs org-specific entries)
  test 'global? returns true for entries without organization' do
    assert blacklists(:global_email).global?
  end

  test 'global? returns false for org-specific entries' do
    assert_not blacklists(:acme_email_blacklist).global?
  end

  # Tests cover blacklisted? class method (WHY: primary lookup for checking email eligibility)
  test 'blacklisted? returns true for global email match' do
    assert Blacklist.blacklisted?(email: 'spam@global-blocked.com', organization: organizations(:acme))
  end

  test 'blacklisted? returns true for global domain match' do
    assert Blacklist.blacklisted?(email: 'anyone@spam-domain.com', organization: organizations(:acme))
  end

  test 'blacklisted? returns true for org-specific email match' do
    assert Blacklist.blacklisted?(email: 'competitor@rival.com', organization: organizations(:acme))
  end

  test 'blacklisted? returns true for org-specific domain match' do
    assert Blacklist.blacklisted?(email: 'anyone@blocked.com', organization: organizations(:acme))
  end

  test 'blacklisted? returns true for company website domain match' do
    assert Blacklist.blacklisted?(
      email: 'anyone@allowed.ch',
      organization: organizations(:acme),
      company_website: 'https://www.blocked.com/about'
    )
  end

  test 'blacklisted? returns true for wildcard email domain match' do
    Blacklist.create!(
      organization: organizations(:acme),
      created_by: accounts(:customer_admin),
      value: 'kienbaum.*',
      value_type: 'domain',
      source: 'manual',
      reason: 'Wildcard domain match'
    )

    assert Blacklist.blacklisted?(email: 'anyone@kienbaum.de', organization: organizations(:acme))
    assert Blacklist.blacklisted?(email: 'anyone@kienbaum.ch', organization: organizations(:acme))
  end

  test 'blacklisted? wildcard domain match preserves broad star semantics' do
    Blacklist.create!(
      organization: organizations(:acme),
      created_by: accounts(:customer_admin),
      value: '*.wildcard-example.com',
      value_type: 'domain',
      source: 'manual',
      reason: 'Wildcard subdomain match'
    )

    assert Blacklist.blacklisted?(email: 'anyone@a.b.wildcard-example.com', organization: organizations(:acme))
    assert_not Blacklist.blacklisted?(email: 'anyone@wildcard-example.com', organization: organizations(:acme))
  end

  test 'blacklisted? returns true for wildcard company website domain match' do
    Blacklist.create!(
      organization: organizations(:acme),
      created_by: accounts(:customer_admin),
      value: 'kienbaum.*',
      value_type: 'domain',
      source: 'manual',
      reason: 'Wildcard website domain match'
    )

    assert Blacklist.blacklisted?(
      email: 'safe@allowed.ch',
      organization: organizations(:acme),
      company_website: 'https://www.kienbaum.de/about'
    )
  end

  test 'blacklisted? returns false for non-blacklisted email' do
    assert_not Blacklist.blacklisted?(email: 'safe@allowed.com', organization: organizations(:acme))
  end

  test 'blacklisted? returns false for blank email' do
    assert_not Blacklist.blacklisted?(email: '', organization: organizations(:acme))
    assert_not Blacklist.blacklisted?(email: nil, organization: organizations(:acme))
  end

  test 'blacklisted? handles email case insensitively' do
    # WHY: Email matching should be case-insensitive
    assert Blacklist.blacklisted?(email: 'SPAM@GLOBAL-BLOCKED.COM', organization: organizations(:acme))
  end

  test 'blacklisted? checks org blacklist but not other orgs' do
    # WHY: Org blacklists should not affect other orgs
    assert_not Blacklist.blacklisted?(email: 'competitor@rival.com', organization: organizations(:beta))
  end

  # Tests cover blacklist_reason class method (WHY: provide explanation for UI)
  test 'blacklist_reason returns custom reason when present' do
    reason = Blacklist.blacklist_reason(email: 'spam@global-blocked.com', organization: organizations(:acme))
    assert_equal 'Known spam sender', reason
  end

  test 'blacklist_reason returns default message for global email without reason' do
    # Create a global entry without reason
    Blacklist.create!(created_by: accounts(:amplifa_admin), value: 'no-reason@example.com', value_type: 'email',
                      source: 'manual')
    reason = Blacklist.blacklist_reason(email: 'no-reason@example.com', organization: organizations(:acme))
    assert_equal 'Email address on global blacklist', reason
  end

  test 'blacklist_reason returns default message for global domain' do
    reason = Blacklist.blacklist_reason(email: 'test@spam-domain.com', organization: organizations(:acme))
    assert_equal 'Known spam domain', reason
  end

  test 'blacklist_reason returns company website domain reason' do
    Blacklist.create!(
      organization: organizations(:acme),
      created_by: accounts(:customer_admin),
      value: 'domainreason.com',
      value_type: 'domain',
      source: 'manual'
    )

    reason = Blacklist.blacklist_reason(
      email: 'safe@allowed.ch',
      organization: organizations(:acme),
      company_website: 'domainreason.com'
    )
    assert_equal 'Email domain on organization blacklist', reason
  end

  test 'blacklist_reason returns wildcard domain reason' do
    Blacklist.create!(
      organization: organizations(:acme),
      created_by: accounts(:customer_admin),
      value: 'kienbaum.*',
      value_type: 'domain',
      source: 'manual',
      reason: 'Wildcard domain reason'
    )

    reason = Blacklist.blacklist_reason(email: 'safe@kienbaum.de', organization: organizations(:acme))
    assert_equal 'Wildcard domain reason', reason
  end

  test 'blacklist_reason returns nil for non-blacklisted email' do
    assert_nil Blacklist.blacklist_reason(email: 'not-blocked@example.com', organization: organizations(:acme))
  end

  test 'blacklist_reason prefers org-specific over global' do
    # Create matching global and org entries
    Blacklist.create!(created_by: accounts(:amplifa_admin), value: 'dual@example.com', value_type: 'email',
                      source: 'manual', reason: 'Global reason')
    Blacklist.create!(organization: organizations(:acme), created_by: accounts(:customer_admin),
                      value: 'dual@example.com', value_type: 'email', source: 'manual', reason: 'Org reason')

    reason = Blacklist.blacklist_reason(email: 'dual@example.com', organization: organizations(:acme))
    assert_equal 'Org reason', reason
  end

  # Tests cover scopes (WHY: efficient filtering for admin views)
  test 'global scope returns only global entries' do
    results = Blacklist.global
    assert_includes results, blacklists(:global_email)
    assert_not_includes results, blacklists(:acme_email_blacklist)
  end

  test 'for_organization scope returns org entries' do
    results = Blacklist.for_organization(organizations(:acme))
    assert_includes results, blacklists(:acme_email_blacklist)
    assert_not_includes results, blacklists(:beta_unsubscribe)
  end

  test 'emails scope returns only email type' do
    results = Blacklist.emails
    assert_includes results, blacklists(:global_email)
    assert_not_includes results, blacklists(:global_domain)
  end

  test 'domains scope returns only domain type' do
    results = Blacklist.domains
    assert_includes results, blacklists(:global_domain)
    assert_not_includes results, blacklists(:global_email)
  end

  # Tests cover associations (WHY: verify model relationships)
  test 'belongs to organization optionally' do
    assert_nil blacklists(:global_email).organization
    assert_equal organizations(:acme), blacklists(:acme_email_blacklist).organization
  end

  test 'belongs to created_by' do
    assert_equal accounts(:amplifa_admin), blacklists(:global_email).created_by
  end
end
