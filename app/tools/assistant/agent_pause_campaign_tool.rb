# frozen_string_literal: true

# Pauses one agent campaign on behalf of the user — the same path as Customer::AgentsController
# #pause_campaign. Stops all sends but preserves the schedule; only customer admins may call this.
module Assistant
  class AgentPauseCampaignTool < BaseTool
    description 'Pauses an active agent campaign — stops all email sends but preserves the schedule. ' \
                'Use agent_list first to find the agent id. Only call this after the user clearly ' \
                'named which agent to pause.'

    param :agent_id, type: :integer, desc: 'The id of the agent to pause', required: true

    def execute(agent_id:)
      agent = scoped(Agent).find_by(id: agent_id)
      # WHY the same message for foreign and unknown ids: a distinguishable answer would let a
      # caller probe which ids exist in other organizations.
      return { error: 'Agent not found.' } unless agent

      authorize!(agent, :pause_campaign?)

      unless agent.can_pause?
        return { error: 'This agent cannot be paused right now.' }
      end

      previous_status = agent.status
      agent.pause!

      success_payload(agent.reload, previous_status)
    end

    private

    def success_payload(agent, previous_status)
      {
        id: agent.id,
        name: agent.name,
        previous_status: previous_status,
        status: agent.status,
        paused_at: agent.paused_at&.iso8601
      }
    end
  end
end
