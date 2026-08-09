require "test_helper"

class TeamPolicyTest < ActiveSupport::TestCase
  def setup
    @amplifa_admin = accounts(:amplifa_admin)
    @customer_admin = accounts(:customer_admin)
    @customer_user = accounts(:customer_user)
  end

  test "index? returns true for customer_admin" do
    # WHY: Customer admins need to see their team members to manage
    # the organization and understand who has access
    policy = TeamPolicy.new(@customer_admin, :team)
    assert policy.index?, "Customer admin should be able to view team page"
  end

  test "index? returns true for customer_user" do
    # WHY: Regular customer users should also be able to see who is
    # on their team for collaboration and transparency
    policy = TeamPolicy.new(@customer_user, :team)
    assert policy.index?, "Customer user should be able to view team page"
  end

  test "index? returns true for amplifa_admin" do
    # WHY: Amplifa admins are internal staff who need to see their team
    # (other amplifa admins) for collaboration. When they access the team
    # page, they should see other internal staff, not customer users.
    policy = TeamPolicy.new(@amplifa_admin, :team)
    assert policy.index?, "Amplifa admin should be able to view their team"
  end

  test "index? returns false for nil user" do
    # WHY: Unauthenticated users should not be able to access
    # the team page at all
    policy = TeamPolicy.new(nil, :team)
    assert_not policy.index?, "Nil user should not access team page"
  end
end
