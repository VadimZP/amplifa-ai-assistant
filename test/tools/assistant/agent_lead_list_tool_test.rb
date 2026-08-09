# frozen_string_literal: true

require 'test_helper'

class Assistant::AgentLeadListToolTest < ActiveSupport::TestCase
  def setup
    @account = accounts(:customer_admin)
    @organization = organizations(:acme)
    act_as_acme_admin
    @tool = Assistant::AgentLeadListTool.new(account: @account, organization: @organization)
    @draft_agent = agents(:draft_agent)
  end

  def teardown
    Current.reset
  end

  test 'returns only agent leads from the tool organization' do
    result = call_tool

    ids = result['agent_leads'].map { |row| row['id'] }
    assert_includes ids, agent_leads(:john_in_draft).id
    assert_not_includes ids, agent_leads(:beta_lead_in_beta_agent).id,
                        'an agent lead from another organization must never be listed'
  end

  test 'returns nothing when the account has no active membership in the organization' do
    Current.reset

    result = call_tool

    assert_equal 0, result['total_count']
    assert_empty result['agent_leads']
  end

  test 'filters by agent id' do
    result = call_tool('agent_id' => @draft_agent.id)

    agent_ids = result['agent_leads'].map { |row| row.dig('agent', 'id') }.uniq
    assert_equal [@draft_agent.id], agent_ids
  end

  test 'a foreign organization agent id behaves exactly like a missing id' do
    foreign = call_tool('agent_id' => agents(:other_org_agent).id)
    missing = call_tool('agent_id' => -1)

    assert_equal 'Agent not found.', foreign['error']
    assert_equal missing, foreign
  end

  test 'filters by delivery status' do
    agent_leads(:john_in_draft).update!(delivery_status: 'in_sequence', sequence_position: 1)

    result = call_tool('agent_id' => @draft_agent.id, 'delivery_status' => 'in_sequence')

    assert_equal [agent_leads(:john_in_draft).id], result['agent_leads'].map { |row| row['id'] }
  end

  test 'searches by lead name' do
    result = call_tool('search' => 'Jane')

    assert_equal [agent_leads(:jane_in_draft).id], result['agent_leads'].map { |row| row['id'] }
  end

  test 'searches by full name with multiple words' do
    result = call_tool('search' => 'John Doe')

    ids = result['agent_leads'].map { |row| row['id'] }
    assert_includes ids, agent_leads(:john_in_draft).id
  end

  test 'rejects an unknown delivery status' do
    result = call_tool('delivery_status' => 'archived')

    assert_includes result['error'], "Unknown delivery_status 'archived'"
    assert_includes result['error'], AgentLead::DELIVERY_STATUSES.join(', ')
  end

  test 'rows expose lead and sequence fields without urls' do
    agent_leads(:john_in_draft).update!(delivery_status: 'in_sequence', sequence_position: 1)

    row = call_tool('agent_id' => @draft_agent.id, 'delivery_status' => 'in_sequence')['agent_leads'].sole

    assert_equal 'John Doe', row.dig('lead', 'name')
    assert_equal 'in_sequence', row['delivery_status']
    assert_equal 1, row['sequence_position']
    assert_not row.key?('url')
    assert_not row.dig('lead').key?('linkedin_url')
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

  def call_tool(args = {})
    JSON.parse(@tool.call(args))
  end
end
