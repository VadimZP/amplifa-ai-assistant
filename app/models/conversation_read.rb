# frozen_string_literal: true

# Tracks when a user last read a conversation.
# A conversation is "unread" for a user if:
# - No ConversationRead record exists, OR
# - The conversation's last_reply_at is more recent than last_read_at
class ConversationRead < ApplicationRecord
  belongs_to :conversation
  belongs_to :account

  validates :conversation_id, uniqueness: { scope: :account_id }
  validates :last_read_at, presence: true
end
