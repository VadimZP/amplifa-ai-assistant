require "test_helper"

class BlacklistPolicyTest < ActiveSupport::TestCase
  def setup
    @amplifa_admin = accounts(:amplifa_admin)
    @customer_admin = accounts(:customer_admin)
    @customer_user = accounts(:customer_user)
    @growth_lab_admin = accounts(:growth_lab_admin)
    @global_email = blacklists(:global_email)
    @global_domain = blacklists(:global_domain)
    @acme_email = blacklists(:acme_email_blacklist)
    @acme_domain = blacklists(:acme_domain_blacklist)
    @beta_unsubscribe = blacklists(:beta_unsubscribe)
  end

  def teardown
    Current.reset
  end

  # index? tests
  test "index? returns true for all authenticated users" do
    # WHY: All users can view blacklist entries (scoped by Scope)
    assert BlacklistPolicy.new(@amplifa_admin, Blacklist).index?
    assert BlacklistPolicy.new(@customer_admin, Blacklist).index?
    assert BlacklistPolicy.new(@customer_user, Blacklist).index?
  end

  # show? tests
  test "show? returns true for amplifa_admin on any entry" do
    # WHY: Amplifa admins need full visibility for platform management
    assert BlacklistPolicy.new(@amplifa_admin, @global_email).show?
    assert BlacklistPolicy.new(@amplifa_admin, @acme_email).show?
    assert BlacklistPolicy.new(@amplifa_admin, @beta_unsubscribe).show?
  end

  test "show? returns true for customer viewing global entries" do
    # WHY: Customers need to see global entries that affect their imports
    assert BlacklistPolicy.new(@customer_admin, @global_email).show?
    assert BlacklistPolicy.new(@customer_user, @global_domain).show?
  end

  test "show? returns true for customer viewing own org entries" do
    Current.organization = organizations(:acme)
    # WHY: Customers can view their organization's blacklist entries
    assert BlacklistPolicy.new(@customer_admin, @acme_email).show?
    assert BlacklistPolicy.new(@customer_user, @acme_domain).show?
  end

  test "show? returns false for customer viewing other org entries" do
    # WHY: Customers should not see other organizations' blacklist entries
    assert_not BlacklistPolicy.new(@customer_admin, @beta_unsubscribe).show?
    assert_not BlacklistPolicy.new(@customer_user, @beta_unsubscribe).show?
  end

  # create? tests
  test "create? returns true for amplifa_admin" do
    # WHY: Amplifa admins can create any blacklist entry
    assert BlacklistPolicy.new(@amplifa_admin, Blacklist.new).create?
  end

  test "create? returns true for customer_admin" do
    # WHY: Customer admins can create blacklist entries for their org
    Current.organization_membership = organization_memberships(:customer_admin_acme)
    assert BlacklistPolicy.new(@customer_admin, Blacklist.new).create?
  end

  test "create? returns false for customer_user" do
    # WHY: Regular users cannot create blacklist entries
    assert_not BlacklistPolicy.new(@customer_user, Blacklist.new).create?
  end

  # create_global? tests
  test "create_global? returns true for amplifa_admin" do
    # WHY: Only Amplifa admins can create global entries that affect all orgs
    assert BlacklistPolicy.new(@amplifa_admin, Blacklist.new).create_global?
  end

  test "create_global? returns false for customer_admin" do
    # WHY: Customer admins cannot create global entries
    assert_not BlacklistPolicy.new(@customer_admin, Blacklist.new).create_global?
  end

  test "create_global? returns false for customer_user" do
    # WHY: Customer users cannot create global entries
    assert_not BlacklistPolicy.new(@customer_user, Blacklist.new).create_global?
  end

  # update? tests
  test "update? returns true for amplifa_admin on any entry" do
    # WHY: Amplifa admins can update any blacklist entry
    assert BlacklistPolicy.new(@amplifa_admin, @global_email).update?
    assert BlacklistPolicy.new(@amplifa_admin, @acme_email).update?
  end

  test "update? returns true for customer_admin on own org entry" do
    # WHY: Customer admins can update their org's blacklist entries
    Current.organization = organizations(:acme)
    Current.organization_membership = organization_memberships(:customer_admin_acme)
    assert BlacklistPolicy.new(@customer_admin, @acme_email).update?
  end

  test "update? returns false for customer_admin on global entry" do
    # WHY: Customer admins cannot modify global entries
    assert_not BlacklistPolicy.new(@customer_admin, @global_email).update?
  end

  test "update? returns false for customer_admin on other org entry" do
    # WHY: Customer admins cannot modify other org's entries
    assert_not BlacklistPolicy.new(@customer_admin, @beta_unsubscribe).update?
  end

  test "update? returns false for customer_user" do
    # WHY: Customer users cannot update blacklist entries
    assert_not BlacklistPolicy.new(@customer_user, @acme_email).update?
  end

  # destroy? tests
  test "destroy? returns true for amplifa_admin on any entry" do
    # WHY: Amplifa admins can delete any blacklist entry
    assert BlacklistPolicy.new(@amplifa_admin, @global_email).destroy?
    assert BlacklistPolicy.new(@amplifa_admin, @acme_email).destroy?
  end

  test "destroy? returns true for customer_admin on own org entry" do
    # WHY: Customer admins can delete their org's blacklist entries
    Current.organization = organizations(:acme)
    Current.organization_membership = organization_memberships(:customer_admin_acme)
    assert BlacklistPolicy.new(@customer_admin, @acme_email).destroy?
  end

  test "destroy? returns false for customer_admin on global entry" do
    # WHY: Customer admins cannot delete global entries
    assert_not BlacklistPolicy.new(@customer_admin, @global_email).destroy?
  end

  test "destroy? returns false for customer_admin on other org entry" do
    # WHY: Customer admins cannot delete other org's entries
    assert_not BlacklistPolicy.new(@customer_admin, @beta_unsubscribe).destroy?
  end

  test "destroy? returns false for customer_user" do
    # WHY: Customer users cannot delete blacklist entries
    assert_not BlacklistPolicy.new(@customer_user, @acme_email).destroy?
  end

  # Scope tests
  test "Scope returns all entries for amplifa_admin" do
    # WHY: Amplifa admins need full visibility
    scope = BlacklistPolicy::Scope.new(@amplifa_admin, Blacklist).resolve
    assert_equal Blacklist.count, scope.count
  end

  test "Scope returns org entries and global entries for customer" do
    Current.organization = organizations(:acme)
    # WHY: Customers see their org's entries plus global entries that affect them
    scope = BlacklistPolicy::Scope.new(@customer_admin, Blacklist).resolve
    scope.each do |entry|
      assert(entry.organization_id.nil? || entry.organization_id == @customer_admin.organization_id,
             "Customer should only see global or own org entries")
    end
    # Verify global entries are included
    assert scope.exists?(organization_id: nil), "Should include global entries"
    # Verify own org entries are included
    assert scope.exists?(organization_id: @customer_admin.organization_id), "Should include own org entries"
  end

  test "Scope does not include other org entries for customer" do
    # WHY: Customers should not see other organizations' blacklist entries
    scope = BlacklistPolicy::Scope.new(@customer_admin, Blacklist).resolve
    assert_not scope.exists?(organization_id: @beta_unsubscribe.organization_id),
               "Should not include other org entries"
  end
end
