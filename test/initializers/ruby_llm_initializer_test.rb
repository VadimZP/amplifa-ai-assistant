# frozen_string_literal: true

require 'test_helper'

class RubyLlmInitializerTest < ActiveSupport::TestCase
  class PayloadBase
    def render_payload(_messages, **kwargs)
      kwargs.fetch(:payload)
    end
  end

  class PayloadRenderer < PayloadBase
    prepend OpenRouterAnthropicStructuredOutputFix
    prepend OpenRouterDeepSeekV4ProProviderFix
  end

  test 'removes strict keys for anthropic structured output payloads' do
    payload = {
      response_format: {
        json_schema: {
          strict: true,
          schema: {
            strict: true,
            properties: {
              foo: { type: 'string', strict: true }
            }
          }
        }
      }
    }

    model = Struct.new(:id).new('anthropic/claude-opus-4.6')
    result = PayloadRenderer.new.render_payload([], payload: payload.deep_dup, model: model, schema: { type: 'object' })

    refute includes_strict_key?(result)
  end

  test 'keeps strict keys for non-anthropic payloads' do
    payload = {
      response_format: {
        json_schema: {
          strict: true,
          schema: {
            properties: {
              foo: { type: 'string', strict: true }
            }
          }
        }
      }
    }

    model = Struct.new(:id).new('openai/gpt-5-mini')
    result = PayloadRenderer.new.render_payload([], payload: payload.deep_dup, model: model, schema: { type: 'object' })

    assert includes_strict_key?(result)
  end

  test 'prefers official deepseek provider for deepseek v4 pro openrouter payloads' do
    payload = {
      model: 'deepseek/deepseek-v4-pro',
      messages: []
    }

    model = Struct.new(:id).new('deepseek/deepseek-v4-pro')
    result = PayloadRenderer.new.render_payload([], payload: payload.deep_dup, model: model)

    assert_equal({ order: ['deepseek'], allow_fallbacks: true }, result[:provider])
  end

  test 'overrides existing provider routing to prefer deepseek for v4 pro openrouter payloads' do
    payload = {
      model: 'deepseek/deepseek-v4-pro',
      provider: { only: ['deepinfra'], allow_fallbacks: true },
      'provider' => { 'only' => ['siliconflow'], 'allow_fallbacks' => true }
    }

    model = Struct.new(:id).new('deepseek/deepseek-v4-pro')
    result = PayloadRenderer.new.render_payload([], payload: payload.deep_dup, model: model)

    assert_equal({ order: ['deepseek'], allow_fallbacks: true }, result[:provider])
    refute result.key?('provider')
  end

  test 'prepends deepseek provider fix to ruby llm openrouter provider' do
    assert_includes RubyLLM::Providers::OpenRouter.ancestors, OpenRouterDeepSeekV4ProProviderFix
  end

  test 'does not force deepseek provider for other openrouter models' do
    payload = {
      model: 'deepseek/deepseek-v4-flash',
      messages: []
    }

    model = Struct.new(:id).new('deepseek/deepseek-v4-flash')
    result = PayloadRenderer.new.render_payload([], payload: payload.deep_dup, model: model)

    refute result.key?(:provider)
  end

  test 'enables new acts_as mode in early configuration' do
    assert RubyLLM.config.use_new_acts_as
  end

  private

  def includes_strict_key?(value)
    case value
    when Hash
      value.key?(:strict) || value.key?('strict') || value.any? { |_, child| includes_strict_key?(child) }
    when Array
      value.any? { |child| includes_strict_key?(child) }
    else
      false
    end
  end
end
