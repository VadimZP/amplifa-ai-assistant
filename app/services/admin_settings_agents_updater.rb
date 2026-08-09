# frozen_string_literal: true

# Applies single-agent and bulk-agent changes from the global admin settings page.
class AdminSettingsAgentsUpdater
  STATUSES = %w[active paused].freeze
  EDITABLE_FIELDS = %w[
    status global_sequence_id llm_model locale use_recipient_locale buying_signals_enabled
    send_sequence_messages_from_same_mailbox
  ].freeze
  BOOLEAN_FIELDS = %w[
    use_recipient_locale buying_signals_enabled send_sequence_messages_from_same_mailbox
  ].freeze

  attr_reader :error_message

  def initialize(agent_ids, attributes, whodunnit = nil)
    @agent_ids = Array(agent_ids).map(&:to_i).uniq
    @attributes = attributes.to_h.stringify_keys
    @whodunnit = whodunnit
  end

  def call
    error = validation_error
    return fail_with(error) if error

    PaperTrail.request(whodunnit: @whodunnit) { update_settings_agents! }

    true
  rescue ActiveRecord::RecordInvalid => e
    fail_with(e.record.errors.full_messages.to_sentence)
  end

  def notice
    return 'Agent updated successfully' if settings_agents.size == 1

    "#{settings_agents.size} agents updated successfully"
  end

  private

  attr_reader :agent_ids

  def update_settings_agents!
    Agent.transaction do
      settings_agents.find_each do |agent|
        agent.paper_trail_event = 'bulk_edit' if bulk_edit?
        agent.update!(normalized_attributes)
      end
    end
  end

  def settings_agents
    @settings_agents ||= Agent.not_deleted.where(id: agent_ids)
  end

  def invalid_agent_selection?
    agent_ids.empty? || settings_agents.size != agent_ids.size
  end

  def validation_error
    return 'Select at least one valid agent' if invalid_agent_selection?
    return 'Select at least one agent setting to update' if normalized_attributes.empty?
    return 'Select active or paused status' if invalid_status?
    return 'Select a supported locale' if @attributes.key?('locale') && !SupportedLocale.include?(@attributes['locale'])
    return 'Select a supported model' if invalid_llm_model?

    nil
  end

  def invalid_status?
    @attributes.key?('status') && !STATUSES.include?(@attributes['status'])
  end

  def invalid_llm_model?
    @attributes.key?('llm_model') && !LlmModelService.valid_model?(@attributes['llm_model'])
  end

  def bulk_edit?
    agent_ids.size > 1
  end

  def normalized_attributes
    @attributes.slice(*EDITABLE_FIELDS).tap do |attributes|
      if attributes.key?('global_sequence_id')
        attributes['global_sequence_id'] = attributes['global_sequence_id'].presence
      end
      cast_boolean_attributes(attributes, *BOOLEAN_FIELDS)
    end
  end

  def cast_boolean_attributes(attributes, *attribute_names)
    boolean_type = ActiveModel::Type::Boolean.new
    attribute_names.each do |attribute_name|
      attributes[attribute_name] = boolean_type.cast(attributes[attribute_name]) if attributes.key?(attribute_name)
    end
  end

  def fail_with(message)
    @error_message = message
    false
  end
end
