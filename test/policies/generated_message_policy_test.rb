# frozen_string_literal: true

require "test_helper"

# Tests for GeneratedMessagePolicy - controls access to AI-generated messages.
# WHY: Generated messages contain sensitive business communications and need
# proper authorization to ensure customers can only access their own data.
class GeneratedMessagePolicyTest < ActiveSupport::TestCase
  def setup
    @amplifa_admin = accounts(:amplifa_admin)
    @customer_admin = accounts(:customer_admin)
    @customer_user = accounts(:customer_user)
    @beta_user = accounts(:beta_user)
    @message = generated_messages(:john_step_one_draft)
  end

  def teardown
    Current.reset
  end

  # show? tests
  test "show? returns true for amplifa_admin" do
    # WHY: Admins can view all messages for platform management
    assert GeneratedMessagePolicy.new(@amplifa_admin, @message).show?
  end

  test "show? returns true for customer viewing own org message" do
    Current.organization = organizations(:acme)
    # WHY: Customers can view messages belonging to their organization
    assert GeneratedMessagePolicy.new(@customer_admin, @message).show?
    assert GeneratedMessagePolicy.new(@customer_user, @message).show?
  end

  test "show? returns false for customer viewing other org message" do
    # WHY: Customers should not access messages from other organizations
    assert_not GeneratedMessagePolicy.new(@beta_user, @message).show?
  end

  test "show? returns false for customer viewing deleted agent message" do
    Current.organization = organizations(:acme)
    @message.agent.mark_deleted!

    assert_not GeneratedMessagePolicy.new(@customer_admin, @message).show?
  end

  # update? tests
  test "update? returns true for amplifa_admin" do
    # WHY: Only admins can edit generated messages
    assert GeneratedMessagePolicy.new(@amplifa_admin, @message).update?
  end

  test "update? returns false for customer_admin" do
    # WHY: Customers have read-only access to messages
    assert_not GeneratedMessagePolicy.new(@customer_admin, @message).update?
  end

  test "update? returns false for customer_user" do
    # WHY: Customers cannot update messages
    assert_not GeneratedMessagePolicy.new(@customer_user, @message).update?
  end

  # send_test? tests
  test "send_test? returns true for amplifa_admin" do
    # WHY: Admins can send test emails to any address
    assert GeneratedMessagePolicy.new(@amplifa_admin, @message).send_test?
  end

  test "send_test? returns true for customer viewing own org message" do
    Current.organization = organizations(:acme)
    # WHY: Customers can send test emails to themselves
    assert GeneratedMessagePolicy.new(@customer_admin, @message).send_test?
  end

  test "send_test? returns false for customer viewing other org message" do
    # WHY: Customers should not send tests for other org's messages
    assert_not GeneratedMessagePolicy.new(@beta_user, @message).send_test?
  end

  test "send_test? returns false for customer viewing deleted agent message" do
    Current.organization = organizations(:acme)
    @message.agent.mark_deleted!

    assert_not GeneratedMessagePolicy.new(@customer_admin, @message).send_test?
  end

  # customer_send_test? tests
  test "customer_send_test? returns true for customer with own org message" do
    Current.organization = organizations(:acme)
    # WHY: Customers can send test emails to their own address
    assert GeneratedMessagePolicy.new(@customer_admin, @message).customer_send_test?
    assert GeneratedMessagePolicy.new(@customer_user, @message).customer_send_test?
  end

  test "customer_send_test? returns false for amplifa_admin" do
    # WHY: Admins should use the admin send_test action, not customer action
    assert_not GeneratedMessagePolicy.new(@amplifa_admin, @message).customer_send_test?
  end

  test "customer_send_test? returns false for other org customer" do
    # WHY: Customers can only test their own org's messages
    assert_not GeneratedMessagePolicy.new(@beta_user, @message).customer_send_test?
  end

  test "customer_send_test? returns false for deleted agent message" do
    @message.agent.mark_deleted!

    assert_not GeneratedMessagePolicy.new(@customer_admin, @message).customer_send_test?
  end

  # Scope tests
  test "Scope returns all messages for amplifa_admin" do
    # WHY: Admins need visibility across all organizations
    scope = GeneratedMessagePolicy::Scope.new(@amplifa_admin, GeneratedMessage).resolve
    assert_equal GeneratedMessage.count, scope.count
  end

  test "Scope returns only own org messages for customer" do
    Current.organization = organizations(:acme)
    # WHY: Customers should only see their organization's messages
    scope = GeneratedMessagePolicy::Scope.new(@customer_admin, GeneratedMessage).resolve
    scope.each do |message|
      assert_equal @customer_admin.organization_id, message.agent.organization_id
      assert_not message.agent.deleted?
    end
  end
end
