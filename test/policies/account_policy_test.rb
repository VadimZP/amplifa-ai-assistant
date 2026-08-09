require 'test_helper'

class AccountPolicyTest < ActiveSupport::TestCase
  def setup
    @account = accounts(:customer_admin)
    @secondary_organization = organizations(:growth_lab)
    @secondary_user = accounts(:growth_lab_user)
    @membership = OrganizationMembership.create!(
      account: @account,
      organization: @secondary_organization,
      role: 'customer_user',
      status: 'active'
    )
    Current.account = @account
    Current.organization = @secondary_organization
    Current.organization_membership = @membership
  end

  def teardown
    Current.reset
  end

  test 'scope uses selected organization instead of legacy account organization' do
    scope = AccountPolicy::Scope.new(@account, Account).resolve

    assert_includes scope, @secondary_user
    assert_not_includes scope, accounts(:customer_user)
  end

  test 'update uses selected membership role instead of legacy account role' do
    policy = AccountPolicy.new(@account, @secondary_user)

    assert_not policy.update?
  end
end
