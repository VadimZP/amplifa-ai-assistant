# frozen_string_literal: true

require 'test_helper'

class Assistant::AgentResumeCampaignToolTest < ActiveSupport::TestCase
  def setup
    @account = accounts(:customer_admin)
    @organization = organizations(:acme)
    act_as_acme_admin
    @tool = Assistant::AgentResumeCampaignTool.new(account: @account, organization: @organization)
    @agent = agents(:active_agent)
    @agent.update!(launched_at: 2.days.ago, paused_at: 1.hour.ago, status: 'paused')
  end

  def teardown
    Current.reset
  end

  test 'resumes a paused launched agent and reports the status change' do
    result = call_tool(@agent.id)

    assert_equal 'paused', result['previous_status']
    assert_equal 'active', result['status']
    assert_equal 'Active Campaign', result['name']
    assert_nil result['paused_at']
    assert_equal 'active', @agent.reload.status
    assert_nil @agent.paused_at
  end

  test 'a foreign organization id behaves exactly like a missing id and mutates nothing' do
    foreign_agent = agents(:other_org_agent)
    previous_status = foreign_agent.status

    foreign = call_tool(foreign_agent.id)
    missing = call_tool(-1)

    assert_equal 'Agent not found.', foreign['error']
    assert_equal missing, foreign
    assert_equal previous_status, foreign_agent.reload.status
  end

  test 'fails closed when the account has no active membership' do
    Current.reset

    result = call_tool(@agent.id)

    assert_equal 'Agent not found.', result['error']
    assert_equal 'paused', @agent.reload.status
  end

  test 'rejects an agent that cannot be resumed without mutating it' do
    @agent.update!(launched_at: 2.days.ago, paused_at: nil, status: 'active')

    result = call_tool(@agent.id)

    assert_equal 'This agent cannot be resumed right now.', result['error']
    assert_equal 'active', @agent.reload.status
  end

  test 'denies customer users who are not organization admins' do
    Current.account = accounts(:customer_user)
    Current.organization_membership = organization_memberships(:customer_user_acme)

    result = call_tool(@agent.id)

    assert_equal 'You are not allowed to do that.', result['error']
    assert_equal 'paused', @agent.reload.status
  end

  test 'reports the tool as temporarily unavailable when the database is down' do
    raise_db_down = ->(*) { raise ActiveRecord::ConnectionNotEstablished, 'server refused connection' }

    Pundit.stub(:policy_scope!, raise_db_down) do
      result = call_tool(@agent.id)

      assert_equal Assistant::BaseTool::UNAVAILABLE_MESSAGE, result['error']
    end
  end

  private

  def act_as_acme_admin
    Current.account = @account
    Current.organization = @organization
    Current.organization_membership = organization_memberships(:customer_admin_acme)
  end

  def call_tool(agent_id)
    JSON.parse(@tool.call({ 'agent_id' => agent_id }))
  end
end
