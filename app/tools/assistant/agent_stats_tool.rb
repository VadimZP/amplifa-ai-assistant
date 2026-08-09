# frozen_string_literal: true

# Aggregate campaign statistics for the assistant. One query answers "how many leads are in
# sequence" without paging through individual rows. Mirrors Customer::AgentsController#index
# status_counts.
module Assistant
  class AgentStatsTool < BaseTool
    description 'Returns aggregate statistics for agent campaigns: total leads and a breakdown by ' \
                'delivery status (not_contacted, in_sequence, paused, replied, bounced, completed). ' \
                'Optionally filter to one agent. Use this for "how many" questions; use ' \
                'agent_lead_list for "which leads" questions.'

    param :agent_id, type: :integer,
          desc: 'Limit stats to one agent. Find ids with agent_list first — never guess an id.',
          required: false

    def execute(agent_id: nil)
      agent = nil
      if agent_id.present?
        agent = scoped(Agent).find_by(id: agent_id)
        return { error: 'Agent not found.' } unless agent
      end

      scope = visible_agent_leads_scope
      scope = scope.where(agent_id: agent.id) if agent

      counts = scope.group(:delivery_status).count
      payload = {
        total: counts.values.sum,
        by_delivery_status: delivery_status_counts(counts)
      }
      payload[:agent] = { id: agent.id, name: agent.name, status: agent.status } if agent

      payload
    end

    private

    def visible_agent_leads_scope
      Pundit.policy_scope!(account, AgentLead)
            .joins(:agent)
            .merge(Agent.not_deleted.where(organization_id: organization.id))
            .joins(:lead)
            .merge(Lead.visible_in_customer_agents)
    end

    def delivery_status_counts(counts)
      AgentLead::DELIVERY_STATUSES.index_with { |status| counts[status].to_i }
    end
  end
end
