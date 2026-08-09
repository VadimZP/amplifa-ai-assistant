# frozen_string_literal: true

require 'test_helper'

class ConversationReadTest < ActiveSupport::TestCase
  test 'requires conversation' do
    cr = ConversationRead.new(account: accounts(:amplifa_admin), last_read_at: Time.current)
    assert_not cr.valid?
    assert_includes cr.errors[:conversation], 'must exist'
  end

  test 'requires account' do
    cr = ConversationRead.new(conversation: conversations(:acme_john_conversation), last_read_at: Time.current)
    assert_not cr.valid?
    assert_includes cr.errors[:account], 'must exist'
  end

  test 'requires last_read_at' do
    cr = ConversationRead.new(
      conversation: conversations(:acme_john_conversation),
      account: accounts(:customer_user)
    )
    assert_not cr.valid?
    assert_includes cr.errors[:last_read_at], "can't be blank"
  end

  test 'prevents duplicate conversation-account pairs' do
    existing = conversation_reads(:admin_read_john_conversation)
    duplicate = ConversationRead.new(
      conversation: existing.conversation,
      account: existing.account,
      last_read_at: Time.current
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:conversation_id], 'has already been taken'
  end

  test 'allows same conversation for different accounts' do
    cr = ConversationRead.new(
      conversation: conversations(:acme_john_conversation),
      account: accounts(:customer_admin),
      last_read_at: Time.current
    )
    assert cr.valid?
  end

  # Tests for Conversation#unread_for?

  test 'unread_for? returns true when no read record exists' do
    conversation = conversations(:acme_john_conversation)
    # customer_user has no ConversationRead for this conversation
    assert conversation.unread_for?(accounts(:customer_user))
  end

  test 'unread_for? returns true when last_reply_at is after last_read_at' do
    conversation = conversations(:acme_john_conversation)
    # admin_read_john_conversation has last_read_at = 3.hours.ago
    # acme_john_conversation has last_reply_at = 2.hours.ago
    # So the conversation should be unread for this admin
    assert conversation.unread_for?(accounts(:amplifa_admin))
  end

  test 'unread_for? returns false when last_read_at is after last_reply_at' do
    conversation = conversations(:acme_jane_conversation)
    # customer_admin_read_jane_conversation has last_read_at = 1.hour.ago
    # acme_jane_conversation has last_reply_at = 1.day.ago
    assert_not conversation.unread_for?(accounts(:customer_admin))
  end

  test 'unread_for? returns false when last_reply_at is nil' do
    conversation = conversations(:snoozed_conversation)
    assert_not conversation.unread_for?(accounts(:amplifa_admin))
  end

  # Tests for Conversation#mark_read_for!

  test 'mark_read_for! creates a new read record' do
    conversation = conversations(:acme_bounce_conversation)
    account = accounts(:customer_admin)

    assert_nil ConversationRead.find_by(conversation: conversation, account: account)

    conversation.mark_read_for!(account)

    cr = ConversationRead.find_by(conversation: conversation, account: account)
    assert_not_nil cr
    assert_in_delta Time.current, cr.last_read_at, 2.seconds
  end

  test 'mark_read_for! updates existing read record' do
    conversation = conversations(:acme_john_conversation)
    account = accounts(:amplifa_admin)

    old_read = conversation_reads(:admin_read_john_conversation)
    old_time = old_read.last_read_at

    conversation.mark_read_for!(account)

    old_read.reload
    assert old_read.last_read_at > old_time
  end

  # Tests for Conversation.unread_for scope

  test 'unread_for scope returns conversations unread by account' do
    account = accounts(:customer_user)
    # customer_user has no ConversationRead records, so all conversations with
    # last_reply_at should be unread
    unread = Conversation.unread_for(account)
    assert unread.any?
    assert(unread.all? { |c| c.last_reply_at.present? })
  end

  test 'unread_for scope excludes conversations already read' do
    account = accounts(:customer_admin)
    # customer_admin has read acme_jane_conversation (last_read_at > last_reply_at)
    unread = Conversation.unread_for(account)
    assert_not unread.include?(conversations(:acme_jane_conversation))
  end
end
