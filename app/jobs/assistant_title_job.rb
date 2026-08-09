# frozen_string_literal: true

# Names a chat after its first prompt, so the sidebar reads like a list of topics instead of
# "New chat, New chat, New chat".
#
# WHY it runs in the background: titling costs an LLM round-trip, and the user should not wait on it
# to see their prompt appear. The title arrives over the cable a moment later.
class AssistantTitleJob < ApplicationJob
  queue_as :default

  discard_on ActiveRecord::RecordNotFound
  retry_on RubyLLM::Error, wait: :polynomially_longer, attempts: 2

  def perform(chat_id)
    chat = Chat.find(chat_id)

    # WHY: Enqueued on the first prompt, but the user may have renamed nothing and a retry may run
    # after a previous attempt succeeded — never overwrite an existing title.
    return if chat.title.present?

    prompt = chat.visible_messages.where(role: 'user').order(:id).first
    return if prompt.nil? || prompt.content.blank?

    title = generate_title(prompt.content)
    # WHY: Fall back to a truncated prompt rather than leaving the chat unnamed if the model returns
    # something unusable — an untitled chat is harder to find than an imperfectly titled one.
    title = fallback_title(prompt.content) if title.blank?

    chat.update!(title: title)
    broadcast_title(chat, title)
  rescue RubyLLM::Error => e
    Rails.logger.warn("[AssistantTitleJob] chat ##{chat_id} LLM error: #{e.class}: #{e.message}")
    raise
  rescue StandardError => e
    Rails.logger.error("[AssistantTitleJob] chat ##{chat_id} failed: #{e.class}: #{e.message}")
    raise
  end

  private

  def generate_title(prompt)
    # `assume_model_exists`: see the note in AssistantReplyService#build_llm_chat.
    response = RubyLLM.chat(model: AssistantReplyService::MODEL, provider: AssistantReplyService::PROVIDER,
                            assume_model_exists: true)
                      .ask(AssistantPrompt.title_prompt(prompt))

    sanitize(response.content.to_s)
  end

  def sanitize(title)
    # WHY: Small models like to wrap titles in quotes, prefix them with "Title:" or add a trailing
    # period. Strip that so the sidebar stays clean.
    title.strip
         .lines.first.to_s.strip
         .sub(/\A(title|titre|título|titel)\s*:\s*/i, '')
         .delete('"')
         .delete("'")
         .sub(/[.:;,]+\z/, '')
         .truncate(Chat::TITLE_MAX_LENGTH, omission: '…')
  end

  def fallback_title(prompt)
    prompt.to_s.squish.truncate(Chat::TITLE_MAX_LENGTH, omission: '…')
  end

  def broadcast_title(chat, title)
    AssistantChatChannel.broadcast_to(chat, { type: 'title', title: title })
  rescue StandardError => e
    # WHY: The title is persisted, so a dropped broadcast only means the sidebar updates on the next
    # navigation. Not worth failing the job.
    Rails.logger.warn("[AssistantTitleJob] broadcast failed for chat ##{chat.id}: #{e.class}: #{e.message}")
  end
end
