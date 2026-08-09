# frozen_string_literal: true

require 'test_helper'

class Assistant::MeetingReadToolTest < ActiveSupport::TestCase
  def setup
    @account = accounts(:customer_admin)
    @organization = organizations(:acme)
    Current.account = @account
    Current.organization = @organization
    Current.organization_membership = organization_memberships(:customer_admin_acme)
    @tool = Assistant::MeetingReadTool.new(account: @account, organization: @organization)
  end

  def teardown
    Current.reset
  end

  test 'returns full details for a meeting in the tool organization' do
    meeting = meetings(:no_show_meeting)
    conversation = conversations(:acme_john_conversation)

    result = call_tool(meeting.id)

    assert_nil result['error']
    assert_equal meeting.id, result['id']
    assert_equal 'no_show', result['status']
    assert_equal 'no_show', result['display_status']
    assert result['terminal']
    assert_not result['in_flight']
    assert_equal 'John Doe', result['lead']['name']
    assert_equal conversation.id, result['conversation_id']
    assert_includes result['scheduling_hint'], 'meeting_create'
    assert_not result.key?('url'), 'no url material for the model to build links from'
  end

  test 'includes reschedule hint for an in-flight meeting' do
    meeting = meetings(:scheduled_discovery)

    result = call_tool(meeting.id)

    assert result['in_flight']
    assert_not result['terminal']
    assert_includes result['scheduling_hint'], 'meeting_reschedule'
  end

  test 'a foreign organization id behaves exactly like a missing id' do
    foreign_meeting = create_foreign_meeting

    foreign = call_tool(foreign_meeting.id)
    missing = call_tool(-1)

    assert_equal 'Meeting not found.', foreign['error']
    assert_equal missing, foreign
  end

  test 'fails closed when the account has no active membership' do
    Current.reset

    result = call_tool(meetings(:scheduled_discovery).id)

    assert_equal 'Meeting not found.', result['error']
  end

  test 'reports the tool as temporarily unavailable when the database is down' do
    raise_db_down = ->(*) { raise ActiveRecord::ConnectionNotEstablished, 'server refused connection' }

    Pundit.stub(:policy_scope!, raise_db_down) do
      result = call_tool(meetings(:scheduled_discovery).id)

      assert_equal Assistant::BaseTool::UNAVAILABLE_MESSAGE, result['error']
    end
  end

  private

  def create_foreign_meeting
    agent_lead = agent_leads(:beta_lead_in_beta_agent)
    Meeting.create!(
      organization: organizations(:beta),
      agent_lead: agent_lead,
      lead: agent_lead.lead,
      agent: agent_lead.agent,
      status: 'scheduled',
      scheduled_at: 2.days.from_now,
      source: 'manual'
    )
  end

  def call_tool(meeting_id)
    JSON.parse(@tool.call({ 'meeting_id' => meeting_id }))
  end
end
