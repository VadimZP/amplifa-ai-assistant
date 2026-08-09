# frozen_string_literal: true

require 'test_helper'

class LlmModelServiceOpenrouterAllowlistTest < ActiveSupport::TestCase
  test 'openrouter allowlist includes gpt 5.5' do
    assert LlmModelService.send(:openrouter_allowed?, 'openai/gpt-5.5')
  end

  test 'openrouter allowlist includes gpt 5.4 mini' do
    assert LlmModelService.send(:openrouter_allowed?, 'openai/gpt-5.4-mini')
  end

  test 'openrouter allowlist includes glm 5.1' do
    assert LlmModelService.send(:openrouter_allowed?, 'z-ai/glm-5.1')
  end

  test 'openrouter allowlist includes deepseek v4 flash' do
    assert LlmModelService.send(:openrouter_allowed?, 'deepseek/deepseek-v4-flash')
  end

  test 'openrouter allowlist includes deepseek v4 pro' do
    assert LlmModelService.send(:openrouter_allowed?, 'deepseek/deepseek-v4-pro')
  end

  test 'openrouter allowlist includes deepseek v3.2' do
    assert LlmModelService.send(:openrouter_allowed?, 'deepseek/deepseek-v3.2')
  end

  test 'openrouter allowlist excludes non-allowlisted model' do
    refute LlmModelService.send(:openrouter_allowed?, 'meta-llama/llama-3.3-70b-instruct')
  end
end
