# frozen_string_literal: true

# Lists leads assigned to agents (campaign entries) for the assistant. Mirrors
# Customer::AgentsController#filtered_agent_leads_scope so the model can answer which leads are
# in which agent and where they are in the email sequence.
module Assistant
  class AgentLeadListTool < BaseTool
    DEFAULT_LIMIT = 20
    MAX_LIMIT = 50
    MAX_OFFSET = 1_000
    IN_SEQUENCE_FIRST_SQL = "CASE WHEN agent_leads.delivery_status = 'in_sequence' THEN 0 ELSE 1 END"

    description 'Lists leads assigned to agents (campaign entries), including delivery status and ' \
                'sequence step. Returns matching rows plus total_count. Call this before answering ' \
                'which leads are in a campaign — never claim a lead is not in a campaign without ' \
                'calling this tool first. Use agent_list to find agent ids; use agent_stats for ' \
                'aggregate counts by delivery status. Read-only.'

    param :agent_id, type: :integer,
          desc: 'Filter to one agent. Find ids with agent_list first — never guess an id.',
          required: false
    param :delivery_status,
          desc: "Filter by delivery status. One of: #{AgentLead::DELIVERY_STATUSES.join(', ')}",
          required: false
    param :search, desc: 'Free-text search over lead first name, last name, email and company',
                   required: false
    param :limit, type: :integer, desc: "Rows to return (default #{DEFAULT_LIMIT}, max #{MAX_LIMIT})",
                  required: false
    param :offset, type: :integer, desc: 'Rows to skip, for paging through more results', required: false

    def execute(agent_id: nil, delivery_status: nil, search: nil, limit: DEFAULT_LIMIT, offset: 0)
      if delivery_status.present? && AgentLead::DELIVERY_STATUSES.exclude?(delivery_status.to_s)
        return invalid_enum('delivery_status', delivery_status, AgentLead::DELIVERY_STATUSES)
      end

      if agent_id.present?
        agent = scoped(Agent).find_by(id: agent_id)
        return { error: 'Agent not found.' } unless agent
      end

      scope = filtered_scope(agent_id:, delivery_status:, search:)
      total = scope.count
      rows = scope.includes(:agent, :lead, generated_messages: [])
                  .offset(offset.to_i.clamp(0, MAX_OFFSET))
                  .limit(limit.to_i.clamp(1, MAX_LIMIT))
                  .to_a

      { total_count: total, returned_count: rows.size, agent_leads: serialize(rows) }
    end

    private

    def filtered_scope(agent_id:, delivery_status:, search:)
      scope = visible_agent_leads_scope
      scope = scope.where(agent_id: agent_id) if agent_id.present?
      scope = scope.where(delivery_status: delivery_status.to_s) if delivery_status.present?
      scope = apply_search(scope, search) if search.present?
      scope.order(Arel.sql(IN_SEQUENCE_FIRST_SQL), created_at: :desc)
    end

    def visible_agent_leads_scope
      # WHY not BaseTool#scoped: AgentLead has no organization_id column; tenant boundary is via agent.
      Pundit.policy_scope!(account, AgentLead)
            .joins(:agent)
            .merge(Agent.not_deleted.where(organization_id: organization.id))
            .joins(:lead)
            .merge(Lead.visible_in_customer_agents)
    end

    def apply_search(scope, search)
      LeadSearchSql.apply(scope, search)
    end

    def serialize(rows)
      rows.map do |agent_lead|
        current_step = agent_lead.current_step
        return_date = agent_lead.lead.out_of_office_return_date

        {
          id: agent_lead.id,
          delivery_status: agent_lead.delivery_status,
          sequence_position: agent_lead.sequence_position,
          current_step_name: current_step&.name,
          total_messages_sent: agent_lead.generated_messages.count { |message| message.status == 'sent' },
          last_sent_at: agent_lead.last_sent_at&.iso8601,
          next_send_at: agent_lead.next_send_at&.iso8601,
          meeting_booked_at: agent_lead.meeting_booked_at&.iso8601,
          currently_out_of_office: return_date.present? && return_date >= Date.current,
          agent: {
            id: agent_lead.agent.id,
            name: agent_lead.agent.name
          },
          lead: {
            id: agent_lead.lead.id,
            name: agent_lead.lead.display_name,
            email: agent_lead.lead.email,
            company: agent_lead.lead.company,
            job_title: agent_lead.lead.job_title,
            blacklisted: agent_lead.lead.blacklisted?
          }
        }
      end
    end

    def invalid_enum(field, value, allowed)
      { error: "Unknown #{field} '#{value.to_s.truncate(30)}'. Valid values: #{allowed.join(', ')}." }
    end
  end
end
