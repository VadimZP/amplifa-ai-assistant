# frozen_string_literal: true

require 'test_helper'

class ConversationTest < ActiveSupport::TestCase
  # WHY: Validations ensure data integrity for conversations
  test 'requires organization' do
    conversation = Conversation.new(
      lead: leads(:john_doe),
      mailbox: mailboxes(:acme_mailbox_one)
    )
    assert_not conversation.valid?
    assert_includes conversation.errors[:organization], 'must exist'
  end

  test 'requires lead' do
    conversation = Conversation.new(
      organization: organizations(:acme),
      mailbox: mailboxes(:acme_mailbox_one)
    )
    assert_not conversation.valid?
    assert_includes conversation.errors[:lead], 'must exist'
  end

  test 'requires mailbox' do
    conversation = Conversation.new(
      organization: organizations(:acme),
      lead: leads(:john_doe)
    )
    assert_not conversation.valid?
    assert_includes conversation.errors[:mailbox], 'must exist'
  end

  # WHY: Uniqueness constraint ensures one conversation per lead-mailbox pair
  test 'prevents duplicate lead-mailbox combinations' do
    existing = conversations(:acme_john_conversation)
    duplicate = Conversation.new(
      organization: existing.organization,
      lead: existing.lead,
      mailbox: existing.mailbox
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:lead_id], 'has already been taken'
  end

  # WHY: Status validation ensures only valid statuses are used
  test 'validates status inclusion' do
    conversation = conversations(:acme_john_conversation)
    conversation.status = 'invalid_status'
    assert_not conversation.valid?
    assert_includes conversation.errors[:status], 'is not included in the list'
  end

  test 'allows valid statuses' do
    Conversation::STATUSES.each do |status|
      conversation = conversations(:acme_john_conversation)
      conversation.status = status
      assert conversation.valid?, "Status '#{status}' should be valid"
    end
  end

  # WHY: Status predicates provide clean API for status checking
  test 'open? returns true when status is open' do
    conversation = conversations(:acme_john_conversation)
    assert conversation.open?
    assert_not conversation.closed?
    assert_not conversation.snoozed?
  end

  test 'closed? returns true when status is closed' do
    conversation = conversations(:acme_jane_conversation)
    assert conversation.closed?
    assert_not conversation.open?
  end

  test 'snoozed? returns true when status is snoozed and snoozed_until is future' do
    conversation = conversations(:snoozed_conversation)
    assert conversation.snoozed?
    assert_not conversation.open?
  end

  test 'snoozed? returns false when snoozed_until is past' do
    conversation = conversations(:snoozed_conversation)
    conversation.snoozed_until = 1.day.ago
    assert_not conversation.snoozed?
  end

  # WHY: Status transitions provide atomic state changes
  test 'reopen! changes status to open and clears snoozed_until' do
    conversation = conversations(:acme_jane_conversation)
    conversation.reopen!
    assert conversation.open?
    assert_nil conversation.snoozed_until
  end

  test 'snooze! sets status to snoozed with until_time' do
    conversation = conversations(:acme_john_conversation)
    snooze_time = 1.week.from_now
    conversation.snooze!(snooze_time)
    assert_equal 'snoozed', conversation.status
    assert_in_delta snooze_time, conversation.snoozed_until, 1.second
  end

  test 'close! changes status to closed' do
    conversation = conversations(:acme_john_conversation)
    conversation.close!
    assert conversation.closed?
  end

  # WHY: Scopes enable efficient filtering of conversations
  test 'open scope returns only open conversations' do
    results = Conversation.open
    assert results.all?(&:open?)
  end

  test 'closed scope returns only closed conversations' do
    results = Conversation.closed
    assert results.all?(&:closed?)
  end

  test 'with_unread scope returns conversations with unread_count > 0' do
    results = Conversation.with_unread
    assert(results.all? { |c| c.unread_count > 0 })
  end

  test 'for_organization scope filters by organization' do
    org = organizations(:acme)
    results = Conversation.for_organization(org)
    assert(results.all? { |c| c.organization_id == org.id })
  end

  # WHY: Associations ensure relationships are properly configured
  test 'belongs to organization' do
    conversation = conversations(:acme_john_conversation)
    assert_equal organizations(:acme), conversation.organization
  end

  test 'belongs to lead' do
    conversation = conversations(:acme_john_conversation)
    assert_equal leads(:john_doe), conversation.lead
  end

  test 'belongs to mailbox' do
    conversation = conversations(:acme_john_conversation)
    assert_equal mailboxes(:acme_mailbox_one), conversation.mailbox
  end

  test 'optionally belongs to agent' do
    conv_with_agent = conversations(:acme_john_conversation)
    assert conv_with_agent.agent.present?

    conv_without_agent = conversations(:snoozed_conversation)
    assert_nil conv_without_agent.agent
  end

  test 'has many replies' do
    conversation = conversations(:acme_john_conversation)
    assert_respond_to conversation, :replies
    assert conversation.replies.include?(replies(:john_doe_reply))
  end

  test 'has many sent_replies' do
    conversation = conversations(:acme_john_conversation)
    assert_respond_to conversation, :sent_replies
    assert conversation.sent_replies.include?(sent_replies(:sent_to_john))
  end

  # WHY: mark_all_read! provides bulk update for read status
  test 'mark_all_read! marks all replies as read and updates counter' do
    conversation = conversations(:acme_john_conversation)
    assert conversation.unread_count > 0

    conversation.mark_all_read!

    assert_equal 0, conversation.unread_count
    assert conversation.replies.all?(&:read?)
  end

  # WHY: refresh_counters! should only count human replies as unread
  test 'refresh_counters! excludes bounces from unread_count' do
    conversation = conversations(:acme_bounce_conversation)
    conversation.refresh_counters!
    assert_equal 0, conversation.unread_count
  end

  test 'refresh_counters! excludes out of office from unread_count' do
    conversation = conversations(:acme_jane_conversation)
    # Mark the OOO reply as unread to test the filter
    replies(:jane_ooo_reply).update_columns(read_at: nil)
    conversation.refresh_counters!
    assert_equal 0, conversation.unread_count
  end

  test 'refresh_counters! counts human unread replies' do
    conversation = conversations(:acme_john_conversation)
    conversation.refresh_counters!
    assert_equal 1, conversation.unread_count
  end

  test 'refresh_counters! caches bounce status' do
    conversation = conversations(:acme_bounce_conversation)

    conversation.update!(has_bounce: false)
    conversation.refresh_counters!

    assert conversation.has_bounce
    assert_not conversation.latest_relevant_reply_is_out_of_office
    assert_nil conversation.ooo_return_date
  end

  test 'refresh_counters! caches latest relevant out of office status and return date' do
    conversation = conversations(:acme_jane_conversation)
    return_date = Date.current + 3.days
    replies(:jane_ooo_reply).update!(out_of_office_return_date: return_date)

    conversation.update!(latest_relevant_reply_is_out_of_office: false, ooo_return_date: nil)
    conversation.refresh_counters!

    assert conversation.latest_relevant_reply_is_out_of_office
    assert_equal return_date, conversation.ooo_return_date
  end

  test 'reply status changes refresh cached conversation status' do
    conversation = conversations(:acme_john_conversation)
    reply = replies(:john_doe_reply)
    return_date = Date.current + 5.days

    assert_not conversation.latest_relevant_reply_is_out_of_office

    reply.update!(is_out_of_office: true, out_of_office_return_date: return_date)

    conversation.reload
    assert conversation.latest_relevant_reply_is_out_of_office
    assert_equal return_date, conversation.ooo_return_date
  end

  test 'refresh_counters! caches latest sent reply timestamp' do
    conversation = conversations(:acme_john_conversation)
    sent_reply = sent_replies(:sent_to_john)

    conversation.update!(last_sent_reply_at: nil)
    conversation.refresh_counters!

    assert_in_delta sent_reply.sent_at, conversation.last_sent_reply_at, 1.second
  end

  # WHY: thread_messages combines incoming/outgoing for chronological view
  test 'thread_messages returns combined replies and sent_replies sorted by timestamp' do
    conversation = conversations(:acme_john_conversation)
    thread = conversation.thread_messages

    assert thread.is_a?(Array)
    assert(thread.any? { |m| m[:type] == :incoming })
    assert(thread.any? { |m| m[:type] == :outgoing })

    timestamps = thread.map { |m| m[:message_at] }
    assert_equal timestamps, timestamps.sort
  end

  test 'thread_messages includes rendered signature for sent replies when requested' do
    conversation = conversations(:acme_john_conversation)
    sent_reply = sent_replies(:sent_to_john)

    thread = conversation.thread_messages
    message = thread.find { |entry| entry[:source] == :sent_reply && entry[:id] == sent_reply.id }

    assert_not_nil message

    expected_signature = conversation.mailbox.sender.rendered_signature_for(lead: conversation.lead)

    assert_includes message[:body_html], expected_signature
    assert_includes message[:body_plain], 'Best regards,'
  end

  test 'thread_messages includes rendered signature for generated messages' do
    conversation = conversations(:acme_john_conversation)
    generated_message = generated_messages(:john_step_one_draft)

    generated_message.update!(
      mailbox: conversation.mailbox,
      status: 'sent',
      sent_at: 2.hours.ago
    )

    thread = conversation.thread_messages
    message = thread.find { |entry| entry[:source] == :generated_message && entry[:id] == generated_message.id }

    assert_not_nil message

    expected_signature = conversation.mailbox.sender.rendered_signature_for(
      lead: conversation.lead,
      agent: generated_message.agent,
      agent_lead: generated_message.agent_lead
    )

    assert_includes message[:body_html], expected_signature
    assert_includes message[:body_plain], 'Best regards,'
  end

  test 'thread_messages keeps generated messages after agent soft delete' do
    conversation = conversations(:acme_john_conversation)
    generated_message = generated_messages(:john_step_one_draft)

    generated_message.update!(
      mailbox: conversation.mailbox,
      status: 'sent',
      sent_at: 2.hours.ago
    )
    conversation.agent.mark_deleted!

    thread = conversation.thread_messages
    message = thread.find { |entry| entry[:source] == :generated_message && entry[:id] == generated_message.id }

    assert_not_nil message
    assert_equal generated_message.subject, message[:subject]
    assert_equal conversation.lead.email, conversation.lead.reload.email
  end

  test 'thread_messages includes generated messages across mailboxes for the same agent lead' do
    conversation = conversations(:acme_john_conversation)
    agent_lead = agent_leads(:john_in_draft)
    mailbox_one = mailboxes(:acme_mailbox_one)
    mailbox_two = mailboxes(:acme_mailbox_two)
    first_message = generated_messages(:john_step_one_draft)
    first_message.update!(mailbox: mailbox_one, status: 'sent', sent_at: 2.hours.ago)
    second_message = GeneratedMessage.create!(
      agent_lead: agent_lead,
      sequence_step: sequence_steps(:step_four_email),
      subject: 'Cross mailbox generated message',
      body: 'Sent from mailbox two',
      status: 'sent',
      ai_model: 'gpt-5-mini',
      mailbox: mailbox_two,
      sent_at: 1.hour.ago,
      message_id: "<conversation-thread-#{SecureRandom.hex(6)}@example.com>"
    )
    conversation.update!(agent_lead: agent_lead)

    thread = conversation.thread_messages
    generated_ids = thread.select { |entry| entry[:source] == :generated_message }.map { |entry| entry[:id] }

    assert_includes generated_ids, first_message.id
    assert_includes generated_ids, second_message.id
  end

  test 'thread_messages uses each generated message mailbox as from address' do
    conversation = conversations(:acme_john_conversation)
    agent_lead = agent_leads(:john_in_draft)
    generated_message = generated_messages(:john_step_one_draft)
    mailbox = mailboxes(:acme_mailbox_two)
    generated_message.update!(mailbox: mailbox, status: 'sent', sent_at: 1.hour.ago)
    conversation.update!(agent_lead: agent_lead)

    message = conversation.thread_messages.find do |entry|
      entry[:source] == :generated_message && entry[:id] == generated_message.id
    end

    assert_equal mailbox.email, message[:from_address]
  end

  test 'thread_messages uses each sent reply mailbox as from address' do
    conversation = conversations(:acme_john_conversation)
    mailbox = mailboxes(:acme_mailbox_two)
    sent_reply = SentReply.create!(
      conversation: conversation,
      mailbox: mailbox,
      sent_by: accounts(:amplifa_admin),
      to_address: conversation.lead.email,
      subject: 'Re: Cross mailbox reply',
      body_plain: 'Reply from mailbox two',
      include_signature: false,
      status: 'sent',
      sent_at: 10.minutes.ago,
      api_message_id: 'cross-mailbox-sent-reply',
      message_id: '<cross-mailbox-sent-reply@example.com>'
    )

    message = conversation.thread_messages.find do |entry|
      entry[:source] == :sent_reply && entry[:id] == sent_reply.id
    end

    assert_equal mailbox.email, message[:from_address]
  end

  test 'reply_mailbox returns mailbox from most recent incoming message' do
    conversation = conversations(:acme_john_conversation)
    agent_lead = agent_leads(:john_in_draft)
    older_mailbox = mailboxes(:acme_mailbox_one)
    outgoing_mailbox = mailboxes(:acme_mailbox_two)
    generated_messages(:john_step_one_draft).update!(
      mailbox: outgoing_mailbox,
      status: 'sent',
      sent_at: 30.minutes.ago
    )
    conversation.update!(agent_lead: agent_lead)
    SentReply.create!(
      conversation: conversation,
      mailbox: older_mailbox,
      sent_by: accounts(:amplifa_admin),
      to_address: conversation.lead.email,
      subject: 'Older manual reply',
      body_plain: 'Older reply',
      include_signature: false,
      status: 'sent',
      sent_at: 2.hours.ago,
      api_message_id: 'older-manual-reply',
      message_id: '<older-manual-reply@example.com>'
    )
    incoming_reply = Reply.create!(
      conversation: conversation,
      mailbox: older_mailbox,
      lead: conversation.lead,
      api_message_id: "incoming-mailbox-choice-#{SecureRandom.hex(6)}",
      from_address: conversation.lead.email,
      subject: 'Re: Latest incoming reply',
      body_plain: 'Reply received by mailbox one',
      received_at: 10.minutes.ago,
      requires_response: true
    )

    assert_equal incoming_reply.mailbox, conversation.reply_mailbox
  end
end
