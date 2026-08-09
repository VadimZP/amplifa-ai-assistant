# frozen_string_literal: true

# Lists agents (running campaigns) in the current organization for the assistant. Mirrors the
# agent picker data in Customer::AgentsController#index so the model can find ids by name before
# calling agent_pause_campaign or agent_resume_campaign.
module Assistant
  class AgentListTool < BaseTool
    DEFAULT_LIMIT = 20
    MAX_LIMIT = 50

    description 'Lists agents (running campaigns) in the current organization, ordered by name. ' \
                'Returns matching rows plus total_count and high-level campaign counters. ' \
                'Read-only — use agent_stats for delivery-status counts and agent_lead_list for ' \
                'individual leads and sequence steps.'

    param :search, desc: 'Free-text search over agent name', required: false
    param :status, desc: "Filter by agent status. One of: #{Agent::VISIBLE_STATUSES.join(', ')}",
                   required: false
    param :limit, type: :integer, desc: "Rows to return (default #{DEFAULT_LIMIT}, max #{MAX_LIMIT})",
                  required: false

    def execute(search: nil, status: nil, limit: DEFAULT_LIMIT)
      if status.present? && Agent::VISIBLE_STATUSES.exclude?(status.to_s)
        return invalid_enum('status', status, Agent::VISIBLE_STATUSES)
      end

      scope = filtered_scope(status:, search:)
      total = scope.count
      rows = scope.limit(limit.to_i.clamp(1, MAX_LIMIT)).to_a

      { total_count: total, returned_count: rows.size, agents: serialize(rows) }
    end

    private

    def filtered_scope(status:, search:)
      scope = scoped(Agent).includes(:playbook).order(:name)
      scope = scope.where(status: status.to_s) if status.present?
      scope = apply_search(scope, search) if search.present?
      scope
    end

    def apply_search(scope, search)
      term = "%#{ActiveRecord::Base.sanitize_sql_like(search.to_s.strip)}%"
      scope.where('agents.name ILIKE :term', term: term)
    end

    def serialize(rows)
      rows.map do |agent|
        {
          id: agent.id,
          name: agent.name,
          status: agent.status,
          launched: agent.launched?,
          launched_at: agent.launched_at&.iso8601,
          playbook_approved: agent.playbook&.approved? || false,
          playbook_name: agent.playbook&.product_name,
          total_leads_count: agent.total_leads_count,
          contacted_count: agent.contacted_count,
          replied_count: agent.replied_count,
          meetings_booked_count: agent.meetings_booked_count,
          can_pause: agent.can_pause?,
          can_resume: agent.can_resume?
        }
      end
    end

    def invalid_enum(field, value, allowed)
      { error: "Unknown #{field} '#{value.to_s.truncate(30)}'. Valid values: #{allowed.join(', ')}." }
    end
  end
end
