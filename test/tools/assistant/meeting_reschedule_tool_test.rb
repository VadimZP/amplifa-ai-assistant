# frozen_string_literal: true

require 'test_helper'

class Assistant::MeetingRescheduleToolTest < ActiveSupport::TestCase
  def setup
    @account = accounts(:customer_admin)
    @organization = organizations(:acme)
    Current.account = @account
    Current.organization = @organization
    Current.organization_membership = organization_memberships(:customer_admin_acme)
    @tool = Assistant::MeetingRescheduleTool.new(account: @account, organization: @organization)
    @new_time = 6.days.from_now.change(hour: 10, min: 30, sec: 0)
  end

  def teardown
    Current.reset
  end

  test 'moves a scheduled meeting and marks it rescheduled' do
    conversation = conversations(:acme_john_conversation)
    meeting = keep_only(meetings(:scheduled_discovery))
    original_time = meeting.scheduled_at

    result = call_tool(conversation.id, @new_time.iso8601)

    assert_nil result['error']
    assert_equal meeting.id, result['meeting_id']
    assert_equal 'John Doe', result['lead_name']
    assert_equal 'scheduled', result['previous_status']
    assert_equal 'rescheduled', result['status']
    assert_equal original_time.iso8601, Time.iso8601(result['previous_scheduled_at']).iso8601
    assert_equal @new_time.iso8601, Time.iso8601(result['scheduled_at']).iso8601
    assert_not result.key?('url'), 'no url material for the model to build links from'

    meeting.reload
    assert_equal 'rescheduled', meeting.status
    assert_equal @new_time, meeting.scheduled_at
  end

  test 'setting the first time on a scheduling meeting books it as scheduled' do
    conversation = conversations(:acme_john_conversation)
    Meeting.where(lead: conversation.lead).destroy_all
    meeting = agent_leads(:john_in_draft).schedule_meeting!(status: 'scheduling')

    result = call_tool(conversation.id, @new_time.iso8601)

    assert_nil result['error']
    assert_equal 'scheduling', result['previous_status']
    assert_equal 'scheduled', result['status']
    assert_nil result['previous_scheduled_at']
    assert_equal 'scheduled', meeting.reload.status
    assert_equal @new_time, meeting.scheduled_at
  end

  test 'rescheduling to the current time is a no-op that reports the meeting as already booked' do
    conversation = conversations(:acme_john_conversation)
    meeting = keep_only(meetings(:scheduled_discovery))

    result = call_tool(conversation.id, meeting.scheduled_at.iso8601)

    assert_equal 'The meeting is already scheduled at this time.', result['error']
    assert_equal 'scheduled', meeting.reload.status, 'status must not flip to rescheduled'
  end

  test 'reports no active meeting when the lead only has a terminal status' do
    conversation = conversations(:acme_jane_conversation)
    meeting = meetings(:completed_demo)
    original_time = meeting.scheduled_at

    result = call_tool(conversation.id, @new_time.iso8601)

    assert_equal 'This lead has no active meeting. Use meeting_create to schedule one.', result['error']
    assert_equal original_time, meeting.reload.scheduled_at
  end

  test 'reports when the lead has no active meeting' do
    conversation = conversations(:acme_bounce_conversation)

    result = call_tool(conversation.id, @new_time.iso8601)

    assert_equal 'This lead has no active meeting. Use meeting_create to schedule one.', result['error']
  end

  test 'rejects malformed date/time input with a correction hint and changes nothing' do
    conversation = conversations(:acme_john_conversation)
    meeting = keep_only(meetings(:scheduled_discovery))
    original_time = meeting.scheduled_at

    ['222:00', '1:13 fm', 'Fuptember 5 at 3pm'].each do |garbage|
      result = call_tool(conversation.id, garbage)

      assert_equal 'The requested date/time is invalid.', result['error'], "expected #{garbage.inspect} to be rejected"
      assert_includes result['expected_format'], 'ISO 8601'
      assert_equal garbage, result['received']
    end

    assert_equal original_time, meeting.reload.scheduled_at
    assert_equal 'scheduled', meeting.status
  end

  test 'rejects a past time and changes nothing' do
    conversation = conversations(:acme_john_conversation)
    meeting = keep_only(meetings(:scheduled_discovery))
    original_time = meeting.scheduled_at

    result = call_tool(conversation.id, 2.days.ago.iso8601)

    assert_includes result['error'], 'in the past'
    assert_equal original_time, meeting.reload.scheduled_at
  end

  test 'includes the busy-day meeting count in the result' do
    conversation = conversations(:acme_john_conversation)
    keep_only(meetings(:scheduled_discovery))
    meetings(:completed_demo).update_columns(scheduled_at: @new_time.change(hour: 9))

    result = call_tool(conversation.id, @new_time.iso8601)

    assert_nil result['error']
    assert_equal 2, result['same_day_meeting_count']
  end

  test 'a foreign organization id behaves exactly like a missing id and changes nothing' do
    foreign_conversation = conversations(:growth_lab_conversation)

    foreign = call_tool(foreign_conversation.id, @new_time.iso8601)
    missing = call_tool(-1, @new_time.iso8601)

    assert_equal 'Conversation not found.', foreign['error']
    assert_equal missing, foreign
  end

  test 'fails closed when the account has no active membership' do
    Current.reset
    conversation = conversations(:acme_john_conversation)
    meeting = keep_only(meetings(:scheduled_discovery))
    original_time = meeting.scheduled_at

    result = call_tool(conversation.id, @new_time.iso8601)

    assert_equal 'Conversation not found.', result['error']
    assert_equal original_time, meeting.reload.scheduled_at
  end

  test 'reports the tool as temporarily unavailable when the database is down' do
    raise_db_down = ->(*) { raise ActiveRecord::ConnectionNotEstablished, 'server refused connection' }

    Pundit.stub(:policy_scope!, raise_db_down) do
      result = call_tool(conversations(:acme_john_conversation).id, @new_time.iso8601)

      assert_equal Assistant::BaseTool::UNAVAILABLE_MESSAGE, result['error']
    end
  end

  private

  # Leaves the given meeting as the lead's only one, so latest_active_meeting is deterministic.
  def keep_only(meeting)
    Meeting.where(lead_id: meeting.lead_id).where.not(id: meeting.id).destroy_all
    meeting
  end

  def call_tool(conversation_id, scheduled_at)
    JSON.parse(@tool.call({ 'conversation_id' => conversation_id, 'scheduled_at' => scheduled_at }))
  end
end
