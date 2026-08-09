# frozen_string_literal: true

module LlmModelCatalog
  OPENROUTER_QWEN_PREFIX = 'qwen/qwen3'

  OPENROUTER_ALLOWLIST = %w[
    openai/gpt-5.5
    openai/gpt-5.4-mini
    anthropic/claude-opus-4.6
    anthropic/claude-opus-4.5
    anthropic/claude-sonnet-5
    anthropic/claude-sonnet-4.6
    anthropic/claude-sonnet-4.5
    deepseek/deepseek-v4-pro
    deepseek/deepseek-v4-flash
    deepseek/deepseek-v3.2
    z-ai/glm-5.1
    qwen/qwen3.5-plus-02-15
    qwen/qwen3.5-flash-02-23
    moonshotai/kimi-k2.5
  ].freeze

  OPENROUTER_DB_SEED_IDS = OPENROUTER_ALLOWLIST.freeze

  def self.openrouter_allowed?(model_id)
    OPENROUTER_ALLOWLIST.include?(model_id) || model_id.start_with?(OPENROUTER_QWEN_PREFIX)
  end
end
