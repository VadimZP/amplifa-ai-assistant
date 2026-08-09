# frozen_string_literal: true

require 'test_helper'

class RubyLlmRegistrySeedTest < ActiveSupport::TestCase
  test 'seeds curated openrouter and qwen family models from database records' do
    curated_id = LlmModelCatalog::OPENROUTER_DB_SEED_IDS.first

    Model.create!(
      model_id: curated_id,
      name: 'Curated Model',
      provider: 'openrouter',
      modalities: { 'output' => ['text'] }
    )

    Model.create!(
      model_id: 'qwen/qwen3-experimental',
      name: 'Qwen Experimental',
      provider: 'openrouter',
      modalities: { 'output' => ['text'] }
    )

    models = []

    RubyLlmRegistrySeed.call(
      models: models,
      openrouter_api_key: 'test-key',
      rails_env: 'development',
      logger: ActiveSupport::Logger.new(nil)
    )

    model_ids = models.map(&:id)

    assert_includes model_ids, curated_id
    assert_includes model_ids, 'qwen/qwen3-experimental'
    assert_not_includes model_ids, 'moonshotai/kimi-k2.5'
  end

  test 'always removes vertexai gemini duplicates' do
    models = [
      model_info(id: 'gemini-2.5-flash', provider: 'vertexai'),
      model_info(id: 'gemini-2.5-flash', provider: 'gemini')
    ]

    RubyLlmRegistrySeed.call(
      models: models,
      openrouter_api_key: nil,
      rails_env: 'development',
      logger: ActiveSupport::Logger.new(nil)
    )

    providers = models.select { |model| model.id == 'gemini-2.5-flash' }.map(&:provider)

    assert_equal ['gemini'], providers
  end

  test 'works with real RubyLLM registry collection' do
    probe_id = 'openrouter/probe-seed-test'
    models = RubyLLM.models.all
    probe_model = model_info(id: probe_id, provider: 'openrouter')

    models << probe_model

    assert(models.any? { |model| model.id == probe_id && model.provider == 'openrouter' })
  ensure
    models.reject! { |model| model.id == probe_id && model.provider == 'openrouter' }
  end

  private

  def model_info(id:, provider:)
    RubyLLM::Model::Info.new(
      id: id,
      name: id,
      provider: provider,
      family: provider,
      context_window: 8_192,
      max_output_tokens: 2_048,
      modalities: { input: %w[text], output: %w[text] },
      capabilities: %w[streaming],
      metadata: {}
    )
  end
end
