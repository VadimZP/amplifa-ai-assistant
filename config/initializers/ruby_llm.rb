# frozen_string_literal: true

# Patch OpenRouter structured output for Anthropic models.
# RubyLLM/OpenRouter include a `strict` key in the JSON schema payload; Anthropic rejects it.
module OpenRouterAnthropicStructuredOutputFix
  def render_payload(messages, **kwargs)
    payload = super(messages, **kwargs)

    model = kwargs[:model]
    schema = kwargs[:schema]

    return payload unless schema && model&.id.to_s.start_with?('anthropic/')

    response_format = payload[:response_format]
    json_schema = response_format.is_a?(Hash) ? (response_format[:json_schema] || response_format['json_schema']) : nil
    deep_delete_strict!(json_schema)

    payload
  end

  private

  def deep_delete_strict!(obj)
    case obj
    when Hash
      obj.delete(:strict)
      obj.delete('strict')
      obj.each_value { |value| deep_delete_strict!(value) }
    when Array
      obj.each { |value| deep_delete_strict!(value) }
    end
  end
end

RubyLLM::Providers::OpenRouter.prepend(OpenRouterAnthropicStructuredOutputFix)

# Prefers OpenRouter's official DeepSeek provider for DeepSeek v4 Pro.
module OpenRouterDeepSeekV4ProProviderFix
  DEEPSEEK_V4_PRO_MODEL_ID = 'deepseek/deepseek-v4-pro'
  DEEPSEEK_PROVIDER_SLUG = 'deepseek'

  def render_payload(messages, **kwargs)
    payload = super(messages, **kwargs)

    return payload unless kwargs[:model]&.id.to_s == DEEPSEEK_V4_PRO_MODEL_ID

    payload.delete('provider')
    payload[:provider] = {
      order: [DEEPSEEK_PROVIDER_SLUG],
      allow_fallbacks: true
    }

    payload
  end
end

RubyLLM::Providers::OpenRouter.prepend(OpenRouterDeepSeekV4ProProviderFix)

openrouter_api_key = ENV['OPENROUTER_API_KEY'].presence ||
                     Rails.application.credentials.dig(:openrouter, :api_key)

RubyLLM.configure do |config|
  config.openrouter_api_key = openrouter_api_key
  config.default_model = 'deepseek/deepseek-v4-flash'
end

Rails.application.config.after_initialize do
  RubyLlmRegistrySeed.call(
    models: RubyLLM.models.all,
    openrouter_api_key: openrouter_api_key,
    rails_env: Rails.env,
    logger: Rails.logger
  )
end
