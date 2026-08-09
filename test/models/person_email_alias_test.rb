# frozen_string_literal: true

require 'test_helper'

class PersonEmailAliasTest < ActiveSupport::TestCase
  # Tests cover basic validation (WHY: aliases must be valid, normalized, and uniquely tied to one canonical person)
  test 'requires person' do
    alias_record = PersonEmailAlias.new(email: 'alias@example.com')
    assert_not alias_record.valid?
    assert_includes alias_record.errors[:person], 'must exist'
  end

  test 'requires email' do
    alias_record = PersonEmailAlias.new(person: people(:john_doe_person))
    assert_not alias_record.valid?
    assert_includes alias_record.errors[:email], "can't be blank"
  end

  test 'normalizes email before validation' do
    alias_record = PersonEmailAlias.new(person: people(:john_doe_person), email: '  Alias@Other.com  ')
    alias_record.valid?

    assert_equal 'alias@other.com', alias_record.email
  end

  test 'prevents duplicate alias email globally' do
    existing = PersonEmailAlias.create!(person: people(:john_doe_person), email: 'alias@other.com')
    duplicate = PersonEmailAlias.new(person: people(:jane_smith_person), email: existing.email.upcase)

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:email], 'has already been taken'
  end

  test 'prevents alias from matching person primary email' do
    person = people(:john_doe_person)
    alias_record = PersonEmailAlias.new(person: person, email: person.email)

    assert_not alias_record.valid?
    assert_includes alias_record.errors[:email], 'must differ from the person primary email'
  end

  test 'prevents alias from matching another person primary email' do
    alias_record = PersonEmailAlias.new(person: people(:john_doe_person), email: people(:jane_smith_person).email)

    assert_not alias_record.valid?
    assert_includes alias_record.errors[:email], 'is already used as a person primary email'
  end
end
