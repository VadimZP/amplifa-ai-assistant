# frozen_string_literal: true

require 'test_helper'

class EmailDomainTest < ActiveSupport::TestCase
  # Tests cover basic validation (WHY: ensure provider configuration integrity)
  test 'requires organization' do
    email_domain = EmailDomain.new(provider_type: 'google', domain: 'test.com')
    assert_not email_domain.valid?
    assert_includes email_domain.errors[:organization], 'must exist'
  end

  test 'requires provider_type' do
    email_domain = EmailDomain.new(organization: organizations(:acme), domain: 'test.com')
    assert_not email_domain.valid?
    assert_includes email_domain.errors[:provider_type], "can't be blank"
  end

  test 'requires domain' do
    email_domain = EmailDomain.new(organization: organizations(:acme), provider_type: 'google')
    assert_not email_domain.valid?
    assert_includes email_domain.errors[:domain], "can't be blank"
  end

  test 'validates provider_type inclusion' do
    email_domain = EmailDomain.new(
      organization: organizations(:acme),
      provider_type: 'invalid',
      domain: 'test.com'
    )
    assert_not email_domain.valid?
    assert_includes email_domain.errors[:provider_type], 'is not included in the list'
  end

  test 'validates status inclusion' do
    email_domain = email_domains(:acme_google)
    email_domain.status = 'invalid'
    assert_not email_domain.valid?
    assert_includes email_domain.errors[:status], 'is not included in the list'
  end

  # Tests cover Microsoft-specific validation (WHY: Microsoft requires tenant ID)
  test 'requires microsoft_tenant_id for microsoft provider' do
    email_domain = EmailDomain.new(
      organization: organizations(:acme),
      provider_type: 'microsoft',
      domain: 'test.com',
      microsoft_tenant_id: nil
    )
    assert_not email_domain.valid?
    assert_includes email_domain.errors[:microsoft_tenant_id], "can't be blank"
  end

  test 'does not require microsoft_tenant_id for google provider' do
    email_domain = EmailDomain.new(
      organization: organizations(:acme),
      provider_type: 'google',
      domain: 'newdomain.com',
      microsoft_tenant_id: nil
    )
    assert email_domain.valid?
  end

  # Tests cover uniqueness (WHY: prevent duplicate domain configurations per org)
  test 'prevents duplicate domain in same organization' do
    existing = email_domains(:acme_google)
    duplicate = EmailDomain.new(
      organization: existing.organization,
      provider_type: 'google',
      domain: existing.domain
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:domain], 'The domain already exists in the current organization.'
  end

  test 'prevents duplicate domain in different organizations' do
    duplicate = EmailDomain.new(
      organization: organizations(:beta),
      provider_type: 'google',
      domain: email_domains(:acme_google).domain
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:domain],
                    'The domain already exists in another organization, <b>Acme Corporation</b>.'
  end

  test 'allows domain reuse after soft deletion' do
    organization = organizations(:acme)
    deleted_domain = EmailDomain.create!(
      organization: organization,
      provider_type: 'google',
      domain: 'reusable-domain.com',
      status: 'deleted'
    )

    replacement = EmailDomain.new(
      organization: organization,
      provider_type: 'google',
      domain: deleted_domain.domain,
      status: 'active'
    )

    assert replacement.valid?
  end

  # Tests cover provider type predicates (WHY: convenient type checking in code)
  test 'google? returns true for google provider' do
    email_domain = email_domains(:acme_google)
    assert email_domain.google?
    assert_not email_domain.microsoft?
  end

  test 'microsoft? returns true for microsoft provider' do
    email_domain = email_domains(:beta_microsoft)
    assert email_domain.microsoft?
    assert_not email_domain.google?
  end

  # Tests cover status predicates (WHY: convenient status checking)
  test 'status predicates work correctly' do
    assert email_domains(:acme_google).active?
    assert email_domains(:inactive_domain).inactive?
    assert email_domains(:error_domain).error?
  end

  # Tests cover domain matching (WHY: used to validate mailbox emails)
  test 'domain_for_email? matches correct domain' do
    email_domain = email_domains(:acme_google)
    assert email_domain.domain_for_email?('user@acme.com')
    assert email_domain.domain_for_email?('USER@ACME.COM') # case insensitive
    assert_not email_domain.domain_for_email?('user@other.com')
    assert_not email_domain.domain_for_email?(nil)
    assert_not email_domain.domain_for_email?('')
  end

  # Tests cover verification methods (WHY: track provider health status)
  test 'mark_verified! updates status and timestamp' do
    email_domain = email_domains(:error_domain)
    email_domain.mark_verified!

    assert email_domain.active?
    assert_not_nil email_domain.last_verified_at
    assert_nil email_domain.verification_error
  end

  test 'mark_verification_error! records the error' do
    email_domain = email_domains(:acme_google)
    email_domain.mark_verification_error!('Connection failed')

    assert email_domain.error?
    assert_equal 'Connection failed', email_domain.verification_error
  end

  # Tests cover scopes (WHY: efficient filtering for queries)
  test 'google scope returns only google providers' do
    results = EmailDomain.google
    assert results.all?(&:google?)
    assert_not results.any?(&:microsoft?)
  end

  test 'microsoft scope returns only microsoft providers' do
    results = EmailDomain.microsoft
    assert results.all?(&:microsoft?)
    assert_not results.any?(&:google?)
  end

  test 'active scope returns only active providers' do
    results = EmailDomain.active
    assert results.all?(&:active?)
  end

  test 'for_organization scope filters by organization' do
    results = EmailDomain.for_organization(organizations(:acme))
    assert(results.all? { |p| p.organization_id == organizations(:acme).id })
  end

  # Tests cover associations (WHY: ensure relationships work)
  test 'belongs to organization' do
    email_domain = email_domains(:acme_google)
    assert_equal organizations(:acme), email_domain.organization
  end

  test 'has many mailboxes' do
    email_domain = email_domains(:acme_google)
    assert_respond_to email_domain, :mailboxes
    assert email_domain.mailboxes.count > 0
  end
end
