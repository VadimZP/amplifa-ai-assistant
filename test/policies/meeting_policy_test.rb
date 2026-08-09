# frozen_string_literal: true

require 'test_helper'

class MeetingPolicyTest < ActiveSupport::TestCase
  def setup
    @amplifa_admin = accounts(:amplifa_admin)
    @customer_admin = accounts(:customer_admin)
    @customer_user = accounts(:customer_user)
    @growth_lab_admin = accounts(:growth_lab_admin)
    @acme_meeting = meetings(:scheduled_discovery)
  end

  def teardown
    Current.reset
  end

  # index? tests

  # WHY: All authenticated users can list meetings (scoped by organization)
  test 'index? returns true for all authenticated users' do
    assert MeetingPolicy.new(@amplifa_admin, Meeting).index?
    assert MeetingPolicy.new(@customer_admin, Meeting).index?
    assert MeetingPolicy.new(@customer_user, Meeting).index?
  end

  # show? tests

  # WHY: Amplifa admins need full access for platform management
  test 'show? returns true for amplifa_admin on any meeting' do
    assert MeetingPolicy.new(@amplifa_admin, @acme_meeting).show?
  end

  # WHY: Customers can view meetings that belong to their organization
  test 'show? returns true for customer viewing own org meeting' do
    Current.organization = organizations(:acme)
    assert MeetingPolicy.new(@customer_admin, @acme_meeting).show?
    assert MeetingPolicy.new(@customer_user, @acme_meeting).show?
  end

  # create? tests

  # WHY: Only admins can create meetings (for dogfooding)
  test 'create? returns true for amplifa_admin' do
    assert MeetingPolicy.new(@amplifa_admin, Meeting.new).create?
  end

  # WHY: Customers can manually create meetings from the meetings page.
  test 'create? returns true for customers' do
    Current.organization = organizations(:acme)
    Current.organization_membership = organization_memberships(:customer_admin_acme)
    assert MeetingPolicy.new(@customer_admin, Meeting.new).create?
    Current.organization_membership = organization_memberships(:customer_user_acme)
    assert MeetingPolicy.new(@customer_user, Meeting.new).create?
  end

  # update? tests

  # WHY: Only admins can update meeting records
  test 'update? returns true for amplifa_admin' do
    assert MeetingPolicy.new(@amplifa_admin, @acme_meeting).update?
  end

  # WHY: Customers have read-only access to meetings
  test 'update? returns false for customers' do
    assert_not MeetingPolicy.new(@customer_admin, @acme_meeting).update?
    assert_not MeetingPolicy.new(@customer_user, @acme_meeting).update?
  end

  # destroy? tests

  # WHY: Only admins can delete meetings
  test 'destroy? returns true for amplifa_admin' do
    assert MeetingPolicy.new(@amplifa_admin, @acme_meeting).destroy?
  end

  # WHY: Customers cannot delete meetings
  test 'destroy? returns false for customers' do
    assert_not MeetingPolicy.new(@customer_admin, @acme_meeting).destroy?
    assert_not MeetingPolicy.new(@customer_user, @acme_meeting).destroy?
  end

  # mark_completed? tests

  test 'mark_completed? returns true for authorized users' do
    Current.organization = organizations(:acme)
    assert MeetingPolicy.new(@amplifa_admin, @acme_meeting).mark_completed?
    assert MeetingPolicy.new(@customer_admin, @acme_meeting).mark_completed?
    assert MeetingPolicy.new(@customer_user, @acme_meeting).mark_completed?
  end

  # mark_no_show? tests

  test 'mark_no_show? returns true for authorized users' do
    Current.organization = organizations(:acme)
    assert MeetingPolicy.new(@amplifa_admin, @acme_meeting).mark_no_show?
    assert MeetingPolicy.new(@customer_admin, @acme_meeting).mark_no_show?
    assert MeetingPolicy.new(@customer_user, @acme_meeting).mark_no_show?
  end

  # cancel? tests

  # WHY: Only admins can cancel meetings
  test 'cancel? returns true for amplifa_admin' do
    assert MeetingPolicy.new(@amplifa_admin, @acme_meeting).cancel?
  end

  # WHY: Customers cannot cancel meetings
  test 'cancel? returns false for customers' do
    assert_not MeetingPolicy.new(@customer_admin, @acme_meeting).cancel?
    assert_not MeetingPolicy.new(@customer_user, @acme_meeting).cancel?
  end

  # reschedule? tests

  test 'reschedule? returns true for authorized users' do
    Current.organization = organizations(:acme)
    assert MeetingPolicy.new(@amplifa_admin, @acme_meeting).reschedule?
    assert MeetingPolicy.new(@customer_admin, @acme_meeting).reschedule?
    assert MeetingPolicy.new(@customer_user, @acme_meeting).reschedule?
  end

  # Scope tests

  # WHY: Admins need visibility across all organizations
  test 'Scope returns all meetings for amplifa_admin' do
    scope = MeetingPolicy::Scope.new(@amplifa_admin, Meeting).resolve
    assert_equal Meeting.count, scope.count
  end

  # WHY: Customers should only see meetings from their organization
  test 'Scope returns only own org meetings for customer' do
    Current.organization = organizations(:acme)
    scope = MeetingPolicy::Scope.new(@customer_admin, Meeting).resolve
    scope.each do |meeting|
      assert_equal @customer_admin.organization_id, meeting.agent.organization_id
    end
  end

  # WHY: an account acting in a workspace where it holds an active membership is a
  # customer_account there, even when its global role would not classify it as one.
  test 'customer_account? follows an active current-workspace membership over global role' do
    membership = OrganizationMembership.create!(
      account: @amplifa_admin,
      organization: organizations(:acme),
      role: 'customer_user',
      status: 'active'
    )
    Current.account = @amplifa_admin
    Current.organization = organizations(:acme)
    Current.organization_membership = membership

    policy = MeetingPolicy.new(@amplifa_admin, Meeting.new)

    assert policy.send(:customer_account?),
           'an account with an active current-workspace membership should be recognized as a customer_account'
  end

  # WHY: a customer acting in a workspace where they hold an ACTIVE membership can
  # create meetings (the create? consumer of the membership-first customer_account?).
  test 'create? is true for a customer_user with an active membership in the current workspace' do
    Current.account = @customer_user
    Current.organization = organizations(:acme)
    Current.organization_membership = organization_memberships(:customer_user_acme)

    assert MeetingPolicy.new(@customer_user, Meeting.new).create?
  end

  # AMP-435 §9 / bug B-fallback: customer_account? no longer falls back to the legacy
  # global Account#role without a current-workspace membership; it returns false
  # (unreachable in real requests). Membership-driven behavior pinned by siblings above.
  test 'customer_account? returns false when there is no current membership' do
    Current.reset

    assert_not MeetingPolicy.new(@customer_user, Meeting.new).send(:customer_account?)
    assert_not MeetingPolicy.new(@customer_admin, Meeting.new).send(:customer_account?)
    assert_not MeetingPolicy.new(@amplifa_admin, Meeting.new).send(:customer_account?)
    assert_not MeetingPolicy.new(nil, Meeting.new).send(:customer_account?)
  end

  # WHY: amplifa_admins can always create via ApplicationPolicy#create? (super),
  # independent of workspace/membership state.
  test 'create? is true for amplifa_admin via super even with no current membership' do
    Current.reset

    assert MeetingPolicy.new(@amplifa_admin, Meeting.new).create?
  end

  # WHY: create? denies unauthenticated (nil user) requests.
  test 'create? is false without a user' do
    Current.reset

    assert_not MeetingPolicy.new(nil, Meeting.new).create?
  end
end
