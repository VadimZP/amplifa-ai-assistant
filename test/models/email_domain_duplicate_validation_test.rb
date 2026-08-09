# frozen_string_literal: true

require 'test_helper'

class EmailDomainDuplicateValidationTest < ActiveSupport::TestCase
  test 'prevents duplicate domain in same organization with exact message' do
    duplicate = EmailDomain.new(
      organization: organizations(:acme),
      provider_type: 'google',
      domain: email_domains(:acme_google).domain
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:domain], 'The domain already exists in the current organization.'
  end

  test 'prevents duplicate domain in another organization with org name message' do
    duplicate = EmailDomain.new(
      organization: organizations(:beta),
      provider_type: 'google',
      domain: email_domains(:acme_google).domain
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:domain],
                    'The domain already exists in another organization, <b>Acme Corporation</b>.'
  end

  test 'normalizes domain and prevents case-insensitive duplicates' do
    duplicate = EmailDomain.new(
      organization: organizations(:beta),
      provider_type: 'google',
      domain: '  ACME.COM  '
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:domain],
                    'The domain already exists in another organization, <b>Acme Corporation</b>.'
  end
end
