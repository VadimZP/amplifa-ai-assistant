require 'test_helper'

class AccountTest < ActiveSupport::TestCase
  # Why: We need to ensure the Account model has proper validation rules for all required fields
  # and that the new role system works correctly with organization associations

  def setup
    @organization = organizations(:acme)
    @amplifa_admin = accounts(:amplifa_admin)
    @customer_admin = accounts(:customer_admin)
    @customer_user = accounts(:customer_user)
  end

  # Email validation tests
  # Why: Email is the primary identifier for accounts and must be valid and unique
  test 'should require email to be present' do
    account = Account.new(
      first_name: 'Test',
      last_name: 'User',
      role: 'customer_user',
      organization: @organization
    )
    refute account.valid?
    assert_includes account.errors[:email], "can't be blank"
  end

  test 'should require email to be unique' do
    existing_email = @customer_admin.email
    account = Account.new(
      email: existing_email,
      first_name: 'Test',
      last_name: 'User',
      role: 'customer_user',
      organization: @organization
    )
    refute account.valid?
  end

  # Name validation tests
  # Why: Names are required for identifying users in the UI and emails
  test 'should require first_name to be present' do
    account = Account.new(
      email: 'test@example.com',
      last_name: 'User',
      role: 'customer_user',
      organization: @organization
    )
    refute account.valid?
    assert_includes account.errors[:first_name], "can't be blank"
  end

  test 'should require last_name to be present' do
    account = Account.new(
      email: 'test@example.com',
      first_name: 'Test',
      role: 'customer_user',
      organization: @organization
    )
    refute account.valid?
    assert_includes account.errors[:last_name], "can't be blank"
  end

  test 'should validate first_name length' do
    account = Account.new(
      email: 'test@example.com',
      first_name: 'a' * 51,
      last_name: 'User',
      role: 'customer_user',
      organization: @organization
    )
    refute account.valid?
    assert_includes account.errors[:first_name], 'is too long (maximum is 50 characters)'
  end

  test 'should validate last_name length' do
    account = Account.new(
      email: 'test@example.com',
      first_name: 'Test',
      last_name: 'a' * 51,
      role: 'customer_user',
      organization: @organization
    )
    refute account.valid?
    assert_includes account.errors[:last_name], 'is too long (maximum is 50 characters)'
  end

  # Role validation tests
  # Why: The role system is critical for authorization throughout the app
  test 'should require role to be in valid list' do
    account = Account.new(
      email: 'test@example.com',
      first_name: 'Test',
      last_name: 'User',
      role: 'invalid_role',
      organization: @organization
    )
    refute account.valid?
    assert_includes account.errors[:role], 'is not included in the list'
  end

  test 'should accept amplifa_admin role' do
    Account.new(
      email: 'test@example.com',
      first_name: 'Test',
      last_name: 'User',
      role: 'amplifa_admin'
    )
    assert_includes Account::ROLES, 'amplifa_admin'
  end

  test 'should accept customer_admin role' do
    Account.new(
      email: 'test@example.com',
      first_name: 'Test',
      last_name: 'User',
      role: 'customer_admin',
      organization: @organization
    )
    assert_includes Account::ROLES, 'customer_admin'
  end

  test 'should accept customer_user role' do
    Account.new(
      email: 'test@example.com',
      first_name: 'Test',
      last_name: 'User',
      role: 'customer_user',
      organization: @organization
    )
    assert_includes Account::ROLES, 'customer_user'
  end

  test 'can belong to multiple organizations through memberships' do
    OrganizationMembership.create!(
      account: @customer_user,
      organization: organizations(:growth_lab),
      role: 'customer_user',
      status: 'active'
    )

    assert_includes @customer_user.organizations, organizations(:acme)
    assert_includes @customer_user.organizations, organizations(:growth_lab)
  end

  test 'creates primary organization membership for new customer accounts' do
    account = Account.create!(
      email: 'primary-membership@example.com',
      first_name: 'Primary',
      last_name: 'Member',
      role: 'customer_admin',
      organization: @organization,
      status: :verified,
      password_hash: RodauthApp.rodauth.allocate.password_hash('password')
    )

    membership = account.organization_memberships.find_by!(organization: @organization)
    assert_equal 'customer_admin', membership.role
    assert membership.active?
  end

  # Organization validation tests
  # Why: Customer roles must belong to an organization, amplifa_admin must not
  test 'should require organization for customer_admin role' do
    account = Account.new(
      email: 'test@example.com',
      first_name: 'Test',
      last_name: 'User',
      role: 'customer_admin',
      organization: nil
    )
    refute account.valid?
    assert_includes account.errors[:organization], 'is required for customer roles'
  end

  test 'should require organization for customer_user role' do
    account = Account.new(
      email: 'test@example.com',
      first_name: 'Test',
      last_name: 'User',
      role: 'customer_user',
      organization: nil
    )
    refute account.valid?
    assert_includes account.errors[:organization], 'is required for customer roles'
  end

  test 'should forbid organization for amplifa_admin role' do
    account = Account.new(
      email: 'test@example.com',
      first_name: 'Test',
      last_name: 'User',
      role: 'amplifa_admin',
      organization: @organization
    )
    refute account.valid?
    assert_includes account.errors[:organization], 'must be blank for amplifa_admin role'
  end

  test 'amplifa_admin can be created without organization' do
    account = Account.new(
      email: 'test@example.com',
      first_name: 'Test',
      last_name: 'User',
      role: 'amplifa_admin',
      organization: nil,
      password_hash: 'test'
    )
    assert account.valid?
  end

  # Role method tests
  # Why: These methods are used throughout the app for authorization checks
  test 'amplifa_admin? returns true for amplifa_admin role' do
    assert @amplifa_admin.amplifa_admin?
    refute @customer_admin.amplifa_admin?
    refute @customer_user.amplifa_admin?
  end

  test 'customer_admin? returns true for customer_admin role' do
    refute @amplifa_admin.customer_admin?
    assert @customer_admin.customer_admin?
    refute @customer_user.customer_admin?
  end

  test 'customer_user? returns true for customer_user role' do
    refute @amplifa_admin.customer_user?
    refute @customer_admin.customer_user?
    assert @customer_user.customer_user?
  end

  # Impersonation tests
  # Why: Only amplifa_admin users should be able to impersonate other users
  test 'can_impersonate? returns true only for amplifa_admin' do
    assert @amplifa_admin.can_impersonate?
    refute @customer_admin.can_impersonate?
    refute @customer_user.can_impersonate?
  end

  test 'amplifa_admin does not require email two factor authentication by default' do
    @amplifa_admin.update!(two_factor_authentication_required: false)

    assert_equal false, @amplifa_admin.requires_email_two_factor_authentication?
  end

  test 'amplifa_admin requires email two factor authentication when account flag is enabled' do
    @amplifa_admin.update!(two_factor_authentication_required: true)

    assert @amplifa_admin.requires_email_two_factor_authentication?
  end

  test 'account two factor flag does not require email two factor authentication for customer users' do
    @customer_user.organization.update!(two_factor_authentication_required: false)
    @customer_user.update!(two_factor_authentication_required: true)

    assert_equal false, @customer_user.requires_email_two_factor_authentication?
  end

  test 'organization two factor setting still requires email two factor authentication for customer users' do
    @customer_user.update!(two_factor_authentication_required: false)
    @customer_user.organization.update!(two_factor_authentication_required: true)

    assert @customer_user.requires_email_two_factor_authentication?
  end

  # Utility method tests
  # Why: full_name is used throughout the UI to display user names
  test 'full_name returns first and last name' do
    account = Account.new(first_name: 'John', last_name: 'Doe')
    assert_equal 'John Doe', account.full_name
  end

  # Scope tests
  # Why: Scopes are used throughout the app to filter accounts by role and organization
  test 'amplifa_admins scope returns only amplifa_admin accounts' do
    admins = Account.amplifa_admins
    assert(admins.all? { |a| a.role == 'amplifa_admin' })
  end

  test 'customer_admins scope returns only customer_admin accounts' do
    admins = Account.customer_admins
    assert(admins.all? { |a| a.role == 'customer_admin' })
  end

  test 'customer_users scope returns only customer_user accounts' do
    users = Account.customer_users
    assert(users.all? { |a| a.role == 'customer_user' })
  end

  test 'customers scope returns both customer_admin and customer_user accounts' do
    customers = Account.customers
    assert(customers.all? { |a| a.role.in?(%w[customer_admin customer_user]) })
  end

  test 'for_organization scope returns only accounts for given organization' do
    org_accounts = Account.for_organization(@organization)
    assert(org_accounts.all? { |a| a.organization_id == @organization.id })
  end

  # Association tests
  # Why: Ensure the new associations are properly set up
  test 'should belong to impersonating account optionally' do
    assert_respond_to @customer_user, :impersonating
  end

  test 'should have many admin_activities' do
    assert_respond_to @amplifa_admin, :admin_activities
  end

  # Internationalization tests (Week 2)
  # Why: Users need to be able to set their preferred language and timezone
  test 'should accept valid locale en' do
    account = Account.new(
      email: 'test@example.com',
      first_name: 'Test',
      last_name: 'User',
      role: 'amplifa_admin',
      locale: 'en'
    )
    assert account.valid?
  end

  test 'should accept valid locale de' do
    account = Account.new(
      email: 'test@example.com',
      first_name: 'Test',
      last_name: 'User',
      role: 'amplifa_admin',
      locale: 'de'
    )
    assert account.valid?
  end

  test 'should accept valid locale pt-BR' do
    account = Account.new(
      email: 'test@example.com',
      first_name: 'Test',
      last_name: 'User',
      role: 'amplifa_admin',
      locale: 'pt-BR'
    )
    assert account.valid?
  end

  test 'should reject invalid locale' do
    account = Account.new(
      email: 'test@example.com',
      first_name: 'Test',
      last_name: 'User',
      role: 'amplifa_admin',
      locale: 'xx'
    )
    refute account.valid?
    assert_includes account.errors[:locale], 'is not included in the list'
  end

  test 'should allow nil locale' do
    # Why: Locale is optional and falls back to organization or default
    account = Account.new(
      email: 'test@example.com',
      first_name: 'Test',
      last_name: 'User',
      role: 'amplifa_admin',
      locale: nil
    )
    assert account.valid?
  end

  test 'should accept valid timezone' do
    account = Account.new(
      email: 'test@example.com',
      first_name: 'Test',
      last_name: 'User',
      role: 'amplifa_admin',
      timezone: 'America/New_York'
    )
    assert account.valid?
  end

  test 'should reject invalid timezone' do
    # Why: Only valid IANA timezones should be accepted
    account = Account.new(
      email: 'test@example.com',
      first_name: 'Test',
      last_name: 'User',
      role: 'amplifa_admin',
      timezone: 'Invalid/Timezone'
    )
    refute account.valid?
    assert_includes account.errors[:timezone], 'is not included in the list'
  end

  test 'should allow nil timezone' do
    # Why: Timezone is optional and defaults to UTC
    account = Account.new(
      email: 'test@example.com',
      first_name: 'Test',
      last_name: 'User',
      role: 'amplifa_admin',
      timezone: nil
    )
    assert account.valid?
  end

  test 'effective_locale returns account locale when set' do
    # Why: User's explicit locale choice should take precedence
    account = @customer_admin
    account.locale = 'de'
    assert_equal 'de', account.effective_locale
  end

  test 'effective_locale returns organization locale when account locale is nil' do
    # Why: Should fall back to organization locale if user hasn't set one
    @organization.update!(locale: 'de')
    account = @customer_admin
    account.locale = nil
    assert_equal 'de', account.effective_locale
  end

  test 'effective_locale returns en when both account and org locale are nil' do
    # Why: Should fall back to default 'en' if nothing is set
    @organization.update!(locale: 'en')
    account = @amplifa_admin
    account.locale = nil
    assert_equal 'en', account.effective_locale
  end

  test 'effective_timezone returns account timezone when set' do
    # Why: User's explicit timezone choice should be used
    account = @customer_admin
    account.timezone = 'Europe/Berlin'
    assert_equal 'Europe/Berlin', account.effective_timezone
  end

  test 'effective_timezone returns UTC when timezone is nil' do
    # Why: UTC is the safe default when no timezone is set
    account = @customer_admin
    account.timezone = nil
    assert_equal 'UTC', account.effective_timezone
  end

  test 'effective_timezone returns UTC when timezone is empty string' do
    # Why: Empty string should also fall back to UTC
    account = @customer_admin
    account.timezone = ''
    assert_equal 'UTC', account.effective_timezone
  end
end
