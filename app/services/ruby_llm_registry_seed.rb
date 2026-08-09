# frozen_string_literal: true

class RubyLlmRegistrySeed
  def self.call(models:, openrouter_api_key:, rails_env:, logger:)
    new(
      models: models,
      openrouter_api_key: openrouter_api_key,
      rails_env: rails_env,
      logger: logger
    ).call
  end

  def initialize(models:, openrouter_api_key:, rails_env:, logger:)
    @models = models
    @openrouter_api_key = openrouter_api_key
    @rails_env = rails_env
    @logger = logger
  end

  def call
    remove_vertexai_gemini_models!
    return unless openrouter_enabled?

    seed_qwen_family_models!
    seed_curated_openrouter_models!
  end

  private

  def openrouter_enabled?
    @openrouter_api_key.present? && @rails_env.to_s != 'test'
  end

  def seed_qwen_family_models!
    qwen_models = Model.where(provider: 'openrouter')
                       .where('model_id ILIKE ?', "#{LlmModelCatalog::OPENROUTER_QWEN_PREFIX}%")
                       .where("modalities -> 'output' ? 'text'")
    qwen_models.find_each { |record| seed_record_model!(record) }
  rescue StandardError => e
    log_seed_error('Qwen model seed failed', e)
  end

  def seed_curated_openrouter_models!
    LlmModelCatalog::OPENROUTER_DB_SEED_IDS.each do |model_id|
      record = Model.find_by(model_id: model_id, provider: 'openrouter')
      seed_record_model!(record)
    end
  rescue StandardError => e
    log_seed_error('Curated OpenRouter model seed failed', e)
  end

  def seed_record_model!(record)
    return unless record
    return if model_registered?(record.model_id, record.provider)

    @models << build_model_info(record)
  end

  def remove_vertexai_gemini_models!
    @models.reject! { |model| model.id.include?('gemini') && model.provider == 'vertexai' }
  end

  def model_registered?(model_id, provider)
    @models.any? { |model| model.id == model_id && model.provider == provider }
  end

  def build_model_info(record)
    modalities = record.modalities.is_a?(Hash) ? record.modalities.deep_symbolize_keys : {}

    RubyLLM::Model::Info.new(
      id: record.model_id,
      name: record.name,
      provider: record.provider,
      family: record.family,
      context_window: record.context_window,
      max_output_tokens: record.max_output_tokens,
      modalities: modalities,
      capabilities: Array(record.capabilities),
      metadata: record.metadata || {}
    )
  end

  def log_seed_error(message, error)
    @logger.error("[RubyLLM] #{message}: #{error.class}: #{error.message}")
  end
end
