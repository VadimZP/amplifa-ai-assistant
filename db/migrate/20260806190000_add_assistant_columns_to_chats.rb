# frozen_string_literal: true

# Adds rolling-summary support to assistant chats.
#
# WHY: As a conversation grows, replaying every message to the LLM is expensive and eventually
# exceeds the context window. AssistantSummaryJob compresses everything up to
# `summarized_message_count` into `summary`, and only messages after that watermark are replayed.
class AddAssistantColumnsToChats < ActiveRecord::Migration[8.1]
  def change
    add_column :chats, :summary, :text unless column_exists?(:chats, :summary)

    unless column_exists?(:chats, :summarized_message_count)
      add_column :chats, :summarized_message_count, :integer, default: 0, null: false
    end

    # WHY: The assistant chat list is always scoped to one account within one organization and
    # ordered by recency, so this covers the only query the sidebar makes.
    return if index_exists?(:chats, %i[account_id organization_id last_message_at])

    add_index :chats, %i[account_id organization_id last_message_at],
              name: 'index_chats_on_account_org_and_last_message_at'
  end
end
