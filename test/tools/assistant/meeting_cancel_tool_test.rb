# frozen_string_literal: true

require 'test_helper'

class Assistant::MeetingCancelToolTest < ActiveSupport::TestCase
  def setup
    @account = accounts(:customer_admin)
    @organization = organizations(:acme)
    Current.account = @account
    Current.organization = @organization
    Current.organization_membership = organization_memberships(:customer_admin_acme)
    @tool = Assistant::MeetingCancelTool.new(account: @account, organization: @organization)
  end

  def teardown
    Current.reset
  end

  test 'a customer cancellation marks the meeting pending_removal and leaves the interest status alone' do
    conversation = conversations(:acme_john_conversation)
    conversation.update_columns(interest_status: 'interested')
    meeting = keep_only(meetings(:scheduled_discovery))
    meeting.agent_lead.update_columns(meeting_booked_at: Time.current, meeting_notes: 'Initial discovery call')

    result = nil
    assert_no_difference -> { Meeting.count } do
      result = call_tool(conversation.id)
    end

    assert_nil result['error']
    assert_equal meeting.id, result['meeting_id']
    assert_equal 'John Doe', result['lead_name']
    assert_equal 'Example Corp', result['company']
    assert_equal 'scheduled', result['previous_status']
    assert_equal 'pending_removal', result['removal']
    assert_equal 'interested', result['interest_status']
    assert_not result.key?('url'), 'no url material for the model to build links from'

    assert_equal 'pending_removal', meeting.reload.status
    assert_equal 'interested', conversation.reload.interest_status, 'interest status must never change'
    assert_nil meeting.agent_lead.reload.meeting_booked_at, 'legacy booking flag must be cleared'
  end

  test 'stores the optional comment on the removal request' do
    conversation = conversations(:acme_john_conversation)
    meeting = keep_only(meetings(:scheduled_discovery))

    result = call_tool(conversation.id, comment: 'Lead asked to cancel, still interested')

    assert_nil result['error']
    assert_equal 'Lead asked to cancel, still interested', meeting.reload.removal_comment
  end

  test 'an amplifa admin cancellation deletes the meeting outright' do
    admin = accounts(:amplifa_admin)
    Current.reset
    Current.account = admin
    Current.organization = @organization
    tool = Assistant::MeetingCancelTool.new(account: admin, organization: @organization)
    conversation = conversations(:acme_john_conversation)
    meeting = keep_only(meetings(:scheduled_discovery))

    result = nil
    assert_difference -> { Meeting.count }, -1 do
      result = JSON.parse(tool.call({ 'conversation_id' => conversation.id }))
    end

    assert_nil result['error']
    assert_equal 'deleted', result['removal']
    assert_not Meeting.exists?(meeting.id)
  end

  test 'reports when the lead has no active meeting' do
    conversation = conversations(:acme_bounce_conversation)

    result = call_tool(conversation.id)

    assert_equal 'This lead has no active meeting to cancel.', result['error']
  end

  test 'reports no active meeting when the lead only has a terminal status' do
    conversation = conversations(:acme_jane_conversation)
    meeting = meetings(:completed_demo)

    result = nil
    assert_no_difference -> { Meeting.count } do
      result = call_tool(conversation.id)
    end

    assert_equal 'This lead has no active meeting to cancel.', result['error']
    assert_equal 'completed', meeting.reload.status
  end

  test 'a foreign organization id behaves exactly like a missing id and changes nothing' do
    foreign_conversation = conversations(:growth_lab_conversation)

    foreign = missing = nil
    assert_no_difference -> { Meeting.count } do
      foreign = call_tool(foreign_conversation.id)
      missing = call_tool(-1)
    end

    assert_equal 'Conversation not found.', foreign['error']
    assert_equal missing, foreign
  end

  test 'fails closed when the account has no active membership' do
    Current.reset
    conversation = conversations(:acme_john_conversation)
    meeting = keep_only(meetings(:scheduled_discovery))

    result = call_tool(conversation.id)

    assert_equal 'Conversation not found.', result['error']
    assert_equal 'scheduled', meeting.reload.status
  end

  test 'reports the tool as temporarily unavailable when the database is down' do
    raise_db_down = ->(*) { raise ActiveRecord::ConnectionNotEstablished, 'server refused connection' }

    Pundit.stub(:policy_scope!, raise_db_down) do
      result = call_tool(conversations(:acme_john_conversation).id)

      assert_equal Assistant::BaseTool::UNAVAILABLE_MESSAGE, result['error']
    end
  end

  private

  # Leaves the given meeting as the lead's only one, so latest_active_meeting is deterministic.
  def keep_only(meeting)
    Meeting.where(lead_id: meeting.lead_id).where.not(id: meeting.id).destroy_all
    meeting
  end

  def call_tool(conversation_id, comment: nil)
    args = { 'conversation_id' => conversation_id }
    args['comment'] = comment if comment
    JSON.parse(@tool.call(args))
  end
end
