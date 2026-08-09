# frozen_string_literal: true

require 'test_helper'

class ConversationServiceTest < ActiveSupport::TestCase
  setup do
    @mailbox = mailboxes(:acme_mailbox_one)
    @lead = leads(:john_doe)
    @organization = organizations(:acme)
  end

  test 'creates new conversation for reply without existing conversation' do
    new_lead = Lead.create!(
      organization: @organization,
      email: 'newlead@example.com',
      first_name: 'New',
      last_name: 'Lead'
    )

    reply = Reply.create!(
      mailbox: @mailbox,
      lead: new_lead,
      api_message_id: "test-msg-#{SecureRandom.hex(8)}",
      from_address: 'newlead@example.com',
      subject: 'Test',
      body_plain: 'Test body',
      received_at: Time.current
    )

    assert_difference -> { Conversation.count }, 1 do
      conversation = ConversationService.find_or_create_for_reply(reply)

      assert conversation.persisted?
      assert_equal @organization, conversation.organization
      assert_equal new_lead, conversation.lead
      assert_equal @mailbox, conversation.mailbox
    end
  end

  test 'finds existing conversation for reply' do
    existing_conversation = conversations(:acme_john_conversation)

    reply = Reply.create!(
      mailbox: @mailbox,
      lead: @lead,
      api_message_id: "test-msg-#{SecureRandom.hex(8)}",
      from_address: @lead.email,
      subject: 'Another reply',
      body_plain: 'More content',
      received_at: Time.current
    )

    assert_no_difference -> { Conversation.count } do
      conversation = ConversationService.find_or_create_for_reply(reply)

      assert_equal existing_conversation.id, conversation.id
    end
  end

  test 'reply to generated message attaches to existing conversation for same agent lead across mailboxes' do
    existing_conversation = conversations(:acme_john_conversation)
    agent_lead = agent_leads(:john_in_draft)
    other_mailbox = mailboxes(:acme_mailbox_two)
    generated_message = GeneratedMessage.create!(
      agent_lead: agent_lead,
      sequence_step: sequence_steps(:step_four_email),
      subject: 'Cross mailbox follow up',
      body: 'Following up from another mailbox',
      status: 'sent',
      ai_model: 'gpt-5-mini',
      mailbox: other_mailbox,
      sent_at: 30.minutes.ago,
      message_id: "<conversation-service-cross-#{SecureRandom.hex(6)}@example.com>"
    )
    existing_conversation.update!(agent_lead: agent_lead)
    reply = Reply.create!(
      generated_message: generated_message,
      mailbox: other_mailbox,
      lead: existing_conversation.lead,
      api_message_id: "test-msg-#{SecureRandom.hex(8)}",
      from_address: existing_conversation.lead.email,
      subject: 'Re: Cross mailbox follow up',
      body_plain: 'Replying to mailbox two',
      received_at: Time.current
    )

    assert_no_difference -> { Conversation.count } do
      conversation = ConversationService.find_or_create_for_reply(reply)

      assert_equal existing_conversation.id, conversation.id
      assert_equal existing_conversation.mailbox, conversation.mailbox
    end

    assert_equal existing_conversation, reply.reload.conversation
  end

  test 'reply without generated message preserves legacy lead mailbox fallback' do
    existing_conversation = conversations(:acme_john_conversation)
    reply = Reply.create!(
      mailbox: existing_conversation.mailbox,
      lead: existing_conversation.lead,
      api_message_id: "test-msg-#{SecureRandom.hex(8)}",
      from_address: existing_conversation.lead.email,
      subject: 'Legacy fallback reply',
      body_plain: 'No generated message reference',
      received_at: Time.current
    )

    assert_no_difference -> { Conversation.count } do
      conversation = ConversationService.find_or_create_for_reply(reply)

      assert_equal existing_conversation.id, conversation.id
    end
  end

  test 'associates reply with conversation' do
    reply = Reply.create!(
      mailbox: @mailbox,
      lead: @lead,
      api_message_id: "test-msg-#{SecureRandom.hex(8)}",
      from_address: @lead.email,
      subject: 'Test',
      body_plain: 'Test body',
      received_at: Time.current
    )

    assert_nil reply.conversation

    conversation = ConversationService.find_or_create_for_reply(reply)

    reply.reload
    assert_equal conversation, reply.conversation
  end

  test 'refreshes conversation counters after adding reply' do
    existing_conversation = conversations(:acme_john_conversation)
    original_count = existing_conversation.replies_count

    reply = Reply.create!(
      mailbox: @mailbox,
      lead: @lead,
      api_message_id: "test-msg-#{SecureRandom.hex(8)}",
      from_address: @lead.email,
      subject: 'Test',
      body_plain: 'New reply body',
      received_at: Time.current
    )

    ConversationService.find_or_create_for_reply(reply)

    existing_conversation.reload
    assert existing_conversation.replies_count > original_count
  end

  test 'reopens closed conversation when new reply arrives' do
    closed_conversation = conversations(:acme_jane_conversation)
    assert closed_conversation.closed?

    reply = Reply.create!(
      mailbox: closed_conversation.mailbox,
      lead: closed_conversation.lead,
      api_message_id: "test-msg-#{SecureRandom.hex(8)}",
      from_address: closed_conversation.lead.email,
      subject: 'New reply',
      body_plain: "I'm back!",
      received_at: Time.current
    )

    ConversationService.find_or_create_for_reply(reply)

    closed_conversation.reload
    assert closed_conversation.open?
  end

  test 'sets agent to nil when no matching agent found' do
    new_lead = Lead.create!(
      organization: @organization,
      email: 'orphan@example.com',
      first_name: 'Orphan',
      last_name: 'Lead'
    )

    reply = Reply.create!(
      mailbox: @mailbox,
      lead: new_lead,
      api_message_id: "test-msg-#{SecureRandom.hex(8)}",
      from_address: 'orphan@example.com',
      subject: 'Test',
      body_plain: 'Test body',
      received_at: Time.current
    )

    conversation = ConversationService.find_or_create_for_reply(reply)

    assert_nil conversation.agent
  end

  test 'finds agent based on sent messages via mailbox' do
    agent = agents(:draft_agent)
    lead = Lead.create!(
      organization: agent.organization,
      email: "agent-find-#{SecureRandom.hex(4)}@example.com",
      first_name: 'Test',
      last_name: 'Lead',
      full_name: 'Test Lead',
      company: 'Example Co'
    )
    agent_lead = AgentLead.create!(agent: agent, lead: lead)
    mailbox = mailboxes(:acme_mailbox_two)

    GeneratedMessage.create!(
      agent_lead: agent_lead,
      sequence_step: sequence_steps(:step_one_email),
      subject: 'Test Subject',
      body: 'Test body',
      status: 'sent',
      ai_model: 'gpt-5-mini',
      mailbox: mailbox,
      sent_at: 1.hour.ago,
      message_id: "<conversation-service-#{SecureRandom.hex(6)}@example.com>"
    )

    reply = Reply.create!(
      mailbox: mailbox,
      lead: lead,
      api_message_id: "test-msg-#{SecureRandom.hex(8)}",
      from_address: lead.email,
      subject: 'Reply',
      body_plain: 'Test',
      received_at: Time.current
    )

    conversation = ConversationService.find_or_create_for_reply(reply)

    assert_equal agent, conversation.agent
  end
end
