require "test_helper"

class OrganizationPolicyTest < ActiveSupport::TestCase
  def setup
    @amplifa_admin = accounts(:amplifa_admin)
    @customer_admin = accounts(:customer_admin)
    @customer_user = accounts(:customer_user)
    @growth_lab_admin = accounts(:growth_lab_admin)
    @acme = organizations(:acme)
    @growth_lab = organizations(:growth_lab)
  end

  def teardown
    Current.reset
  end

  test 'show? uses selected organization instead of legacy account organization' do
    membership = OrganizationMembership.create!(
      account: @customer_admin,
      organization: @growth_lab,
      role: 'customer_user',
      status: 'active'
    )
    Current.account = @customer_admin
    Current.organization = @growth_lab
    Current.organization_membership = membership

    assert OrganizationPolicy.new(@customer_admin, @growth_lab).show?
    assert_not OrganizationPolicy.new(@customer_admin, @acme).show?
  end

  test 'update_company_settings? uses selected membership role' do
    membership = OrganizationMembership.create!(
      account: @customer_admin,
      organization: @growth_lab,
      role: 'customer_user',
      status: 'active'
    )
    Current.account = @customer_admin
    Current.organization = @growth_lab
    Current.organization_membership = membership

    assert_not OrganizationPolicy.new(@customer_admin, @growth_lab).update_company_settings?
  end

  # show? tests
  test "show? returns true for amplifa_admin on any organization" do
    # WHY: Platform admins can view all organizations for support
    assert OrganizationPolicy.new(@amplifa_admin, @acme).show?
    assert OrganizationPolicy.new(@amplifa_admin, @growth_lab).show?
  end

  test "show? returns true for customer viewing own organization" do
    Current.organization = @acme
    # WHY: Users can view their own organization
    assert OrganizationPolicy.new(@customer_admin, @acme).show?
    assert OrganizationPolicy.new(@customer_user, @acme).show?
  end

  test "show? returns false for customer viewing other organization" do
    # WHY: Users cannot view other organizations
    assert_not OrganizationPolicy.new(@customer_admin, @growth_lab).show?
    assert_not OrganizationPolicy.new(@customer_user, @growth_lab).show?
  end

  # update? tests
  test "update? returns true for amplifa_admin on any organization" do
    # WHY: Platform admins can update all organizations
    assert OrganizationPolicy.new(@amplifa_admin, @acme).update?
  end

  test "update? returns true for customer_admin on own organization" do
    # WHY: Customer admins can manage their own organization
    Current.organization = @acme
    Current.organization_membership = organization_memberships(:customer_admin_acme)
    assert OrganizationPolicy.new(@customer_admin, @acme).update?
  end

  test "update? returns false for customer_admin on other organization" do
    # WHY: Customer admins cannot modify other organizations
    assert_not OrganizationPolicy.new(@customer_admin, @growth_lab).update?
  end

  test "update? returns false for customer_user" do
    # WHY: Regular users cannot update organization settings
    assert_not OrganizationPolicy.new(@customer_user, @acme).update?
  end

  # update_company_settings? tests
  test "update_company_settings? returns true for amplifa_admin" do
    # WHY: Platform admins can update any organization's settings
    assert OrganizationPolicy.new(@amplifa_admin, @acme).update_company_settings?
  end

  test "update_company_settings? returns true for customer_admin on own organization" do
    # WHY: Customer admins can update their own organization's settings
    Current.organization = @acme
    Current.organization_membership = organization_memberships(:customer_admin_acme)
    assert OrganizationPolicy.new(@customer_admin, @acme).update_company_settings?
  end

  test "update_company_settings? returns false for customer_admin on other organization" do
    # WHY: Customer admins cannot update other organizations' settings
    assert_not OrganizationPolicy.new(@customer_admin, @growth_lab).update_company_settings?
  end

  test "update_company_settings? returns false for customer_user" do
    # WHY: Regular users cannot update organization settings
    assert_not OrganizationPolicy.new(@customer_user, @acme).update_company_settings?
  end

  # update_slack_settings? tests
  test "update_slack_settings? returns true for amplifa_admin" do
    # WHY: Only platform admins can configure Slack webhook integration
    assert OrganizationPolicy.new(@amplifa_admin, @acme).update_slack_settings?
  end

  test "update_slack_settings? returns false for customer_admin" do
    # WHY: Customers cannot configure Slack integration - admin-only
    assert_not OrganizationPolicy.new(@customer_admin, @acme).update_slack_settings?
  end

  test "update_slack_settings? returns false for customer_user" do
    # WHY: Regular users cannot configure integrations
    assert_not OrganizationPolicy.new(@customer_user, @acme).update_slack_settings?
  end

  # Scope tests
  test "Scope returns all organizations for amplifa_admin" do
    # WHY: Platform admins can see all organizations
    scope = OrganizationPolicy::Scope.new(@amplifa_admin, Organization).resolve
    assert_equal Organization.count, scope.count
  end

  test "Scope returns only own organization for customer" do
    Current.organization = @acme
    # WHY: Customers can only see their own organization
    scope = OrganizationPolicy::Scope.new(@customer_admin, Organization).resolve
    assert_equal 1, scope.count
    assert_equal @customer_admin.organization_id, scope.first.id
  end
end
