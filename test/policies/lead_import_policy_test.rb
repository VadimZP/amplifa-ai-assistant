require "test_helper"

class LeadImportPolicyTest < ActiveSupport::TestCase
  def setup
    @amplifa_admin = accounts(:amplifa_admin)
    @customer_admin = accounts(:customer_admin)
    @customer_user = accounts(:customer_user)
    @growth_lab_admin = accounts(:growth_lab_admin)
    @acme_import = lead_imports(:completed_import)
    @beta_import = lead_imports(:failed_import)
  end

  def teardown
    Current.reset
  end

  # index? tests
  test "index? returns true for amplifa_admin" do
    # WHY: Amplifa admins can see all imports across organizations
    assert LeadImportPolicy.new(@amplifa_admin, LeadImport).index?
  end

  test "index? returns true for customer_admin" do
    Current.organization = organizations(:acme)
    # WHY: Customer admins can view their org's import history
    assert LeadImportPolicy.new(@customer_admin, LeadImport).index?
  end

  test "index? returns true for customer_user" do
    Current.organization = organizations(:acme)
    # WHY: Customer users can view their org's import history
    assert LeadImportPolicy.new(@customer_user, LeadImport).index?
  end

  # show? tests
  test "show? returns true for amplifa_admin on any import" do
    # WHY: Amplifa admins need full visibility for support
    assert LeadImportPolicy.new(@amplifa_admin, @acme_import).show?
    assert LeadImportPolicy.new(@amplifa_admin, @beta_import).show?
  end

  test "show? returns true for customer viewing own org import" do
    Current.organization = organizations(:acme)
    # WHY: Customers can view their organization's imports
    assert LeadImportPolicy.new(@customer_admin, @acme_import).show?
    assert LeadImportPolicy.new(@customer_user, @acme_import).show?
  end

  test "show? returns false for customer viewing other org import" do
    # WHY: Customers should not access other org's import data
    assert_not LeadImportPolicy.new(@customer_admin, @beta_import).show?
    assert_not LeadImportPolicy.new(@customer_user, @beta_import).show?
  end

  # create? tests
  test "create? returns true for amplifa_admin" do
    # WHY: Only Amplifa admins can create/import leads
    assert LeadImportPolicy.new(@amplifa_admin, LeadImport.new).create?
  end

  test "create? returns false for customer_admin" do
    # WHY: Customers cannot create imports - admin-only operation
    assert_not LeadImportPolicy.new(@customer_admin, LeadImport.new).create?
  end

  test "create? returns false for customer_user" do
    # WHY: Customers cannot create imports
    assert_not LeadImportPolicy.new(@customer_user, LeadImport.new).create?
  end

  # new? tests
  test "new? follows create? for all user types" do
    # WHY: Access to import form follows create permission
    assert LeadImportPolicy.new(@amplifa_admin, LeadImport.new).new?
    assert_not LeadImportPolicy.new(@customer_admin, LeadImport.new).new?
    assert_not LeadImportPolicy.new(@customer_user, LeadImport.new).new?
  end

  # Scope tests
  test "Scope returns all imports for amplifa_admin" do
    # WHY: Admins need visibility across all organizations
    scope = LeadImportPolicy::Scope.new(@amplifa_admin, LeadImport).resolve
    assert_equal LeadImport.count, scope.count
  end

  test "Scope returns only own org imports for customer_admin" do
    Current.organization = organizations(:acme)
    # WHY: Customers should only see their organization's imports
    scope = LeadImportPolicy::Scope.new(@customer_admin, LeadImport).resolve
    expected_imports = LeadImport.where(organization: @customer_admin.organization)
    assert_equal expected_imports.count, scope.count
    scope.each do |lead_import|
      assert_equal @customer_admin.organization_id, lead_import.organization_id
    end
  end

  test "Scope returns only own org imports for customer_user" do
    Current.organization = organizations(:acme)
    # WHY: Customer users should only see their organization's imports
    scope = LeadImportPolicy::Scope.new(@customer_user, LeadImport).resolve
    scope.each do |lead_import|
      assert_equal @customer_user.organization_id, lead_import.organization_id
    end
  end
end
