# frozen_string_literal: true

require 'test_helper'

class Assistant::MeetingListToolTest < ActiveSupport::TestCase
  def setup
    @account = accounts(:customer_admin)
    @organization = organizations(:acme)
    act_as_acme_admin
    @tool = Assistant::MeetingListTool.new(account: @account, organization: @organization)
  end

  def teardown
    Current.reset
  end

  test 'returns only meetings from the tool organization' do
    foreign_meeting = create_foreign_meeting

    result = call_tool

    ids = result['meetings'].map { |row| row['id'] }
    assert_includes ids, meetings(:scheduled_discovery).id
    assert_not_includes ids, foreign_meeting.id,
                        'a meeting from another organization must never be listed'
    assert_equal acme_meeting_count, result['total_count']
  end

  test 'returns nothing when the account has no active membership in the organization' do
    Current.reset

    result = call_tool

    assert_equal 0, result['total_count']
    assert_empty result['meetings']
  end

  test 'searches by lead name and company' do
    result = call_tool('search' => 'john')

    ids = result['meetings'].map { |row| row['id'] }
    assert_includes ids, meetings(:scheduled_discovery).id
    assert_includes ids, meetings(:no_show_meeting).id
    assert_not_includes ids, meetings(:completed_demo).id
  end

  test 'searches by full name with multiple words' do
    result = call_tool('search' => 'John Doe')

    ids = result['meetings'].map { |row| row['id'] }
    assert_includes ids, meetings(:scheduled_discovery).id
    assert_includes ids, meetings(:no_show_meeting).id
  end

  test 'filters by no_show status' do
    result = call_tool('status' => 'no_show')

    assert_equal [meetings(:no_show_meeting).id], result['meetings'].map { |row| row['id'] }
    assert_equal 1, result['status_counts']['no_show']
  end

  test 'filters scheduled tab to scheduled and rescheduled meetings' do
    rescheduled = meetings(:scheduled_discovery)
    rescheduled.update!(status: 'rescheduled')

    result = call_tool('status' => 'scheduled')

    assert_equal [rescheduled.id], result['meetings'].map { |row| row['id'] }
  end

  test 'includes raw status, in_flight flag and conversation id for each row' do
    conversation = conversations(:acme_john_conversation)
    meeting = meetings(:no_show_meeting)

    result = call_tool('search' => 'john', 'status' => 'no_show')
    row = result['meetings'].sole

    assert_equal meeting.id, row['id']
    assert_equal 'no_show', row['status']
    assert_equal 'no_show', row['display_status']
    assert row['terminal']
    assert_not row['in_flight']
    assert_equal conversation.id, row['conversation_id']
    assert_not row.key?('url'), 'no url material for the model to build links from'
  end

  test 'filters upcoming in-flight meetings only' do
    past_scheduled = meetings(:scheduled_discovery)
    past_scheduled.update!(scheduled_at: 1.day.ago)

    result = call_tool('upcoming_only' => true)

    ids = result['meetings'].map { |row| row['id'] }
    assert_not_includes ids, past_scheduled.id
    assert_not_includes ids, meetings(:no_show_meeting).id
  end

  test 'clamps limit and offset regardless of what the model sends' do
    result = call_tool('limit' => 50_000, 'offset' => -5)

    assert_equal acme_meeting_count, result['returned_count']

    result = call_tool('limit' => 1)
    assert_equal 1, result['returned_count']
  end

  test 'rejects unknown enum values with a corrective error' do
    result = call_tool('status' => 'DROP TABLE meetings')

    assert_match(/Unknown status/, result['error'])
    assert_match(/scheduled/, result['error'])
  end

  test 'reports the tool as temporarily unavailable when the database is down' do
    raise_db_down = ->(*) { raise ActiveRecord::ConnectionNotEstablished, 'server refused connection' }

    Pundit.stub(:policy_scope!, raise_db_down) do
      result = call_tool

      assert_equal Assistant::BaseTool::UNAVAILABLE_MESSAGE, result['error']
    end
  end

  private

  def acme_meeting_count
    Meeting.where(organization_id: @organization.id).count
  end

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

  def act_as_acme_admin
    Current.account = @account
    Current.organization = @organization
    Current.organization_membership = organization_memberships(:customer_admin_acme)
  end

  def call_tool(args = {})
    JSON.parse(@tool.call(args))
  end
end
