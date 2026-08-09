require 'test_helper'

class OrganizationMembershipTest < ActiveSupport::TestCase
  def setup
    @account = accounts(:customer_user)
    @organization = organizations(:growth_lab)
  end

  test 'validates role inclusion' do
    membership = OrganizationMembership.new(
      account: @account,
      organization: @organization,
      role: 'owner',
      status: 'active'
    )

    refute membership.valid?
    assert_includes membership.errors[:role], 'is not included in the list'
  end

  test 'validates status inclusion' do
    membership = OrganizationMembership.new(
      account: @account,
      organization: @organization,
      role: 'customer_user',
      status: 'archived'
    )

    refute membership.valid?
    assert_includes membership.errors[:status], 'is not included in the list'
  end

  test 'requires unique account per organization' do
    OrganizationMembership.create!(
      account: @account,
      organization: @organization,
      role: 'customer_user',
      status: 'active'
    )

    duplicate = OrganizationMembership.new(
      account: @account,
      organization: @organization,
      role: 'customer_admin',
      status: 'active'
    )

    refute duplicate.valid?
    assert_includes duplicate.errors[:account_id], 'has already been taken'
  end

  test 'active scope excludes inactive memberships' do
    active = OrganizationMembership.create!(
      account: @account,
      organization: @organization,
      role: 'customer_user',
      status: 'active'
    )
    inactive = OrganizationMembership.create!(
      account: accounts(:growth_lab_user),
      organization: organizations(:acme),
      role: 'customer_user',
      status: 'inactive',
      deactivated_at: Time.current
    )

    assert_includes OrganizationMembership.active, active
    assert_not_includes OrganizationMembership.active, inactive
  end

  test 'active scope excludes memberships for deactivated organizations' do
    organization = organizations(:growth_lab)
    membership = OrganizationMembership.find_by!(account: accounts(:growth_lab_user), organization: organization)

    organization.deactivate!

    assert_not_includes OrganizationMembership.active, membership
    assert_not membership.reload.active?
  end

  test 'build_multi_org_scenario builds account with multi-org memberships' do
    result = build_multi_org_scenario

    assert result.org_a.active?
    assert result.org_b.active?
    assert_nil result.org_a.archived_at
    assert_nil result.org_b.archived_at
    refute_equal result.org_a, result.org_b

    assert result.org_archived.archived?
    assert result.org_deactivated.deactivated_at.present?

    assert result.membership_a.customer_admin?
    assert result.membership_a.active?
    assert_equal result.org_a, result.membership_a.organization

    assert result.membership_b.customer_user?
    assert result.membership_b.active?
    assert_equal result.org_b, result.membership_b.organization

    assert_equal 4, result.account.organization_memberships.count

    active_memberships = result.account.active_organization_memberships

    assert_includes active_memberships, result.membership_a
    assert_includes active_memberships, result.membership_b
    assert_not_includes active_memberships, result.membership_deactivated

    # Observed current behavior: OrganizationMembership.active only filters
    # organizations.deactivated_at, NOT archived_at, so the archived-org
    # membership is still INCLUDED in the active scope.
    assert_includes active_memberships, result.membership_archived
    assert_equal [result.membership_a, result.membership_b, result.membership_archived].map(&:id).sort,
                 active_memberships.map(&:id).sort
  end

  # AMP-435 §9 / bug B7: `switchable` narrows `active` to exclude archived orgs.
  test 'switchable scope excludes archived-org and deactivated-org memberships' do
    result = build_multi_org_scenario

    switchable = OrganizationMembership.switchable

    assert_includes switchable, result.membership_a
    assert_includes switchable, result.membership_b
    assert_not_includes switchable, result.membership_archived
    assert_not_includes switchable, result.membership_deactivated

    # Guards that the broadly-used `active` scope stays unchanged: admin, team,
    # meeting and channel surfaces still count the archived-org membership.
    assert_includes OrganizationMembership.active, result.membership_archived
  end

  test 'switchable scope is exposed through Account#switchable_organization_memberships' do
    result = build_multi_org_scenario

    switchable = result.account.switchable_organization_memberships

    assert_includes switchable, result.membership_a
    assert_includes switchable, result.membership_b
    assert_not_includes switchable, result.membership_archived
    assert_not_includes switchable, result.membership_deactivated

    assert_equal [result.membership_a, result.membership_b].map(&:id).sort,
                 switchable.map(&:id).sort
  end
end
