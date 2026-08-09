# frozen_string_literal: true

require 'test_helper'

class Assistant::ConversationUpdateInterestStatusToolTest < ActiveSupport::TestCase
  def setup
    @account = accounts(:customer_admin)
    @organization = organizations(:acme)
    Current.account = @account
    Current.organization = @organization
    Current.organization_membership = organization_memberships(:customer_admin_acme)
    @tool = Assistant::ConversationUpdateInterestStatusTool.new(account: @account, organization: @organization)
  end

  def teardown
    Current.reset
  end

  test 'updates the status and reports the previous and new values' do
    conversation = conversations(:acme_john_conversation)

    result = call_tool(conversation.id, 'interested')

    assert_nil result['previous_interest_status']
    assert_equal 'interested', result['interest_status']
    assert_equal 'John Doe', result['lead_name']
    assert_not result.key?('url'), 'no url material for the model to build links from'
    assert_equal 'interested', conversation.reload.interest_status
    # John's agent lead already has an active meeting, so no new one is created.
    assert_equal 'unchanged', result['meeting_effect']
  end

  test 'reports a created meeting when a positive status books one' do
    conversation = conversations(:acme_john_conversation)
    Meeting.where(lead: conversation.lead).destroy_all

    result = nil
    assert_difference -> { Meeting.count }, 1 do
      result = call_tool(conversation.id, 'meeting_request')
    end

    assert_equal 'created', result['meeting_effect']
    assert_equal 'scheduling', Meeting.where(lead: conversation.lead).order(:created_at).last.status
  end

  test 'reports a removed meeting when moving away from a positive status' do
    conversation = conversations(:acme_john_conversation)
    conversation.update_columns(interest_status: 'interested')
    meeting = meetings(:scheduled_discovery)

    result = call_tool(conversation.id, 'not_interested')

    assert_equal 'removed', result['meeting_effect']
    # A customer actor requests removal rather than destroying outright.
    assert_equal 'pending_removal', meeting.reload.status
  end

  test 'a foreign organization id behaves exactly like a missing id and mutates nothing' do
    foreign_conversation = conversations(:growth_lab_conversation)

    foreign = call_tool(foreign_conversation.id, 'interested')
    missing = call_tool(-1, 'interested')

    assert_equal 'Conversation not found.', foreign['error']
    assert_equal missing, foreign
    assert_nil foreign_conversation.reload.interest_status
  end

  test 'fails closed when the account has no active membership' do
    Current.reset
    conversation = conversations(:acme_john_conversation)

    result = call_tool(conversation.id, 'interested')

    assert_equal 'Conversation not found.', result['error']
    assert_nil conversation.reload.interest_status
  end

  test 'rejects an unknown interest status without touching the conversation' do
    conversation = conversations(:acme_john_conversation)

    result = call_tool(conversation.id, 'archived')

    assert_includes result['error'], "Unknown interest_status 'archived'"
    assert_includes result['error'], 'interested, meeting_request, not_interested, wrong_person'
    assert_nil conversation.reload.interest_status
  end

  test 'setting the already-current status is a success no-op' do
    conversation = conversations(:acme_john_conversation)
    conversation.update_columns(interest_status: 'not_interested')

    result = nil
    assert_no_difference -> { Meeting.count } do
      result = call_tool(conversation.id, 'not_interested')
    end

    assert_nil result['error']
    assert_equal 'not_interested', result['previous_interest_status']
    assert_equal 'not_interested', result['interest_status']
    assert_equal 'unchanged', result['meeting_effect']
  end

  test 'surfaces the human-readable service error when no campaign lead matches' do
    conversation = conversations(:acme_bounce_conversation)

    result = call_tool(conversation.id, 'interested')

    assert_equal 'No matching campaign lead found for this conversation.', result['error']
    assert_nil conversation.reload.interest_status
  end

  test 'reports the tool as temporarily unavailable when the database is down' do
    raise_db_down = ->(*) { raise ActiveRecord::ConnectionNotEstablished, 'server refused connection' }

    Pundit.stub(:policy_scope!, raise_db_down) do
      result = call_tool(conversations(:acme_john_conversation).id, 'interested')

      assert_equal Assistant::BaseTool::UNAVAILABLE_MESSAGE, result['error']
    end
  end

  private

  def call_tool(conversation_id, interest_status)
    JSON.parse(@tool.call({ 'conversation_id' => conversation_id, 'interest_status' => interest_status }))
  end
end
