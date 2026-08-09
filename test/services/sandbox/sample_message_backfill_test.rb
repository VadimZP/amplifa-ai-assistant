# frozen_string_literal: true

require 'test_helper'

module Sandbox
  # Repairs incoherent sandbox sample data: inbound replies/conversations that
  # exist with no preceding outbound GeneratedMessage. The backfill creates the
  # missing outbound message and links the reply to it so the thread is coherent
  # in both the Agents lead modal and the Inbox.
  class SampleMessageBackfillTest < ActiveSupport::TestCase
    setup do
      @organization = organizations(:acme)
      @agent = agents(:ready_agent)
      @mailbox = mailboxes(:acme_mailbox_two)
      # Fresh lead + agent_lead so the scenario has zero pre-existing generated_messages.
      @lead = Lead.create!(
        organization: @organization,
        email: 'backfill-lead@example.com',
        first_name: 'Backfill',
        last_name: 'Tester'
      )
      @agent_lead = AgentLead.create!(
        agent: @agent,
        lead: @lead,
        status: 'pending',
        delivery_status: 'in_sequence',
        sequence_position: 1
      )

      @conversation = Conversation.create!(
        organization: @organization,
        lead: @lead,
        mailbox: @mailbox,
        agent: @agent,
        status: 'open',
        replies_count: 1,
        unread_count: 1,
        last_reply_at: 2.hours.ago,
        last_reply_preview: 'Sounds interesting, tell me more.'
      )
      @reply = Reply.create!(
        lead: @lead,
        mailbox: @mailbox,
        conversation: @conversation,
        api_message_id: 'sandbox-msg-backfill-001',
        message_id: '<sandbox-backfill-001@example.com>',
        from_address: @lead.email,
        subject: 'Re: Quick question',
        body_plain: 'Sounds interesting, tell me more.',
        received_at: 2.hours.ago,
        is_out_of_office: false,
        is_bounce: false,
        is_warmup: false,
        requires_response: true
      )
    end

    test 'creates a linked outbound message for a reply that has none' do
      assert_nil @reply.generated_message_id, 'precondition: reply must start unlinked'
      assert_equal 0, @agent_lead.generated_messages.count, 'precondition: agent_lead has no messages'

      stats = Sandbox::SampleMessageBackfill.new(organization: @organization).call

      @reply.reload
      assert @reply.generated_message_id.present?, 'reply must be linked to a backfilled outbound message'

      message = @reply.generated_message
      assert_equal @agent_lead.id, message.agent_lead_id, 'message must belong to the reply lead agent_lead'
      assert_equal 'sent', message.status, 'backfilled message must be marked sent'
      assert message.sent_at.present?, 'backfilled message must have a sent_at'
      assert message.replied_at.present?, 'backfilled message must record the reply time'
      assert message.body.present?, 'backfilled message must have a body'
      assert_operator stats[:messages_created], :>=, 1
    end

    test 'is idempotent - a second run creates no additional messages' do
      Sandbox::SampleMessageBackfill.new(organization: @organization).call
      count_after_first = GeneratedMessage.for_lead(@lead).count

      stats = Sandbox::SampleMessageBackfill.new(organization: @organization).call
      count_after_second = GeneratedMessage.for_lead(@lead).count

      assert_equal count_after_first, count_after_second, 'rerun must not create duplicate messages'
      assert_equal 0, stats[:messages_created], 'rerun must report zero new messages'
    end

    test 'does not touch replies that already have a generated message' do
      linked_reply = replies(:john_doe_reply)
      original_message_id = linked_reply.generated_message_id
      assert original_message_id.present?, 'precondition: fixture reply is already linked'

      Sandbox::SampleMessageBackfill.new(organization: @organization).call

      assert_equal original_message_id, linked_reply.reload.generated_message_id,
                   'already-linked replies must be left untouched'
    end
  end
end
