# frozen_string_literal: true

# Finds or creates Reply Center conversations for inbound replies and legacy lead-mailbox lookups.
class ConversationService
  def self.find_or_create_for_reply(reply)
    new(reply: reply).find_or_create
  end

  def self.find_or_create_for_lead_and_mailbox(lead:, mailbox:, agent: nil)
    new(lead: lead, mailbox: mailbox, agent: agent).find_or_create
  end

  def initialize(reply: nil, lead: nil, mailbox: nil, agent: nil)
    @reply = reply
    @lead = lead || reply&.lead
    @mailbox = mailbox || reply&.mailbox
    @agent = agent
    @agent_lead = reply&.generated_message&.agent_lead
  end

  def find_or_create
    conversation = find_or_initialize_conversation
    persist_new_conversation!(conversation) if conversation.new_record?

    attach_reply_and_refresh!(conversation)

    conversation
  end

  private

  def find_or_initialize_conversation
    return agent_lead_conversation if @agent_lead.present?

    Conversation.find_or_initialize_by(
      lead: @lead,
      mailbox: @mailbox
    )
  end

  def agent_lead_conversation
    Conversation.find_by(agent_lead: @agent_lead) || legacy_conversation_for_agent_lead
  end

  def legacy_conversation_for_agent_lead
    Conversation.find_or_initialize_by(lead: @lead, mailbox: @mailbox).tap do |conversation|
      conversation.agent_lead ||= @agent_lead
    end
  end

  def persist_new_conversation!(conversation)
    conversation.assign_attributes(new_conversation_attributes)
    conversation.save!
    log_created_conversation(conversation)
  end

  def new_conversation_attributes
    {
      organization: @mailbox.organization,
      lead: @lead,
      mailbox: @mailbox,
      agent: @agent || find_agent_for_lead,
      agent_lead: @agent_lead
    }
  end

  def log_created_conversation(conversation)
    Rails.logger.info(
      "[ConversationService] Created conversation #{conversation.id} " \
      "for lead #{@lead.id} via mailbox #{@mailbox.id}"
    )
  end

  def attach_reply_and_refresh!(conversation)
    conversation.save! if conversation.changed?
    @reply&.update!(conversation: conversation)
    conversation.refresh_counters!
    reopen_closed_conversation!(conversation) if @reply.present? && conversation.closed?
  end

  def reopen_closed_conversation!(conversation)
    conversation.reopen!
    Rails.logger.info(
      "[ConversationService] Reopened conversation #{conversation.id} due to new reply"
    )
  end

  def find_agent_for_lead
    return @agent_lead.agent if @agent_lead.present?

    agent_lead = AgentLead
                 .joins(:generated_messages)
                 .where(lead: @lead)
                 .where(generated_messages: { mailbox_id: @mailbox.id, status: 'sent' })
                 .first

    agent_lead&.agent
  end
end
