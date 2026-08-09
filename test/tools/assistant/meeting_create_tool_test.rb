# frozen_string_literal: true

require 'test_helper'

class Assistant::MeetingCreateToolTest < ActiveSupport::TestCase
  def setup
    @account = accounts(:customer_admin)
    @organization = organizations(:acme)
    Current.account = @account
    Current.organization = @organization
    Current.organization_membership = organization_memberships(:customer_admin_acme)
    @tool = Assistant::MeetingCreateTool.new(account: @account, organization: @organization)
    @future_time = 5.days.from_now.change(hour: 15, min: 0, sec: 0)
  end

  def teardown
    Current.reset
  end

  test 'books a scheduled meeting when a time is given' do
    conversation = conversations(:acme_john_conversation)
    Meeting.where(lead: conversation.lead).destroy_all

    result = nil
    assert_difference -> { Meeting.count }, 1 do
      result = call_tool(conversation.id, scheduled_at: @future_time.iso8601, notes: 'Demo of the new plan')
    end

    assert_nil result['error']
    assert_equal 'John Doe', result['lead_name']
    assert_equal 'Example Corp', result['company']
    assert_equal 'scheduled', result['status']
    assert_equal @future_time.iso8601, Time.iso8601(result['scheduled_at']).iso8601
    assert_equal 'Demo of the new plan', result['notes']
    assert_equal 1, result['same_day_meeting_count']
    assert_not result.key?('url'), 'no url material for the model to build links from'

    meeting = Meeting.where(lead: conversation.lead).order(:created_at).last
    assert_equal 'scheduled', meeting.status
    assert_equal @future_time, meeting.scheduled_at
  end

  test 'creates a scheduling meeting when no time is agreed yet' do
    conversation = conversations(:acme_john_conversation)
    Meeting.where(lead: conversation.lead).destroy_all

    result = nil
    assert_difference -> { Meeting.count }, 1 do
      result = call_tool(conversation.id)
    end

    assert_nil result['error']
    assert_equal 'scheduling', result['status']
    assert_nil result['scheduled_at']
    assert_nil result['same_day_meeting_count']
  end

  test 'booking the same lead at the same time reports the existing meeting and does nothing' do
    conversation = conversations(:acme_john_conversation)
    meeting = meetings(:scheduled_discovery)
    Meeting.where(lead: conversation.lead).where.not(id: meeting.id).destroy_all

    result = nil
    assert_no_difference -> { Meeting.count } do
      result = call_tool(conversation.id, scheduled_at: meeting.scheduled_at.iso8601)
    end

    assert_equal 'A meeting with this lead at this time already exists.', result['error']
    assert_equal meeting.id, result['meeting_id']
  end

  test 'books a new meeting when the lead only has a terminal no_show meeting' do
    conversation = conversations(:acme_john_conversation)
    no_show = meetings(:no_show_meeting)
    Meeting.where(lead: conversation.lead).where.not(id: no_show.id).destroy_all

    result = nil
    assert_difference -> { Meeting.count }, 1 do
      result = call_tool(conversation.id, scheduled_at: @future_time.iso8601)
    end

    assert_nil result['error']
    assert_equal 'scheduled', result['status']
    assert_equal @future_time.iso8601, Time.iso8601(result['scheduled_at']).iso8601
    assert_equal 'no_show', no_show.reload.status, 'the prior no_show record must be left unchanged'
  end

  test 'a lead with an active meeting at another time is steered to meeting_reschedule' do
    conversation = conversations(:acme_john_conversation)
    meeting = meetings(:scheduled_discovery)
    Meeting.where(lead: conversation.lead).where.not(id: meeting.id).destroy_all

    result = nil
    assert_no_difference -> { Meeting.count } do
      result = call_tool(conversation.id, scheduled_at: @future_time.iso8601)
    end

    assert_includes result['error'], 'already has an active meeting'
    assert_includes result['error'], 'meeting_reschedule'
    assert_equal meeting.id, result['meeting_id']
  end

  test 'rejects malformed date/time input with a correction hint and writes nothing' do
    conversation = conversations(:acme_john_conversation)
    Meeting.where(lead: conversation.lead).destroy_all

    ['222:00', '1:13 fm', 'Fuptember 5 at 3pm', '2026-13-45T25:99:00Z'].each do |garbage|
      result = nil
      assert_no_difference -> { Meeting.count } do
        result = call_tool(conversation.id, scheduled_at: garbage)
      end

      assert_equal 'The requested date/time is invalid.', result['error'], "expected #{garbage.inspect} to be rejected"
      assert_includes result['expected_format'], 'ISO 8601'
      assert_equal garbage, result['received']
    end
  end

  test 'rejects a past time and writes nothing' do
    conversation = conversations(:acme_john_conversation)
    Meeting.where(lead: conversation.lead).destroy_all

    result = nil
    assert_no_difference -> { Meeting.count } do
      result = call_tool(conversation.id, scheduled_at: 2.days.ago.iso8601)
    end

    assert_includes result['error'], 'in the past'
    assert_includes result['expected_format'], 'ISO 8601'
  end

  test 'rejects a time more than two years ahead and writes nothing' do
    conversation = conversations(:acme_john_conversation)
    Meeting.where(lead: conversation.lead).destroy_all

    result = nil
    assert_no_difference -> { Meeting.count } do
      result = call_tool(conversation.id, scheduled_at: 3.years.from_now.iso8601)
    end

    assert_includes result['error'], 'more than 2 years ahead'
  end

  test 'counts only active meetings on the same day for the busy-day reminder' do
    conversation = conversations(:acme_john_conversation)
    meetings(:scheduled_discovery).destroy
    meetings(:no_show_meeting).destroy
    # Same day, active (completed still counts): included. Same day but cancelled: excluded.
    meetings(:completed_demo).update_columns(scheduled_at: @future_time.change(hour: 9))
    meetings(:cancelled_meeting).update_columns(scheduled_at: @future_time.change(hour: 11))

    result = call_tool(conversation.id, scheduled_at: @future_time.iso8601)

    assert_nil result['error']
    assert_equal 2, result['same_day_meeting_count']
  end

  test 'a foreign organization id behaves exactly like a missing id and creates nothing' do
    foreign_conversation = conversations(:growth_lab_conversation)

    foreign = missing = nil
    assert_no_difference -> { Meeting.count } do
      foreign = call_tool(foreign_conversation.id, scheduled_at: @future_time.iso8601)
      missing = call_tool(-1, scheduled_at: @future_time.iso8601)
    end

    assert_equal 'Conversation not found.', foreign['error']
    assert_equal missing, foreign
  end

  test 'fails closed when the account has no active membership' do
    Current.reset
    conversation = conversations(:acme_john_conversation)

    result = nil
    assert_no_difference -> { Meeting.count } do
      result = call_tool(conversation.id, scheduled_at: @future_time.iso8601)
    end

    assert_equal 'Conversation not found.', result['error']
  end

  test 'reports when no campaign lead matches the conversation' do
    conversation = conversations(:acme_bounce_conversation)

    result = nil
    assert_no_difference -> { Meeting.count } do
      result = call_tool(conversation.id, scheduled_at: @future_time.iso8601)
    end

    assert_equal 'No matching campaign lead found for this conversation.', result['error']
  end

  test 'reports the tool as temporarily unavailable when the database is down' do
    raise_db_down = ->(*) { raise ActiveRecord::ConnectionNotEstablished, 'server refused connection' }

    Pundit.stub(:policy_scope!, raise_db_down) do
      result = call_tool(conversations(:acme_john_conversation).id, scheduled_at: @future_time.iso8601)

      assert_equal Assistant::BaseTool::UNAVAILABLE_MESSAGE, result['error']
    end
  end

  private

  def call_tool(conversation_id, scheduled_at: nil, notes: nil)
    args = { 'conversation_id' => conversation_id }
    args['scheduled_at'] = scheduled_at if scheduled_at
    args['notes'] = notes if notes
    JSON.parse(@tool.call(args))
  end
end
