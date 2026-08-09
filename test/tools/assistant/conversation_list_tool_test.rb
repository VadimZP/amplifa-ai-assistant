# frozen_string_literal: true

require 'test_helper'

class Assistant::ConversationListToolTest < ActiveSupport::TestCase
  def setup
    @account = accounts(:customer_admin)
    @organization = organizations(:acme)
    act_as_acme_admin
    @tool = Assistant::ConversationListTool.new(account: @account, organization: @organization)
  end

  def teardown
    Current.reset
  end

  test 'returns only conversations from the tool organization' do
    result = call_tool

    ids = result['conversations'].map { |row| row['id'] }
    assert_includes ids, conversations(:acme_john_conversation).id
    assert_not_includes ids, conversations(:growth_lab_conversation).id,
                        'a conversation from another organization must never be listed'
    assert_equal 3, result['total_count']
  end

  test 'returns nothing when the account has no active membership in the organization' do
    # WHY: This is the background-job failure mode — if Current is empty (or the membership was
    # revoked), the policy scope must fail closed rather than fall back to the whole table.
    Current.reset

    result = call_tool

    assert_equal 0, result['total_count']
    assert_empty result['conversations']
  end

  test 'searches by lead name, email and company' do
    result = call_tool('search' => 'jane')

    assert_equal [conversations(:acme_jane_conversation).id], result['conversations'].map { |row| row['id'] }

    result = call_tool('search' => 'example corp')
    assert_includes result['conversations'].map { |row| row['id'] }, conversations(:acme_john_conversation).id
  end

  test 'searches by full name with multiple words' do
    result = call_tool('search' => 'John Doe')

    assert_equal [conversations(:acme_john_conversation).id], result['conversations'].map { |row| row['id'] }
  end

  test 'filters by interest status within human conversations' do
    conversations(:acme_john_conversation).update!(interest_status: 'interested')

    result = call_tool('interest_status' => 'interested')

    assert_equal [conversations(:acme_john_conversation).id], result['conversations'].map { |row| row['id'] }
  end

  test 'filters unread and awaiting-reply conversations' do
    unread = call_tool('unread_only' => true)
    assert_equal [conversations(:acme_bounce_conversation).id, conversations(:acme_john_conversation).id].sort,
                 unread['conversations'].map { |row| row['id'] }.sort

    awaiting = call_tool('awaiting_reply_only' => true)
    ids = awaiting['conversations'].map { |row| row['id'] }
    assert_not_includes ids, conversations(:acme_john_conversation).id,
                        'a conversation already answered is not awaiting a reply'
    assert_includes ids, conversations(:acme_jane_conversation).id
  end

  test 'clamps limit and offset regardless of what the model sends' do
    result = call_tool('limit' => 50_000, 'offset' => -5)

    assert_equal 3, result['returned_count']

    result = call_tool('limit' => 0)
    assert_equal 1, result['returned_count']
  end

  test 'rejects unknown enum values with a corrective error' do
    result = call_tool('status' => 'DROP TABLE conversations')

    assert_match(/Unknown status/, result['error'])
    assert_match(/open, snoozed, closed/, result['error'])
  end

  test 'rejects unparseable dates with a corrective error' do
    result = call_tool('last_reply_after' => 'not-a-date')

    assert_match(/Could not parse last_reply_after/, result['error'])
  end

  test 'reports the tool as temporarily unavailable when the database is down' do
    result = nil
    raise_db_down = ->(*) { raise ActiveRecord::ConnectionNotEstablished, 'server refused connection' }

    Pundit.stub(:policy_scope!, raise_db_down) do
      result = call_tool
    end

    assert_equal Assistant::BaseTool::UNAVAILABLE_MESSAGE, result['error']
    assert_no_match(/refused connection/, result.to_s, 'raw driver errors must not reach the model')
  end

  test 'rows expose no urls the model could turn into links' do
    # WHY: assistant replies must never contain links, so tool payloads give the model no url
    # material to build them from.
    row = call_tool('search' => 'jane')['conversations'].sole

    assert_not row.key?('url')
  end

  private

  def act_as_acme_admin
    Current.account = @account
    Current.organization = @organization
    Current.organization_membership = organization_memberships(:customer_admin_acme)
  end

  # Goes through Tool#call (not #execute) so tests exercise the same JSON envelope and error
  # handling the LLM sees.
  def call_tool(args = {})
    JSON.parse(@tool.call(args))
  end
end
