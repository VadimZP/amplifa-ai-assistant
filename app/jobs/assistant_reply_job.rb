# frozen_string_literal: true

# Generates and streams the assistant's reply to one user prompt.
#
# WHY no retry_on: the user is watching a spinner. A silent retry minutes later would append a reply
# to a conversation they have already given up on, so a failure is surfaced immediately and the user
# retries by resending. AssistantReplyService already returns a Result instead of raising.
class AssistantReplyJob < ApplicationJob
  queue_as :default

  discard_on ActiveRecord::RecordNotFound

  def perform(chat_id, user_message_id = nil)
    chat = Chat.find(chat_id)

    result = AssistantReplyService.call(chat: chat)

    if result.success?
      # WHY: Enqueued only after a successful turn, so a failed reply doesn't fold a half-finished
      # exchange into the summary.
      AssistantSummaryJob.perform_later(chat.id) if chat.reload.summary_due?
    else
      broadcast_error(chat, result.error)
    end
  ensure
    # WHY: Releasing the lock in `ensure` is what stops a crashed job from wedging the chat in a
    # permanently "streaming" state where the composer refuses every new prompt.
    release_lock(chat, user_message_id)
  end

  private

  def release_lock(chat, user_message_id)
    return unless chat

    chat.update_columns(streaming: false, updated_at: Time.current)
  rescue StandardError => e
    Rails.logger.error(
      "[AssistantReplyJob] failed to clear streaming flag on chat ##{chat.id} " \
      "(prompt ##{user_message_id}): #{e.class}: #{e.message}"
    )
  end

  # WHY: A terminal frame is mandatory — without it the browser waits on a stream that will never
  # produce another token.
  def broadcast_error(chat, reason)
    AssistantChatChannel.broadcast_to(chat, { type: 'error', error: reason.to_s })
  rescue StandardError => e
    Rails.logger.error("[AssistantReplyJob] failed to broadcast error for chat ##{chat.id}: #{e.class}: #{e.message}")
  end
end
