# frozen_string_literal: true

require 'test_helper'

class Assistant::LeadSearchToolTest < ActiveSupport::TestCase
  def setup
    @account = accounts(:customer_admin)
    @organization = organizations(:acme)
    act_as_acme_admin
    @tool = Assistant::LeadSearchTool.new(account: @account, organization: @organization)
  end

  def teardown
    Current.reset
  end

  test 'returns only leads from the tool organization' do
    result = call_tool('query' => 'example')

    ids = result['leads'].map { |row| row['id'] }
    assert_includes ids, leads(:john_doe).id
    assert_not_includes ids, leads(:growth_lab_lead).id,
                        'a lead from another organization must never be listed'
    assert_not_includes ids, leads(:beta_lead).id
  end

  test 'returns nothing when the account has no active membership in the organization' do
    Current.reset

    result = call_tool('query' => 'example')

    assert_equal 0, result['total_count']
    assert_empty result['leads']
  end

  test 'searches by first name, email and company' do
    result = call_tool('query' => 'jane')
    assert_equal [leads(:jane_smith).id], result['leads'].map { |row| row['id'] }

    result = call_tool('query' => 'john.doe@example.com')
    assert_equal [leads(:john_doe).id], result['leads'].map { |row| row['id'] }

    result = call_tool('query' => 'test corp')
    assert_equal [leads(:jane_smith).id], result['leads'].map { |row| row['id'] }
  end

  test 'searches by full name with multiple words' do
    result = call_tool('query' => 'John Doe')

    assert_equal [leads(:john_doe).id], result['leads'].map { |row| row['id'] }
  end

  test 'rejects blank query with a corrective error' do
    result = call_tool('query' => '   ')

    assert_match(/Query is required/, result['error'])
  end

  test 'clamps limit regardless of what the model sends' do
    result = call_tool('query' => 'com', 'limit' => 50_000)

    assert_equal 3, result['returned_count']

    result = call_tool('query' => 'com', 'limit' => 0)
    assert_equal 1, result['returned_count']
  end

  test 'sanitizes sql wildcards in the query' do
    result = call_tool('query' => '%')

    assert_equal 0, result['total_count']
    assert_empty result['leads']
  end

  test 'reports the tool as temporarily unavailable when the database is down' do
    result = nil
    raise_db_down = ->(*) { raise ActiveRecord::ConnectionNotEstablished, 'server refused connection' }

    Pundit.stub(:policy_scope!, raise_db_down) do
      result = call_tool('query' => 'john')
    end

    assert_equal Assistant::BaseTool::UNAVAILABLE_MESSAGE, result['error']
    assert_no_match(/refused connection/, result.to_s, 'raw driver errors must not reach the model')
  end

  test 'rows expose no urls the model could turn into links' do
    row = call_tool('query' => 'jane')['leads'].sole

    assert_not row.key?('url')
    assert_not row.key?('linkedin_url')
    assert_not row.key?('company_website')
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
