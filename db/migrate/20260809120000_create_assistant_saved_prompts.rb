# frozen_string_literal: true

class CreateAssistantSavedPrompts < ActiveRecord::Migration[8.1]
  def change
    create_table :assistant_saved_prompts do |t|
      t.bigint :account_id, null: false
      t.bigint :organization_id, null: false
      t.string :title, null: false
      t.text :prompt, null: false
      t.boolean :welcome_pinned, default: false, null: false
      t.integer :position, default: 0, null: false

      t.timestamps
    end

    add_index :assistant_saved_prompts, :account_id
    add_index :assistant_saved_prompts, :organization_id
    add_index :assistant_saved_prompts,
              %i[account_id organization_id welcome_pinned position],
              name: 'index_assistant_saved_prompts_on_account_org_welcome_position'
  end
end
