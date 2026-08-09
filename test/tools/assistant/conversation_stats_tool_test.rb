# frozen_string_literal: true

require 'test_helper'

class Assistant::ConversationStatsToolTest < ActiveSupport::TestCase
  def setup
    @account = accounts(:customer_admin)
    @organization = organizations(:acme)
    Current.account = @account
    Current.organization = @organization
    Current.organization_membership = organization_memberships(:customer_admin_acme)
    @tool = Assistant::ConversationStatsTool.new(account: @account, organization: @organization)
  end

  def teardown
    Current.reset
  end

  test 'counts only the tool organization conversations' do
    stats = JSON.parse(@tool.call({}))

    # Acme has 3 inbox conversations (john, jane, bounce); growth_lab's must not be counted.
    assert_equal 3, stats['total']
    assert_equal 2, stats['open']
    assert_equal 1, stats['closed']
    assert_equal 1, stats['bounced']
    assert_equal 1, stats['out_of_office']
    # John's conversation is the only human one and it is unread for this account.
    assert_equal 1, stats['unread']
    assert_equal 1, stats['by_interest_status']['unclassified']
  end

  test 'reflects interest status updates' do
    conversations(:acme_john_conversation).update!(interest_status: 'meeting_request')

    stats = JSON.parse(@tool.call({}))

    assert_equal 1, stats['by_interest_status']['meeting_request']
    assert_equal 0, stats['by_interest_status']['unclassified']
  end

  test 'reports the tool as temporarily unavailable when the database is down' do
    raise_db_down = ->(*) { raise ActiveRecord::ConnectionNotEstablished, 'server refused connection' }

    Pundit.stub(:policy_scope!, raise_db_down) do
      stats = JSON.parse(@tool.call({}))

      assert_equal Assistant::BaseTool::UNAVAILABLE_MESSAGE, stats['error']
    end
  end
end
