# frozen_string_literal: true

# Generates the assistant's reply for one chat turn and streams it to the browser.
#
# WHY it does not use ruby_llm's `chat.ask`: `acts_as_chat` replays *every* persisted message, which
# defeats the whole point of the rolling summary. We build a plain RubyLLM::Chat, seed it with the
# system prompt + `chat.summary` + only the messages after the summary watermark, and persist the
# assistant message ourselves.
class AssistantReplyService
  Result = Struct.new(:success?, :error, :message, keyword_init: true)

  # WHY: A fast, cheap model. The assistant answers conversationally, so latency matters more than
  # frontier reasoning. Same default the app already configures in config/initializers/ruby_llm.rb.
  MODEL = 'deepseek/deepseek-v4-flash'
  PROVIDER = :openrouter

  # WHY: Deltas are coalesced into one broadcast every BROADCAST_INTERVAL rather than one per token,
  # so a fast stream can't flood ActionCable with hundreds of tiny frames per second.
  BROADCAST_INTERVAL = 0.08

  # The tools the assistant can call during a turn. Each is instantiated per turn with the
  # chat's account + organization so it can never act outside that tenant.
  TOOL_CLASSES = [
    Assistant::ConversationListTool,
    Assistant::ConversationStatsTool,
    Assistant::ConversationReadTool,
    Assistant::ConversationUpdateInterestStatusTool,
    Assistant::LeadSearchTool,
    Assistant::AgentListTool,
    Assistant::AgentStatsTool,
    Assistant::AgentLeadListTool,
    Assistant::AgentPauseCampaignTool,
    Assistant::AgentResumeCampaignTool,
    Assistant::MeetingListTool,
    Assistant::MeetingReadTool,
    Assistant::MeetingCreateTool,
    Assistant::MeetingRescheduleTool,
    Assistant::MeetingCancelTool
  ].freeze

  def self.call(...) = new(...).call

  def initialize(chat:)
    @chat = chat
    @buffer = +''
    @last_broadcast_at = nil
    @current_tool = nil
  end

  def call
    assistant_message = @chat.messages.create!(role: 'assistant', content: '')
    broadcast(type: 'start', message_id: assistant_message.id)

    response = with_tenant_context do
      llm_chat = build_llm_chat(assistant_message)
      llm_chat.complete { |chunk| handle_chunk(chunk, assistant_message) }
    end
    content = @buffer.presence || response&.content.to_s

    # WHY: A provider can return 200 with no content. Treat that as a failure rather than persisting
    # an empty bubble the user would read as a broken reply.
    if content.blank?
      Rails.logger.error("[AssistantReplyService] chat ##{@chat.id} returned an empty completion")
      discard_empty_message(assistant_message)
      return Result.new(success?: false, error: :empty_completion, message: nil)
    end

    finalize!(assistant_message, content)
    Result.new(success?: true, error: nil, message: assistant_message)
  rescue RubyLLM::Error => e
    # WHY: The provider's raw message can contain keys, model ids and internal URLs, so it is logged
    # but never returned. The caller substitutes a t() string.
    Rails.logger.error("[AssistantReplyService] chat ##{@chat.id} LLM error: #{e.class}: #{e.message}")
    discard_empty_message(assistant_message)
    Result.new(success?: false, error: :llm_unavailable, message: nil)
  rescue StandardError => e
    Rails.logger.error("[AssistantReplyService] chat ##{@chat.id} failed: #{e.class}: #{e.message}")
    discard_empty_message(assistant_message)
    Result.new(success?: false, error: :unexpected, message: nil)
  end

  private

  # WHY `assume_model_exists`: this model is not in ruby_llm's bundled models.json — it only reaches the
  # registry through RubyLlmRegistrySeed, which no-ops when no OpenRouter key is set at boot. A server
  # started before the key was configured would then raise ModelNotFoundError on every turn. The
  # provider is explicit, so skipping the registry lookup is safe and removes the boot-order coupling.
  def build_llm_chat(assistant_message)
    llm_chat = RubyLLM.chat(model: MODEL, provider: PROVIDER, assume_model_exists: true)
    llm_chat.with_instructions(system_prompt)
    llm_chat.with_instructions(summary_instruction) if @chat.summary?
    llm_chat.with_tools(*build_tools)
    llm_chat.on_tool_call { |tool_call| handle_tool_call(tool_call, assistant_message) }
    llm_chat.on_tool_result { |result| handle_tool_result(result, assistant_message) }

    # WHY: Only the tail after the summary watermark is replayed verbatim; everything older is
    # already represented by `summary_instruction` above.
    @chat.messages_after_summary.each do |message|
      content = message.content.to_s
      next if content.blank?

      llm_chat.add_message(role: message.role.to_sym, content: content)
    end

    llm_chat
  end

  # WHY: Pundit policies resolve the tenant and role from Current, which is empty inside a
  # background job. Without this every tool scope would fail closed and return no rows. A user
  # whose membership was revoked since the chat started gets a nil membership — and correctly
  # keeps getting no rows.
  def with_tenant_context(&)
    membership = @chat.account.organization_memberships.active.find_by(organization_id: @chat.organization_id)
    Current.set(account: @chat.account, organization: @chat.organization, organization_membership: membership, &)
  end

  def build_tools
    TOOL_CLASSES.map { |klass| klass.new(account: @chat.account, organization: @chat.organization) }
  end

  def handle_tool_call(tool_call, assistant_message)
    @current_tool = { id: tool_call.id, name: tool_call.name }
    # WHY: Any text the model streamed before deciding to call a tool would otherwise concatenate
    # directly with the first words of the post-tool answer in one buffer.
    @buffer << "\n\n" if @buffer.present? && !@buffer.end_with?("\n")
    broadcast(type: 'tool_start', message_id: assistant_message.id,
              call_id: tool_call.id, tool: tool_call.name)
  end

  # WHY the result is inspected here: ruby_llm 1.11's on_tool_result callback receives only the
  # return value. Tools report failures as JSON { error: } payloads (they never raise — see
  # Assistant::BaseTool), so parsing is the one way to tell the UI whether the chip is a success.
  def handle_tool_result(result, assistant_message)
    current = @current_tool || {}
    broadcast(type: 'tool_end', message_id: assistant_message.id,
              call_id: current[:id], tool: current[:name],
              status: tool_result_error?(result) ? 'error' : 'ok')
  end

  def tool_result_error?(result)
    return false unless result.is_a?(String)

    parsed = JSON.parse(result)
    parsed.is_a?(Hash) && parsed.key?('error')
  rescue JSON::ParserError
    false
  end

  def system_prompt
    AssistantPrompt.system_prompt(organization: @chat.organization, account: @chat.account)
  end

  def summary_instruction
    AssistantPrompt.summary_instruction(@chat.summary)
  end

  def handle_chunk(chunk, assistant_message)
    delta = chunk.content.to_s
    return if delta.empty?

    @buffer << delta
    return unless throttle_elapsed?

    @last_broadcast_at = monotonic_now
    broadcast(type: 'delta', message_id: assistant_message.id, content: @buffer)
  end

  def throttle_elapsed?
    @last_broadcast_at.nil? || (monotonic_now - @last_broadcast_at) >= BROADCAST_INTERVAL
  end

  def monotonic_now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  def finalize!(assistant_message, content)
    assistant_message.update!(content: content)
    @chat.update!(last_message_at: Time.current)
    broadcast(type: 'done', message_id: assistant_message.id, content: content)
  end

  def discard_empty_message(assistant_message)
    # WHY: An assistant row with blank content would be replayed to the LLM on the next turn and
    # rendered as an empty bubble, so remove it rather than leaving a broken turn in history.
    assistant_message&.destroy if assistant_message&.persisted? && assistant_message.content.blank?
  rescue StandardError => e
    Rails.logger.error("[AssistantReplyService] failed to discard empty message: #{e.class}: #{e.message}")
  end

  def broadcast(payload)
    AssistantChatChannel.broadcast_to(@chat, payload)
  rescue StandardError => e
    # WHY: A dropped broadcast must not fail the turn — the message is already persisted, so a
    # reload recovers the full reply.
    Rails.logger.warn("[AssistantReplyService] broadcast failed for chat ##{@chat.id}: #{e.class}: #{e.message}")
  end
end
