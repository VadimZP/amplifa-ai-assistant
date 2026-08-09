# frozen_string_literal: true

require 'test_helper'

class LlmModelServiceTest < ActiveSupport::TestCase
  # WHY: Need to ensure we have models in the database for testing
  setup do
    # Create test models if none exist
    unless Model.exists?
      Model.create!(
        model_id: 'gpt-4',
        name: 'GPT-4',
        provider: 'openai',
        modalities: { 'input' => ['text'], 'output' => ['text'] }
      )
      Model.create!(
        model_id: 'claude-3-opus',
        name: 'Claude 3 Opus',
        provider: 'anthropic',
        modalities: { 'input' => ['text'], 'output' => ['text'] }
      )
      Model.create!(
        model_id: 'gemini-2.5-flash-lite',
        name: 'Gemini 2.5 Flash-Lite',
        provider: 'gemini',
        modalities: { 'input' => ['text'], 'output' => ['text'] }
      )
      # Embedding model should be excluded
      Model.create!(
        model_id: 'text-embedding-004',
        name: 'Text Embedding 004',
        provider: 'gemini',
        modalities: { 'input' => ['text'], 'output' => ['embedding'] }
      )
    end
  end

  # WHY: Verify the service returns models suitable for chat/text generation
  test 'available_models returns chat models with text output' do
    models = LlmModelService.available_models

    assert models.is_a?(Array), 'Should return an array'
    assert models.any?, 'Should return at least one model'

    # Each model should have the expected keys
    models.each do |model|
      assert model[:id].present?, 'Model should have an id'
      assert model[:name].present?, 'Model should have a name'
      assert model[:provider].present?, 'Model should have a provider'
      assert model[:display_name].present?, 'Model should have a display_name'
    end
  end

  # WHY: Verify embedding models are excluded from the list
  test 'available_models excludes embedding models' do
    models = LlmModelService.available_models

    model_ids = models.map { |m| m[:id] }
    refute model_ids.include?('text-embedding-004'), 'Should exclude embedding models'
  end

  # WHY: Verify models are grouped correctly by provider
  test 'grouped_by_provider returns models grouped by provider' do
    grouped = LlmModelService.grouped_by_provider

    assert grouped.is_a?(Hash), 'Should return a hash'

    grouped.each do |provider, models|
      assert provider.is_a?(String), 'Provider key should be a string'
      assert models.is_a?(Array), 'Provider value should be an array'
      models.each do |model|
        assert_equal provider, model[:provider], 'All models in group should have matching provider'
      end
    end
  end

  # WHY: Verify the for_select method returns data suitable for select dropdowns
  test 'for_select returns array of [display_name, id] pairs' do
    select_options = LlmModelService.for_select

    assert select_options.is_a?(Array), 'Should return an array'

    select_options.each do |option|
      assert option.is_a?(Array), 'Each option should be an array'
      assert_equal 2, option.length, 'Each option should have 2 elements'
      assert option[0].is_a?(String), 'First element (display_name) should be a string'
      assert option[1].is_a?(String), 'Second element (id) should be a string'
    end
  end

  # WHY: Verify the valid_model? method validates against selectable models
  test 'valid_model? returns true for available models' do
    model_id = LlmModelService.available_models.first[:id]

    assert model_id.present?, 'Expected at least one available model'
    assert LlmModelService.valid_model?(model_id), 'Should return true for an available model'
  end

  # WHY: Blank model_id should be valid (uses default)
  test 'valid_model? returns true for blank model_id' do
    assert LlmModelService.valid_model?(nil), 'Should return true for nil'
    assert LlmModelService.valid_model?(''), 'Should return true for empty string'
  end

  # WHY: Verify invalid models are detected
  test 'valid_model? returns false for non-existent models' do
    refute LlmModelService.valid_model?('non-existent-model'), 'Should return false for non-existent model'
  end

  test 'valid_model? uses curated availability rather than raw database existence' do
    Model.create!(
      model_id: 'custom/test-db-model',
      name: 'Custom DB Model',
      provider: 'openrouter',
      modalities: { 'input' => ['text'], 'output' => ['text'] }
    )

    LlmModelService.stub :available_models, [{ id: 'another/model' }] do
      refute LlmModelService.valid_model?('custom/test-db-model')
    end
  end
end
