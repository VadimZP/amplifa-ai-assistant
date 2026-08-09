# frozen_string_literal: true

# LlmModelService provides available LLM models for message generation.
# Uses RubyLLM's native filtering to select chat models from configured providers.
class LlmModelService
  CONFIGURED_PROVIDERS = %i[openai gemini openrouter].freeze
  FallbackModel = Struct.new(
    :model_id, :name, :provider, :context_window, :max_output_tokens, :modalities, keyword_init: true
  )

  def self.available_models
    latest_aliases(filter_models(load_models))
      .sort_by { |model| [model.provider, model.name] }
      .map { |model| serialize_model(model) }
  end

  # Returns models grouped by provider for dropdown display
  def self.grouped_by_provider = available_models.group_by { |m| m[:provider] }

  # Returns a flat list suitable for select dropdowns
  def self.for_select = available_models.map { |m| [m[:display_name], m[:id]] }

  # Validates if a model_id is available
  def self.valid_model?(model_id)
    return true if model_id.blank? || openrouter_allowed?(model_id)

    available_models.any? { |model| model[:id] == model_id }
  rescue StandardError => e
    Rails.logger.warn("[LlmModelService] Model validation failed for #{model_id}: #{e.class}: #{e.message}")
    false
  end

  def self.latest_aliases(models)
    models.group_by { |model| [model.provider, model.name] }.values.map do |group|
      group.max_by { |model| latest_alias_priority(model_identifier(model)) }
    end
  end
  private_class_method :latest_aliases

  def self.load_models
    models = CONFIGURED_PROVIDERS.flat_map do |provider|
      load_models_for_provider(provider)
    end
    models.presence || persisted_models.presence || curated_openrouter_models
  end
  private_class_method :load_models

  def self.persisted_models
    Model.where(provider: CONFIGURED_PROVIDERS.map(&:to_s)).to_a
  rescue StandardError => e
    Rails.logger.warn("[LlmModelService] Failed loading persisted models: #{e.class}: #{e.message}")
    []
  end
  private_class_method :persisted_models

  def self.curated_openrouter_models
    LlmModelCatalog::OPENROUTER_ALLOWLIST.map do |model_id|
      FallbackModel.new(
        model_id: model_id,
        name: model_id,
        provider: 'openrouter',
        context_window: nil,
        max_output_tokens: nil,
        modalities: { output: ['text'] }
      )
    end
  end
  private_class_method :curated_openrouter_models

  def self.load_models_for_provider(provider)
    RubyLLM.models.chat_models.by_provider(provider).to_a
  rescue StandardError => e
    Rails.logger.warn("[LlmModelService] Failed loading models for #{provider}: #{e.class}: #{e.message}")
    []
  end
  private_class_method :load_models_for_provider

  def self.serialize_model(model)
    {
      id: model_identifier(model),
      name: model.name,
      provider: model.provider,
      display_name: "#{model.provider.capitalize}: #{model.name}",
      context_window: model.context_window,
      max_output_tokens: model.max_output_tokens
    }
  end
  private_class_method :serialize_model

  def self.filter_models(models)
    models.select do |model|
      next false unless text_output_model?(model)

      if model.provider.to_s == 'openrouter'
        openrouter_allowed?(model_identifier(model))
      else
        true
      end
    end
  end
  private_class_method :filter_models

  def self.text_output_model?(model)
    return false if model_identifier(model).to_s.include?('embedding')

    modalities = extract_modalities(model)
    return true unless modalities

    output_modalities = Array(modalities[:output] || modalities['output'])
    return true if output_modalities.empty?

    output_modalities.map(&:to_s).include?('text')
  end
  private_class_method :text_output_model?

  def self.extract_modalities(model)
    modalities = model.respond_to?(:modalities) ? model.modalities : nil
    if modalities.blank? && model.respond_to?(:provider)
      record = Model.find_by(provider: model.provider, model_id: model_identifier(model))
      modalities = record&.modalities
    end

    return modalities if modalities.is_a?(Hash)

    nil
  end
  private_class_method :extract_modalities

  def self.openrouter_allowed?(model_id) = LlmModelCatalog.openrouter_allowed?(model_id)
  private_class_method :openrouter_allowed?

  def self.model_identifier(model) = model.respond_to?(:model_id) ? model.model_id : model.id
  private_class_method :model_identifier

  def self.latest_alias_priority(model_id)
    if model_id.end_with?('-latest')
      [2, Date.new(0)]
    elsif model_id.match?(/-\d{4}-\d{2}-\d{2}\z/)
      [0, date_suffix(model_id) || Date.new(0)]
    else
      [1, Date.new(0)]
    end
  end
  private_class_method :latest_alias_priority

  def self.date_suffix(model_id)
    match = model_id.match(/-(\d{4}-\d{2}-\d{2})\z/)
    return unless match

    Date.iso8601(match[1])
  rescue Date::Error
    nil
  end
  private_class_method :date_suffix
end
