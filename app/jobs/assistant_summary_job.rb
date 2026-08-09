# frozen_string_literal: true

# Compresses the older part of a long chat into `chat.summary`.
#
# WHY: Replaying an entire conversation on every turn grows linearly in cost and eventually blows the
# context window. Every Chat::SUMMARY_EVERY messages this folds everything up to a watermark into a
# short summary; AssistantReplyService then sends `summary + the tail` instead of the whole thread.
#
# WHY a fast model: the summary is background context, not user-visible prose, so latency and cost
# matter far more than polish.
class AssistantSummaryJob < ApplicationJob
  queue_as :default

  discard_on ActiveRecord::RecordNotFound
  retry_on RubyLLM::Error, wait: :polynomially_longer, attempts: 2

  # WHY: Leave the most recent messages verbatim. The model answers follow-ups like "and the second
  # one?" from exact wording, which a summary would have flattened.
  KEEP_VERBATIM = 10

  def perform(chat_id)
    chat = Chat.find(chat_id)

    messages = chat.visible_messages.order(:id).to_a
    watermark = messages.size - KEEP_VERBATIM

    # WHY: Re-checked here rather than trusting the caller — jobs can be enqueued more than once and
    # run out of order, and re-summarising the same watermark would just burn tokens.
    return if watermark <= chat.summarized_message_count

    to_summarize = messages.first(watermark)
    return if to_summarize.empty?

    summary = generate_summary(to_summarize, previous_summary: chat.summary)
    # WHY: Keep the old summary rather than clobbering it with a blank one if the model misbehaves.
    return if summary.blank?

    chat.update!(summary: summary, summarized_message_count: watermark)
  rescue RubyLLM::Error => e
    Rails.logger.warn("[AssistantSummaryJob] chat ##{chat_id} LLM error: #{e.class}: #{e.message}")
    raise
  rescue StandardError => e
    Rails.logger.error("[AssistantSummaryJob] chat ##{chat_id} failed: #{e.class}: #{e.message}")
    raise
  end

  private

  def generate_summary(messages, previous_summary:)
    transcript = messages.map { |message| "#{message.role}: #{message.content}" }.join("\n\n")
    prompt = AssistantPrompt.summary_prompt(transcript, previous_summary: previous_summary)

    # `assume_model_exists`: see the note in AssistantReplyService#build_llm_chat.
    response = RubyLLM.chat(model: AssistantReplyService::MODEL, provider: AssistantReplyService::PROVIDER,
                            assume_model_exists: true)
                      .ask(prompt)

    response.content.to_s.strip
  end
end
