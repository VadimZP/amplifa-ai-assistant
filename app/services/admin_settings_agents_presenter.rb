# frozen_string_literal: true

# Builds the props used by the global admin agents settings page.
class AdminSettingsAgentsPresenter
  def props
    {
      current_tab: 'agents',
      organization_agent_groups: serialize_organization_agent_groups,
      status_options: AdminSettingsAgentsUpdater::STATUSES,
      locale_options: Agent::LOCALES,
      global_sequences: global_sequence_options,
      llm_models: LlmModelService.grouped_by_provider,
      default_llm_model: Agent::DEFAULT_LLM_MODEL
    }
  end

  private

  def serialize_organization_agent_groups
    ordered_settings_agents.group_by(&:organization).map do |organization, agents|
      serialize_organization_agent_group(organization, agents)
    end
  end

  def ordered_settings_agents
    Agent.not_deleted.includes(:organization, :playbook, :sequence_steps)
         .joins(:organization)
         .order(
           Arel.sql('LOWER(organizations.name) ASC'),
           Arel.sql('LOWER(agents.name) ASC'),
           :id
         )
  end

  def serialize_organization_agent_group(organization, agents)
    {
      organization: { id: organization.id, name: organization.name },
      agents: agents.map { |agent| serialize_agent(agent) }
    }
  end

  def serialize_agent(agent)
    agent.slice(*agent_fields).merge(
      playbook_name: agent.playbook&.product_name,
      local_sequence_steps_count: agent.sequence_steps.not_archived.size
    )
  end

  def global_sequence_options
    GlobalSequence.left_joins(:sequence_steps)
                  .select(global_sequence_select_clause)
                  .group('global_sequences.id', 'global_sequences.name')
                  .order(:name)
                  .map { |sequence| serialize_global_sequence(sequence) }
  end

  def global_sequence_select_clause
    <<~SQL.squish
      global_sequences.id,
      global_sequences.name,
      COUNT(sequence_steps.id) FILTER (WHERE sequence_steps.archived = FALSE) AS sequence_steps_count
    SQL
  end

  def serialize_global_sequence(sequence)
    {
      id: sequence.id,
      name: sequence.name,
      sequence_steps_count: sequence.sequence_steps_count.to_i
    }
  end

  def agent_fields
    %i[
      id name status locale use_recipient_locale buying_signals_enabled send_sequence_messages_from_same_mailbox llm_model total_leads_count
      contacted_count replied_count meetings_booked_count global_sequence_id created_at
    ]
  end
end
