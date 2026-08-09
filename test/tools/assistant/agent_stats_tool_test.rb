# frozen_string_literal: true

require 'test_helper'

class Assistant::AgentStatsToolTest < ActiveSupport::TestCase
  def setup
    @account = accounts(:customer_admin)
    @organization = organizations(:acme)
    act_as_acme_admin
    @tool = Assistant::AgentStatsTool.new(account: @account, organization: @organization)
    @draft_agent = agents(:draft_agent)
  end

  def teardown
    Current.reset
  end

  test 'returns delivery status counts for the organization' do
    agent_leads(:john_in_draft).update!(delivery_status: 'in_sequence')

    result = call_tool

    assert_equal acme_visible_agent_leads.count, result['total']
    assert_equal acme_visible_agent_leads.where(delivery_status: 'in_sequence').count,
                 result.dig('by_delivery_status', 'in_sequence')
    AgentLead::DELIVERY_STATUSES.each do |status|
      assert result['by_delivery_status'].key?(status)
    end
  end

  test 'returns nothing when the account has no active membership in the organization' do
    Current.reset

    result = call_tool

    assert_equal 0, result['total']
    AgentLead::DELIVERY_STATUSES.each do |status|
      assert_equal 0, result.dig('by_delivery_status', status)
    end
  end

  test 'filters stats to one agent' do
    agent_leads(:john_in_draft).update!(delivery_status: 'in_sequence')
    agent_leads(:jane_in_draft).update!(delivery_status: 'replied')

    result = call_tool('agent_id' => @draft_agent.id)

    assert_equal 2, result['total']
    assert_equal 1, result.dig('by_delivery_status', 'in_sequence')
    assert_equal 1, result.dig('by_delivery_status', 'replied')
    assert_equal @draft_agent.id, result.dig('agent', 'id')
    assert_equal @draft_agent.name, result.dig('agent', 'name')
  end

  test 'a foreign organization agent id behaves exactly like a missing id' do
    foreign = call_tool('agent_id' => agents(:other_org_agent).id)
    missing = call_tool('agent_id' => -1)

    assert_equal 'Agent not found.', foreign['error']
    assert_equal missing, foreign
  end

  test 'does not include other organization agent leads in totals' do
    result = call_tool

    assert_equal acme_visible_agent_leads.count, result['total']
    assert_operator result['total'], :<, AgentLead.count
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

  def acme_visible_agent_leads
    AgentLead.joins(:agent)
             .merge(Agent.not_deleted.where(organization_id: @organization.id))
             .joins(:lead)
             .merge(Lead.visible_in_customer_agents)
  end

  def call_tool(args = {})
    JSON.parse(@tool.call(args))
  end
end
