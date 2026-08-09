# frozen_string_literal: true

require "test_helper"

class SentReplyTest < ActiveSupport::TestCase
  # WHY: Validations ensure sent replies have required data for email sending
  test "requires conversation" do
    sent_reply = SentReply.new(
      mailbox: mailboxes(:acme_mailbox_one),
      sent_by: accounts(:amplifa_admin),
      subject: "Test",
      body_plain: "Test body"
    )
    assert_not sent_reply.valid?
    assert_includes sent_reply.errors[:conversation], "must exist"
  end

  test "requires mailbox" do
    sent_reply = SentReply.new(
      conversation: conversations(:acme_john_conversation),
      sent_by: accounts(:amplifa_admin),
      subject: "Test",
      body_plain: "Test body"
    )
    assert_not sent_reply.valid?
    assert_includes sent_reply.errors[:mailbox], "must exist"
  end

  test "requires sent_by" do
    sent_reply = SentReply.new(
      conversation: conversations(:acme_john_conversation),
      mailbox: mailboxes(:acme_mailbox_one),
      subject: "Test",
      body_plain: "Test body"
    )
    assert_not sent_reply.valid?
    assert_includes sent_reply.errors[:sent_by], "must exist"
  end

  test "requires subject" do
    sent_reply = SentReply.new(
      conversation: conversations(:acme_john_conversation),
      mailbox: mailboxes(:acme_mailbox_one),
      sent_by: accounts(:amplifa_admin),
      body_plain: "Test body"
    )
    assert_not sent_reply.valid?
    assert_includes sent_reply.errors[:subject], "can't be blank"
  end

  test "requires body_plain" do
    sent_reply = SentReply.new(
      conversation: conversations(:acme_john_conversation),
      mailbox: mailboxes(:acme_mailbox_one),
      sent_by: accounts(:amplifa_admin),
      subject: "Test"
    )
    assert_not sent_reply.valid?
    assert_includes sent_reply.errors[:body_plain], "can't be blank"
  end

  # WHY: Status validation ensures only valid statuses are used
  test "validates status inclusion" do
    sent_reply = sent_replies(:sent_to_john)
    sent_reply.status = "invalid"
    assert_not sent_reply.valid?
    assert_includes sent_reply.errors[:status], "is not included in the list"
  end

  test "allows valid statuses" do
    SentReply::STATUSES.each do |status|
      sent_reply = sent_replies(:sent_to_john)
      sent_reply.status = status
      assert sent_reply.valid?, "Status '#{status}' should be valid"
    end
  end

  test 'defaults to latest incoming sender as to address' do
    conversation = conversations(:acme_john_conversation)

    Reply.create!(
      mailbox: conversation.mailbox,
      lead: conversation.lead,
      conversation: conversation,
      api_message_id: "gmail-msg-#{SecureRandom.hex(4)}",
      message_id: '<latest-sender@example.com>',
      from_address: 'latest.sender@example.com',
      subject: 'Re: Partnership Opportunity',
      body_plain: 'I am the newest participant.',
      received_at: Time.current
    )

    sent_reply = SentReply.new(
      conversation: conversation,
      mailbox: conversation.mailbox,
      sent_by: accounts(:amplifa_admin),
      subject: 'Re: Partnership Opportunity',
      body_plain: 'Thanks.'
    )

    assert sent_reply.valid?
    assert_equal 'latest.sender@example.com', sent_reply.to_address
  end

  test 'cc recipients exclude mailbox and chosen to address' do
    sent_reply = SentReply.new(
      conversation: conversations(:acme_john_conversation),
      mailbox: mailboxes(:acme_mailbox_one),
      sent_by: accounts(:amplifa_admin),
      to_address: 'observer@example.com',
      subject: 'Re: Partnership Opportunity',
      body_plain: 'Thanks.',
      cc_addresses: ['sales@acme.com', 'observer@example.com', 'ally@example.com']
    )

    assert_equal ['ally@example.com'], sent_reply.additional_cc_addresses(excluding: sent_reply.mailbox.email)
  end

  # WHY: Status predicates provide clean API for checking send state
  test "draft? returns true for draft status" do
    assert sent_replies(:draft_reply).draft?
    assert_not sent_replies(:sent_to_john).draft?
  end

  test "sent? returns true for sent status" do
    assert sent_replies(:sent_to_john).sent?
    assert_not sent_replies(:draft_reply).sent?
  end

  test "failed? returns true for failed status" do
    assert sent_replies(:failed_reply).failed?
    assert_not sent_replies(:sent_to_john).failed?
  end

  # WHY: mark_sending! tracks when email is being processed
  test "mark_sending! changes status to sending" do
    sent_reply = sent_replies(:draft_reply)
    sent_reply.mark_sending!
    assert sent_reply.sending?
  end

  # WHY: mark_sent! records successful send with message IDs
  test "mark_sent! updates status and records message IDs" do
    sent_reply = sent_replies(:draft_reply)
    sent_reply.mark_sent!(api_message_id: "gmail-123", message_id: "<msg-id@example.com>")

    assert sent_reply.sent?
    assert_equal "gmail-123", sent_reply.api_message_id
    assert_equal "<msg-id@example.com>", sent_reply.message_id
    assert_not_nil sent_reply.sent_at
    assert_nil sent_reply.send_error
  end

  test 'mark_sent! refreshes conversation last sent reply timestamp' do
    sent_reply = sent_replies(:draft_reply)
    conversation = sent_reply.conversation

    assert_nil conversation.last_sent_reply_at

    sent_reply.mark_sent!(api_message_id: 'gmail-cache-123', message_id: '<cache-msg-id@example.com>')

    conversation.reload
    assert_in_delta sent_reply.reload.sent_at, conversation.last_sent_reply_at, 1.second
  end

  # WHY: mark_failed! preserves error for debugging
  test "mark_failed! updates status and records error" do
    sent_reply = sent_replies(:draft_reply)
    sent_reply.mark_failed!("API rate limit exceeded")

    assert sent_reply.failed?
    assert_equal "API rate limit exceeded", sent_reply.send_error
  end

  # WHY: Scopes enable efficient filtering by send state
  test "sent scope returns only sent replies" do
    results = SentReply.sent
    assert results.all?(&:sent?)
  end

  test "failed scope returns only failed replies" do
    results = SentReply.failed
    assert results.all?(&:failed?)
  end

  test "pending scope returns draft and sending replies" do
    results = SentReply.pending
    assert results.all? { |r| r.draft? || r.sending? }
  end

  # WHY: Associations ensure relationships are properly configured
  test "belongs to conversation" do
    sent_reply = sent_replies(:sent_to_john)
    assert_equal conversations(:acme_john_conversation), sent_reply.conversation
  end

  test "belongs to mailbox" do
    sent_reply = sent_replies(:sent_to_john)
    assert_equal mailboxes(:acme_mailbox_one), sent_reply.mailbox
  end

  test "belongs to sent_by account" do
    sent_reply = sent_replies(:sent_to_john)
    assert_equal accounts(:amplifa_admin), sent_reply.sent_by
  end

  test "optionally belongs to reply" do
    with_reply = sent_replies(:sent_to_john)
    assert with_reply.reply.present?

    without_reply = SentReply.new(
      conversation: conversations(:acme_john_conversation),
      mailbox: mailboxes(:acme_mailbox_one),
      sent_by: accounts(:amplifa_admin),
      subject: "Test",
      body_plain: "Test body"
    )
    assert_nil without_reply.reply
  end
end
