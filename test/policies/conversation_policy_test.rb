require 'test_helper'

class ConversationPolicyTest < ActiveSupport::TestCase
  def setup
    @amplifa_admin = accounts(:amplifa_admin)
    @customer_admin = accounts(:customer_admin)
    @customer_user = accounts(:customer_user)
    @growth_lab_admin = accounts(:growth_lab_admin)
    @acme_conversation = conversations(:acme_john_conversation)
    @growth_lab_conversation = conversations(:growth_lab_conversation)
  end

  def teardown
    Current.reset
  end

  test 'show? uses selected organization instead of legacy account organization' do
    membership = OrganizationMembership.create!(
      account: @customer_admin,
      organization: organizations(:growth_lab),
      role: 'customer_user',
      status: 'active'
    )
    Current.account = @customer_admin
    Current.organization = organizations(:growth_lab)
    Current.organization_membership = membership

    assert ConversationPolicy.new(@customer_admin, @growth_lab_conversation).show?
    assert_not ConversationPolicy.new(@customer_admin, @acme_conversation).show?
  end

  test 'scope uses selected organization instead of legacy account organization' do
    membership = OrganizationMembership.create!(
      account: @customer_admin,
      organization: organizations(:growth_lab),
      role: 'customer_user',
      status: 'active'
    )
    Current.account = @customer_admin
    Current.organization = organizations(:growth_lab)
    Current.organization_membership = membership

    scope = ConversationPolicy::Scope.new(@customer_admin, Conversation).resolve

    assert_includes scope, @growth_lab_conversation
    assert_not_includes scope, @acme_conversation
  end

  # index? tests
  test 'index? returns true for amplifa_admin' do
    # WHY: Platform admins need access to all conversations for support
    assert ConversationPolicy.new(@amplifa_admin, Conversation).index?
  end

  test 'index? returns true for customer_admin' do
    Current.organization_membership = organization_memberships(:customer_admin_acme)
    # WHY: Customer admins can view their organization's conversations
    assert ConversationPolicy.new(@customer_admin, Conversation).index?
  end

  test 'index? returns true for customer_user' do
    Current.organization_membership = organization_memberships(:customer_user_acme)
    assert ConversationPolicy.new(@customer_user, Conversation).index?
  end

  # show? tests
  test 'show? returns true for amplifa_admin on any conversation' do
    # WHY: Platform admins can view all conversations
    assert ConversationPolicy.new(@amplifa_admin, @acme_conversation).show?
    assert ConversationPolicy.new(@amplifa_admin, @growth_lab_conversation).show?
  end

  test 'show? returns true for customer_admin viewing own org conversation' do
    Current.organization = organizations(:acme)
    Current.organization_membership = organization_memberships(:customer_admin_acme)
    # WHY: Customer admins can view their organization's conversations
    assert ConversationPolicy.new(@customer_admin, @acme_conversation).show?
  end

  test 'show? returns false for customer_admin viewing other org conversation' do
    # WHY: Customers cannot view conversations from other organizations
    assert_not ConversationPolicy.new(@customer_admin, @growth_lab_conversation).show?
  end

  test 'show? returns true for customer_user viewing own org conversation' do
    Current.organization = organizations(:acme)
    Current.organization_membership = organization_memberships(:customer_user_acme)
    assert ConversationPolicy.new(@customer_user, @acme_conversation).show?
  end

  # close? tests
  test 'close? returns true for amplifa_admin' do
    # WHY: Only platform admins can close conversations
    assert ConversationPolicy.new(@amplifa_admin, @acme_conversation).close?
  end

  test 'close? returns false for customer_admin' do
    # WHY: Customers have read-only access to conversations
    assert_not ConversationPolicy.new(@customer_admin, @acme_conversation).close?
  end

  test 'close? returns false for customer_user' do
    # WHY: Regular users cannot manage conversations
    assert_not ConversationPolicy.new(@customer_user, @acme_conversation).close?
  end

  # reopen? tests
  test 'reopen? returns true for amplifa_admin' do
    # WHY: Only platform admins can reopen conversations
    assert ConversationPolicy.new(@amplifa_admin, @acme_conversation).reopen?
  end

  test 'reopen? returns false for customer_admin' do
    # WHY: Customers cannot reopen closed conversations
    assert_not ConversationPolicy.new(@customer_admin, @acme_conversation).reopen?
  end

  test 'reopen? returns false for customer_user' do
    # WHY: Regular users cannot manage conversations
    assert_not ConversationPolicy.new(@customer_user, @acme_conversation).reopen?
  end

  # snooze? tests
  test 'snooze? returns true for amplifa_admin' do
    # WHY: Only platform admins can snooze conversations
    assert ConversationPolicy.new(@amplifa_admin, @acme_conversation).snooze?
  end

  test 'snooze? returns false for customer_admin' do
    # WHY: Customers cannot snooze conversations
    assert_not ConversationPolicy.new(@customer_admin, @acme_conversation).snooze?
  end

  test 'snooze? returns false for customer_user' do
    # WHY: Regular users cannot manage conversations
    assert_not ConversationPolicy.new(@customer_user, @acme_conversation).snooze?
  end

  # send_reply? tests
  test 'send_reply? returns true for amplifa_admin' do
    # WHY: Only platform admins can send replies
    assert ConversationPolicy.new(@amplifa_admin, @acme_conversation).send_reply?
  end

  test 'send_reply? returns false for customer_admin' do
    Current.organization = organizations(:acme)
    Current.organization_membership = organization_memberships(:customer_admin_acme)
    assert ConversationPolicy.new(@customer_admin, @acme_conversation).send_reply?
  end

  test 'send_reply? returns true for customer_user on own org conversation' do
    Current.organization = organizations(:acme)
    Current.organization_membership = organization_memberships(:customer_user_acme)
    assert ConversationPolicy.new(@customer_user, @acme_conversation).send_reply?
  end

  # mark_read? tests
  test 'mark_read? returns true for amplifa_admin' do
    # WHY: Platform admins can mark replies as read
    assert ConversationPolicy.new(@amplifa_admin, @acme_conversation).mark_read?
  end

  test 'mark_read? returns true for customer_admin viewing own org conversation' do
    Current.organization = organizations(:acme)
    Current.organization_membership = organization_memberships(:customer_admin_acme)
    # WHY: Customer admins can mark their org's replies as read
    assert ConversationPolicy.new(@customer_admin, @acme_conversation).mark_read?
  end

  test 'mark_read? returns false for customer_admin on other org conversation' do
    # WHY: Cannot mark replies as read for other organizations
    assert_not ConversationPolicy.new(@customer_admin, @growth_lab_conversation).mark_read?
  end

  test 'mark_read? returns true for customer_user on own org conversation' do
    Current.organization = organizations(:acme)
    Current.organization_membership = organization_memberships(:customer_user_acme)
    assert ConversationPolicy.new(@customer_user, @acme_conversation).mark_read?
  end

  test 'update_interest_status? returns true for amplifa_admin' do
    assert ConversationPolicy.new(@amplifa_admin, @acme_conversation).update_interest_status?
  end

  test 'update_interest_status? returns true for customer accounts in own organization' do
    Current.organization = organizations(:acme)
    Current.organization_membership = organization_memberships(:customer_admin_acme)
    assert ConversationPolicy.new(@customer_admin, @acme_conversation).update_interest_status?
    Current.organization_membership = organization_memberships(:customer_user_acme)
    assert ConversationPolicy.new(@customer_user, @acme_conversation).update_interest_status?
  end

  test 'update_interest_status? returns false for customer accounts in other organization' do
    assert_not ConversationPolicy.new(@customer_admin, @growth_lab_conversation).update_interest_status?
    assert_not ConversationPolicy.new(@customer_user, @growth_lab_conversation).update_interest_status?
  end

  # Scope tests
  test 'Scope returns all conversations for amplifa_admin' do
    # WHY: Platform admins can see all conversations across organizations
    scope = ConversationPolicy::Scope.new(@amplifa_admin, Conversation).resolve
    assert_equal Conversation.count, scope.count
  end

  test 'Scope returns only own org conversations for customer_admin' do
    Current.organization = organizations(:acme)
    Current.organization_membership = organization_memberships(:customer_admin_acme)
    # WHY: Customer admins should only see their organization's conversations
    scope = ConversationPolicy::Scope.new(@customer_admin, Conversation).resolve
    expected_count = Conversation.where(organization_id: @customer_admin.organization_id).count
    assert_equal expected_count, scope.count
    scope.each do |conversation|
      assert_equal @customer_admin.organization_id, conversation.organization_id
    end
  end

  test 'Scope returns only own org conversations for customer_user' do
    Current.organization = organizations(:acme)
    Current.organization_membership = organization_memberships(:customer_user_acme)
    scope = ConversationPolicy::Scope.new(@customer_user, Conversation).resolve
    expected_count = Conversation.where(organization_id: @customer_user.organization_id).count
    assert_equal expected_count, scope.count
    scope.each do |conversation|
      assert_equal @customer_user.organization_id, conversation.organization_id
    end
  end

  test 'Scope returns none for nil user' do
    # WHY: Unauthenticated requests should see nothing
    scope = ConversationPolicy::Scope.new(nil, Conversation).resolve
    assert_equal 0, scope.count
  end
end
