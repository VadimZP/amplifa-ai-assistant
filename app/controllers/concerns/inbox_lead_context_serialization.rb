# frozen_string_literal: true

# Serializes read-only campaign history for inbox lead sidebars.
module InboxLeadContextSerialization
  private

  def serialize_inbox_agent_leads_for(lead)
    lead.agent_leads
        .includes(:assigned_mailbox, :current_agent_lead_run, agent: :sequence_steps)
        .map { |agent_lead| serialize_inbox_agent_lead(agent_lead) }
  end

  def serialize_inbox_agent_lead(agent_lead)
    agent_lead.as_json(only: %i[id status delivery_status sequence_position]).symbolize_keys.merge(
      agent: serialize_inbox_agent_for(agent_lead.agent),
      assigned_mailbox: serialize_inbox_assigned_mailbox(agent_lead.assigned_mailbox),
      generated_messages: serialize_inbox_generated_messages(
        agent_lead.current_run_generated_messages.includes(:sequence_step)
      )
    )
  end

  def serialize_inbox_agent_for(agent)
    {
      id: agent.id,
      name: agent.name,
      status: agent.status,
      sequence_steps: serialize_inbox_sequence_steps(agent)
    }
  end

  def serialize_inbox_sequence_steps(agent)
    agent.active_email_sequence_steps.ordered.map do |step|
      step.as_json(only: %i[id position name display_name event_type delay_days]).symbolize_keys
    end
  end

  def serialize_inbox_assigned_mailbox(mailbox)
    return nil unless mailbox

    {
      id: mailbox.id,
      email: mailbox.email
    }
  end

  def serialize_inbox_generated_messages(messages)
    messages.map do |message|
      serialize_inbox_generated_message(message)
    end
  end

  def serialize_inbox_generated_message(message)
    message.as_json(
      only: %i[id sequence_step_id subject body status manually_edited sent_at ai_model generation_time_ms created_at]
    ).symbolize_keys.merge(
      sequence_step: serialize_inbox_message_sequence_step(message.sequence_step)
    )
  end

  def serialize_inbox_message_sequence_step(sequence_step)
    return nil unless sequence_step

    {
      id: sequence_step.id,
      position: sequence_step.position,
      display_name: sequence_step.display_name
    }
  end
end
