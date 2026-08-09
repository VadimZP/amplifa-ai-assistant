require "test_helper"

class LeadPolicyTest < ActiveSupport::TestCase
  def setup
    @amplifa_admin = accounts(:amplifa_admin)
    @customer_admin = accounts(:customer_admin)
    @customer_user = accounts(:customer_user)
    @growth_lab_admin = accounts(:growth_lab_admin)
    @acme_lead = leads(:john_doe)
    @beta_lead = leads(:beta_lead)
  end

  def teardown
    Current.reset
  end

  # index? tests
  test "index? returns true for amplifa_admin" do
    # WHY: Amplifa admins need to view all leads across organizations
    assert LeadPolicy.new(@amplifa_admin, Lead).index?
  end

  test "index? returns true for customer_admin" do
    Current.organization_membership = organization_memberships(:customer_admin_acme)
    # WHY: Customer admins can view leads in their organization
    assert LeadPolicy.new(@customer_admin, Lead).index?
  end

  test "index? returns true for customer_user" do
    Current.organization_membership = organization_memberships(:customer_user_acme)
    # WHY: Customer users can view leads in their organization
    assert LeadPolicy.new(@customer_user, Lead).index?
  end

  # show? tests
  test "show? returns true for amplifa_admin on any lead" do
    # WHY: Amplifa admins need full visibility for support and management
    assert LeadPolicy.new(@amplifa_admin, @acme_lead).show?
    assert LeadPolicy.new(@amplifa_admin, @beta_lead).show?
  end

  test "show? returns true for customer viewing own org lead" do
    Current.organization = organizations(:acme)
    # WHY: Customers should view leads belonging to their organization
    assert LeadPolicy.new(@customer_admin, @acme_lead).show?
    assert LeadPolicy.new(@customer_user, @acme_lead).show?
  end

  test "show? returns false for customer viewing other org lead" do
    # WHY: Customers should not access leads from other organizations
    assert_not LeadPolicy.new(@customer_admin, @beta_lead).show?
    assert_not LeadPolicy.new(@customer_user, @beta_lead).show?
  end

  # Scope tests
  test "Scope returns all leads for amplifa_admin" do
    # WHY: Amplifa admins need visibility across all organizations
    scope = LeadPolicy::Scope.new(@amplifa_admin, Lead).resolve
    assert_equal Lead.count, scope.count
  end

  test "Scope returns only own org leads for customer_admin" do
    Current.organization = organizations(:acme)
    # WHY: Customer admins should only see their organization's leads
    scope = LeadPolicy::Scope.new(@customer_admin, Lead).resolve
    expected_leads = Lead.where(organization: @customer_admin.organization)
    assert_equal expected_leads.count, scope.count
    scope.each do |lead|
      assert_equal @customer_admin.organization_id, lead.organization_id
    end
  end

  test "Scope returns only own org leads for customer_user" do
    Current.organization = organizations(:acme)
    # WHY: Customer users should only see their organization's leads
    scope = LeadPolicy::Scope.new(@customer_user, Lead).resolve
    expected_leads = Lead.where(organization: @customer_user.organization)
    assert_equal expected_leads.count, scope.count
    scope.each do |lead|
      assert_equal @customer_user.organization_id, lead.organization_id
    end
  end
end
