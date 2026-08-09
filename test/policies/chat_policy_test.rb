require 'test_helper'

class ChatPolicyTest < ActiveSupport::TestCase
  def setup
    @amplifa_admin = accounts(:amplifa_admin)
    @customer_admin = accounts(:customer_admin)
    @customer_user = accounts(:customer_user)
    @growth_lab_admin = accounts(:growth_lab_admin)

    @acme_admin_chat = chats(:acme_admin_chat)
    @acme_user_chat = chats(:acme_user_chat)
    @growth_lab_chat = chats(:growth_lab_chat)
  end

  def teardown
    Current.reset
  end

  def act_as_acme_admin
    Current.account = @customer_admin
    Current.organization = organizations(:acme)
    Current.organization_membership = organization_memberships(:customer_admin_acme)
  end

  # index? / create?
  test 'index? returns true for a customer with an active membership' do
    act_as_acme_admin
    assert ChatPolicy.new(@customer_admin, Chat).index?
  end

  test 'index? returns false for amplifa_admin' do
    # WHY: The assistant is a customer surface. An amplifa admin has no workspace to scope it to.
    assert_not ChatPolicy.new(@amplifa_admin, Chat).index?
  end

  test 'index? returns false without an active membership' do
    assert_not ChatPolicy.new(@customer_admin, Chat).index?
  end

  test 'create? returns true for a customer and false for amplifa_admin' do
    act_as_acme_admin
    assert ChatPolicy.new(@customer_admin, Chat).create?
    assert_not ChatPolicy.new(@amplifa_admin, Chat).create?
  end

  # show?
  test 'show? returns true for the owner in the matching organization' do
    act_as_acme_admin
    assert ChatPolicy.new(@customer_admin, @acme_admin_chat).show?
  end

  test 'show? returns false for a colleague in the same organization' do
    # WHY: Chats are private per user, not per organization — a customer admin cannot read a
    # colleague's assistant conversation.
    act_as_acme_admin
    assert_not ChatPolicy.new(@customer_admin, @acme_user_chat).show?
  end

  test 'show? returns false for a chat in another organization' do
    act_as_acme_admin
    assert_not ChatPolicy.new(@customer_admin, @growth_lab_chat).show?
  end

  test 'show? returns false for amplifa_admin on any chat' do
    assert_not ChatPolicy.new(@amplifa_admin, @acme_admin_chat).show?
    assert_not ChatPolicy.new(@amplifa_admin, @growth_lab_chat).show?
  end

  test 'show? returns false when the owner is acting in a different workspace' do
    # WHY: The same user switched to growth_lab must not see the chat they created in acme —
    # otherwise assistant context could leak across the tenant boundary mid-session.
    membership = OrganizationMembership.create!(
      account: @customer_admin,
      organization: organizations(:growth_lab),
      role: 'customer_user',
      status: 'active'
    )
    Current.account = @customer_admin
    Current.organization = organizations(:growth_lab)
    Current.organization_membership = membership

    assert_not ChatPolicy.new(@customer_admin, @acme_admin_chat).show?
  end

  # destroy? / create_message?
  test 'destroy? and create_message? mirror show?' do
    act_as_acme_admin
    assert ChatPolicy.new(@customer_admin, @acme_admin_chat).destroy?
    assert ChatPolicy.new(@customer_admin, @acme_admin_chat).create_message?

    assert_not ChatPolicy.new(@customer_admin, @growth_lab_chat).destroy?
    assert_not ChatPolicy.new(@customer_admin, @growth_lab_chat).create_message?
    assert_not ChatPolicy.new(@customer_admin, @acme_user_chat).destroy?
    assert_not ChatPolicy.new(@customer_admin, @acme_user_chat).create_message?
  end

  test 'pin? mirrors show?' do
    act_as_acme_admin
    assert ChatPolicy.new(@customer_admin, @acme_admin_chat).pin?

    assert_not ChatPolicy.new(@customer_admin, @growth_lab_chat).pin?
    assert_not ChatPolicy.new(@customer_admin, @acme_user_chat).pin?
  end

  # Scope
  test 'Scope returns only the callers own chats in the current organization' do
    act_as_acme_admin
    scope = ChatPolicy::Scope.new(@customer_admin, Chat).resolve

    assert_includes scope, @acme_admin_chat
    assert_not_includes scope, @acme_user_chat
    assert_not_includes scope, @growth_lab_chat
  end

  test 'Scope returns none for amplifa_admin' do
    # WHY: Explicitly does not call super — admins get no assistant chats at all.
    assert_equal 0, ChatPolicy::Scope.new(@amplifa_admin, Chat).resolve.count
  end

  test 'Scope returns none for nil user' do
    assert_equal 0, ChatPolicy::Scope.new(nil, Chat).resolve.count
  end

  test 'Scope returns none without an active membership' do
    assert_equal 0, ChatPolicy::Scope.new(@customer_admin, Chat).resolve.count
  end

  test 'Scope excludes chats the same user owns in another workspace' do
    membership = OrganizationMembership.create!(
      account: @customer_admin,
      organization: organizations(:growth_lab),
      role: 'customer_user',
      status: 'active'
    )
    Current.account = @customer_admin
    Current.organization = organizations(:growth_lab)
    Current.organization_membership = membership

    scope = ChatPolicy::Scope.new(@customer_admin, Chat).resolve

    assert_not_includes scope, @acme_admin_chat
    assert_equal 0, scope.count
  end
end
