# frozen_string_literal: true

module Sandbox
  # Repairs incoherent sample/sandbox data where inbound replies and conversations
  # exist with no preceding outbound GeneratedMessage (so a lead's thread shows an
  # incoming reply out of nowhere, and the Agents-page thread and Inbox disagree).
  #
  # For every reply in the organization that is a real inbound message (not a bounce
  # or warmup) and is not yet linked to an outbound message, this creates the missing
  # outbound GeneratedMessage on the lead's AgentLead and links the reply to it. The
  # message is marked sent (with a sent_at before the reply and a replied_at matching
  # the reply) so it surfaces consistently in both the lead modal and the Inbox thread.
  #
  # Idempotent: replies that are already linked, and steps that already have a message
  # for the current run, are skipped, so re-running the backfill never duplicates data.
  class SampleMessageBackfill
    OUTBOUND_SUBJECT = 'Quick question'
    OUTBOUND_BODY = <<~BODY.strip
      Hi %<name>s,

      I came across your work and thought there might be a fit with what we're building. Would you be open to a short chat this week?

      Best
    BODY

    def initialize(organization:)
      @organization = organization
    end

    def call
      stats = { messages_created: 0, replies_linked: 0, skipped: 0 }

      Conversation.for_organization(@organization)
                  .includes(:lead, :mailbox, :agent, :replies)
                  .find_each do |conversation|
        conversation.replies.each { |reply| process_reply(conversation, reply, stats) }
      end

      stats
    end

    private

    def process_reply(conversation, reply, stats)
      if reply.generated_message_id.present? || reply.is_warmup? || reply.is_bounce?
        stats[:skipped] += 1
        return
      end

      agent_lead = resolve_agent_lead(conversation, reply.lead)
      step = agent_lead && first_email_step(agent_lead.agent)
      if agent_lead.nil? || step.nil?
        stats[:skipped] += 1
        return
      end

      message = existing_message(agent_lead, step)
      if message.nil?
        message = build_message(agent_lead, step, conversation, reply)
        message.save!
        stats[:messages_created] += 1
      end

      reply.update!(generated_message_id: message.id)
      stats[:replies_linked] += 1
    end

    def resolve_agent_lead(conversation, lead)
      return nil if lead.nil?

      scope = AgentLead.where(lead_id: lead.id)
                       .joins(:agent)
                       .where(agents: { organization_id: @organization.id })
      (conversation.agent_id && scope.find_by(agent_id: conversation.agent_id)) || scope.first
    end

    def first_email_step(agent)
      steps = agent.effective_sequence_steps.active
      steps.email_steps.order(:position).first || steps.order(:position).first
    end

    def existing_message(agent_lead, step)
      run_id = agent_lead.current_agent_lead_run_id
      if run_id
        agent_lead.generated_messages.find_by(sequence_step_id: step.id, agent_lead_run_id: run_id)
      else
        agent_lead.generated_messages.find_by(sequence_step_id: step.id)
      end
    end

    def build_message(agent_lead, step, conversation, reply)
      reply_time = reply.received_at || conversation.last_reply_at || Time.current
      first_name = reply.lead&.first_name.presence || 'there'

      agent_lead.generated_messages.build(
        sequence_step: step,
        mailbox: conversation.mailbox || agent_lead.assigned_mailbox,
        status: 'sent',
        sample: false,
        subject: OUTBOUND_SUBJECT,
        body: format(OUTBOUND_BODY, name: first_name),
        sent_at: reply_time - 1.day,
        replied_at: reply.received_at
      )
    end
  end
end
