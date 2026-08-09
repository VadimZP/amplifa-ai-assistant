# frozen_string_literal: true

require 'test_helper'

class Assistant::AgentListToolTest < ActiveSupport::TestCase
  def setup
    @account = accounts(:customer_admin)
    @organization = organizations(:acme)
    act_as_acme_admin
    @tool = Assistant::AgentListTool.new(account: @account, organization: @organization)
  end

  def teardown
    Current.reset
  end

  test 'returns only agents from the tool organization' do
    result = call_tool

    ids = result['agents'].map { |row| row['id'] }
    assert_includes ids, agents(:active_agent).id
    assert_not_includes ids, agents(:other_org_agent).id,
                        'an agent from another organization must never be listed'
  end

  test 'returns nothing when the account has no active membership in the organization' do
    Current.reset

    result = call_tool

    assert_equal 0, result['total_count']
    assert_empty result['agents']
  end

  test 'searches by agent name' do
    result = call_tool('search' => 'Active Campaign')

    assert_equal [agents(:active_agent).id], result['agents'].map { |row| row['id'] }
  end

  test 'filters by status' do
    result = call_tool('status' => 'draft')

    ids = result['agents'].map { |row| row['id'] }
    assert_includes ids, agents(:draft_agent).id
    assert_not_includes ids, agents(:active_agent).id
  end

  test 'rejects an unknown status' do
    result = call_tool('status' => 'archived')

    assert_includes result['error'], "Unknown status 'archived'"
    assert_includes result['error'], Agent::VISIBLE_STATUSES.join(', ')
  end

  test 'exposes pause and resume eligibility flags' do
    active = agents(:active_agent)
    active.update!(launched_at: 2.days.ago, paused_at: nil, status: 'active')

    row = call_tool('search' => active.name)['agents'].sole

    assert row['can_pause']
    assert_not row['can_resume']
  end

  test 'clamps limit regardless of what the model sends' do
    result = call_tool('limit' => 50_000)

    assert_equal scoped_acme_agents.count, result['returned_count']

    result = call_tool('limit' => 0)
    assert_equal 1, result['returned_count']
  end

  test 'reports the tool as temporarily unavailable when the database is down' do
    raise_db_down = ->(*) { raise ActiveRecord::ConnectionNotEstablished, 'server refused connection' }

    Pundit.stub(:policy_scope!, raise_db_down) do
      result = call_tool

      assert_equal Assistant::BaseTool::UNAVAILABLE_MESSAGE, result['error']
    end
  end

  private

  def act_as_acme_admin
    Current.account = @account
    Current.organization = @organization
    Current.organization_membership = organization_memberships(:customer_admin_acme)
  end

  def scoped_acme_agents
    Agent.where(organization_id: @organization.id).not_deleted
  end

  def call_tool(args = {})
    JSON.parse(@tool.call(args))
  end
end
