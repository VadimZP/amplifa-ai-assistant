# frozen_string_literal: true

# Updates the interest classification of one conversation on behalf of the user — the assistant's
# first write tool. All mutation logic (meeting auto-create/remove, blacklist sync, transactions)
# lives in ConversationInterestStatusUpdater, the same service the inbox and agents UIs call; this
# tool only adds scoping, authorization and a model-facing payload.
module Assistant
  class ConversationUpdateInterestStatusTool < BaseTool
    # WHY status is reported around the service call instead of read from it: the updater's Result
    # only carries success/error. Comparing the lead's active meetings before and after lets the
    # assistant tell the user a Scheduling meeting appeared on (or left) the Meetings page.
    ACTIVE_MEETING_EXCLUDED_STATUSES = %w[cancelled pending_removal].freeze

    description 'Changes the interest status of one email conversation, exactly as the user could ' \
                'in the inbox. Side effects: interested/meeting_request auto-creates a meeting in ' \
                'Scheduling if none exists; moving away removes it. Use conversation_list first to ' \
                'find the conversation id. Only call this after the user clearly named the ' \
                'conversation and the target status.'

    param :conversation_id, type: :integer, desc: 'The id of the conversation to update', required: true
    param :interest_status,
          desc: "The new interest status. One of: #{ConversationInterestStatusUpdater::SUPPORTED_STATUSES.join(', ')}",
          required: true

    def execute(conversation_id:, interest_status:)
      status = interest_status.to_s
      if ConversationInterestStatusUpdater::SUPPORTED_STATUSES.exclude?(status)
        return invalid_enum('interest_status', interest_status,
                            ConversationInterestStatusUpdater::SUPPORTED_STATUSES)
      end

      conversation = scoped(Conversation).find_by(id: conversation_id)
      # WHY the same message for foreign and unknown ids: a distinguishable answer would let a
      # caller probe which ids exist in other organizations.
      return { error: 'Conversation not found.' } unless conversation

      authorize!(conversation, :update_interest_status?)

      previous_status = conversation.interest_status
      meetings_before = active_meeting_count(conversation)

      # WHY reason_context :manual: the user explicitly asked for this change (same as the agents
      # modal path), as opposed to an automatic classification from a reply.
      result = ConversationInterestStatusUpdater.new(
        conversation: conversation,
        target_status: status,
        actor: account,
        reason_context: :manual
      ).call
      # Updater errors are already human-readable sentences, safe to relay to the model.
      return { error: result.error } unless result.success?

      success_payload(conversation.reload, previous_status, meetings_before)
    end

    private

    def success_payload(conversation, previous_status, meetings_before)
      {
        id: conversation.id,
        lead_name: conversation.lead.display_name,
        company: conversation.lead.company,
        previous_interest_status: previous_status,
        interest_status: conversation.interest_status,
        meeting_effect: meeting_effect(meetings_before, active_meeting_count(conversation))
      }
    end

    def meeting_effect(before, after)
      return 'created' if after > before
      return 'removed' if after < before

      'unchanged'
    end

    def active_meeting_count(conversation)
      Meeting.where(organization_id: organization.id, lead_id: conversation.lead_id)
             .where.not(status: ACTIVE_MEETING_EXCLUDED_STATUSES)
             .count
    end

    def invalid_enum(field, value, allowed)
      { error: "Unknown #{field} '#{value.to_s.truncate(30)}'. Valid values: #{allowed.join(', ')}." }
    end
  end
end
