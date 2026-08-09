# frozen_string_literal: true

require 'test_helper'

class Assistant::ConversationReadToolTest < ActiveSupport::TestCase
  def setup
    @account = accounts(:customer_admin)
    @organization = organizations(:acme)
    Current.account = @account
    Current.organization = @organization
    Current.organization_membership = organization_memberships(:customer_admin_acme)
    @tool = Assistant::ConversationReadTool.new(account: @account, organization: @organization)
  end

  def teardown
    Current.reset
  end

  test 'returns the thread for a conversation in the tool organization' do
    conversation = conversations(:acme_john_conversation)

    result = call_tool(conversation.id)

    assert_equal conversation.id, result['id']
    assert_equal 'John Doe', result['lead']['name']
    assert_not result.key?('url'), 'no url material for the model to build links from'
    assert result.key?('messages')
  end

  test 'a foreign organization id behaves exactly like a missing id' do
    # WHY this is the key cross-org test: a distinguishable response would let a prompt-injected
    # model probe which ids exist in other organizations.
    foreign = call_tool(conversations(:growth_lab_conversation).id)
    missing = call_tool(-1)

    assert_equal 'Conversation not found.', foreign['error']
    assert_equal missing, foreign
  end

  test 'fails closed when the account has no active membership' do
    Current.reset

    result = call_tool(conversations(:acme_john_conversation).id)

    assert_equal 'Conversation not found.', result['error']
  end

  test 'does not mark the conversation as read' do
    conversation = conversations(:acme_john_conversation)

    assert_no_difference -> { ConversationRead.count } do
      call_tool(conversation.id)
    end
    assert conversation.reload.unread_for?(@account), 'asking the assistant is not reviewing the inbox'
  end

  test 'reports the tool as temporarily unavailable when the database is down' do
    raise_db_down = ->(*) { raise ActiveRecord::ConnectionNotEstablished, 'server refused connection' }

    Pundit.stub(:policy_scope!, raise_db_down) do
      result = call_tool(conversations(:acme_john_conversation).id)

      assert_equal Assistant::BaseTool::UNAVAILABLE_MESSAGE, result['error']
    end
  end

  private

  def call_tool(conversation_id)
    JSON.parse(@tool.call({ 'conversation_id' => conversation_id }))
  end
end
