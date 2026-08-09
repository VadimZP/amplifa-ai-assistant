# frozen_string_literal: true

# Streams assistant reply tokens for a single chat.
#
# Frames pushed to subscribers (see AssistantReplyService and AssistantReplyJob):
#   { type: 'start',  message_id: }            — the assistant bubble was created
#   { type: 'delta',  message_id:, content: }  — content so far (cumulative, not a diff)
#   { type: 'done',   message_id:, content: }  — final content, stream finished
#   { type: 'error',  error: }                 — terminal failure, UI must clear its spinner
#   { type: 'title',  title: }                 — the generated chat title is ready
class AssistantChatChannel < ApplicationCable::Channel
  def subscribed
    chat = Chat.find_by(id: params[:chat_id])

    # WHY: The connection only proves *who* is asking. Ownership is re-verified here because the
    # chat_id arrives from the client and a subscription outlives the request that created it.
    if chat && authorized?(chat)
      stream_for chat
    else
      reject
    end
  end

  def unsubscribed; end

  private

  # WHY: Mirrors ChatPolicy#show? without Current (a cable connection has no request to set it from):
  # the caller must own the chat AND still have an active membership in that chat's organization.
  def authorized?(chat)
    return false unless current_account
    return false if current_account.amplifa_admin?
    return false unless chat.account_id == current_account.id

    current_account.active_organization_memberships.exists?(organization_id: chat.organization_id)
  end
end
