# frozen_string_literal: true

class AddPinnedToChats < ActiveRecord::Migration[8.1]
  def change
    add_column :chats, :pinned, :boolean, default: false, null: false
    add_index :chats, %i[account_id organization_id pinned last_message_at],
              name: 'index_chats_on_account_org_pinned_and_last_message_at'
  end
end
