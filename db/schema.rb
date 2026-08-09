# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_08_09_120000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "citext"
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_trgm"

  create_table "account_login_change_keys", force: :cascade do |t|
    t.datetime "deadline", null: false
    t.string "key", null: false
    t.string "login", null: false
  end

  create_table "account_password_reset_keys", force: :cascade do |t|
    t.datetime "deadline", null: false
    t.datetime "email_last_sent", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.string "key", null: false
  end

  create_table "account_remember_keys", force: :cascade do |t|
    t.datetime "deadline", null: false
    t.string "key", null: false
  end

  create_table "account_verification_keys", force: :cascade do |t|
    t.datetime "email_last_sent", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.string "key", null: false
    t.datetime "requested_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
  end

  create_table "accounts", force: :cascade do |t|
    t.datetime "created_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.datetime "deactivated_at"
    t.citext "email", null: false
    t.string "first_name"
    t.bigint "impersonating_id"
    t.string "last_name"
    t.string "locale"
    t.bigint "organization_id"
    t.string "password_hash"
    t.jsonb "reply_center_filters", default: {}, null: false
    t.string "role", default: "customer_user", null: false
    t.integer "status", default: 1, null: false
    t.string "timezone"
    t.boolean "two_factor_authentication_required", default: false, null: false
    t.index ["deactivated_at"], name: "index_accounts_on_deactivated_at"
    t.index ["email"], name: "index_accounts_on_email", unique: true, where: "(status = ANY (ARRAY[1, 2]))"
    t.index ["impersonating_id"], name: "index_accounts_on_impersonating_id"
    t.index ["organization_id"], name: "index_accounts_on_organization_id"
    t.index ["role"], name: "index_accounts_on_role"
    t.check_constraint "email ~ '^[^,;@ \r\n]+@[^,@; \r\n]+.[^,@; \r\n]+$'::citext", name: "valid_email"
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "admin_activities", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "action", null: false
    t.datetime "created_at", null: false
    t.jsonb "details", default: {}, null: false
    t.string "ip_address"
    t.bigint "organization_id"
    t.string "user_agent"
    t.index ["account_id"], name: "index_admin_activities_on_account_id"
    t.index ["action"], name: "index_admin_activities_on_action"
    t.index ["created_at"], name: "index_admin_activities_on_created_at"
    t.index ["organization_id"], name: "index_admin_activities_on_organization_id"
  end

  create_table "agent_lead_runs", force: :cascade do |t|
    t.bigint "agent_lead_id", null: false
    t.bigint "assigned_mailbox_id"
    t.datetime "created_at", null: false
    t.datetime "ended_at"
    t.text "restart_reason"
    t.bigint "restarted_by_id"
    t.integer "run_number", null: false
    t.datetime "started_at", null: false
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_lead_id", "run_number"], name: "index_agent_lead_runs_on_agent_lead_id_and_run_number", unique: true
    t.index ["agent_lead_id"], name: "idx_agent_lead_runs_one_active_per_lead", unique: true, where: "((status)::text = 'active'::text)"
    t.index ["agent_lead_id"], name: "index_agent_lead_runs_on_agent_lead_id"
    t.index ["assigned_mailbox_id"], name: "index_agent_lead_runs_on_assigned_mailbox_id"
    t.index ["restarted_by_id"], name: "index_agent_lead_runs_on_restarted_by_id"
  end

  create_table "agent_leads", force: :cascade do |t|
    t.bigint "agent_id", null: false
    t.bigint "assigned_mailbox_id"
    t.datetime "created_at", null: false
    t.bigint "current_agent_lead_run_id"
    t.string "delivery_status", default: "not_contacted", null: false
    t.text "generation_error"
    t.datetime "last_generated_at"
    t.datetime "last_rescheduled_at"
    t.datetime "last_rescheduled_to_at"
    t.datetime "last_sent_at"
    t.bigint "lead_id", null: false
    t.datetime "meeting_booked_at"
    t.text "meeting_notes"
    t.datetime "next_send_at"
    t.datetime "ooo_followup_send_at"
    t.date "ooo_return_date"
    t.boolean "pending_welcome_back", default: false, null: false
    t.integer "reschedule_count", default: 0, null: false
    t.datetime "send_in_progress_at"
    t.integer "sequence_position", default: 0, null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_id", "assigned_mailbox_id", "created_at", "id"], name: "idx_agent_leads_selector_initial", where: "(((delivery_status)::text = ANY (ARRAY[('not_contacted'::character varying)::text, ('in_sequence'::character varying)::text])) AND (sequence_position = 0) AND (last_sent_at IS NULL))", include: ["lead_id", "sequence_position"]
    t.index ["agent_id", "assigned_mailbox_id", "next_send_at", "created_at", "id"], name: "idx_agent_leads_selector_due", where: "(((delivery_status)::text = ANY (ARRAY[('not_contacted'::character varying)::text, ('in_sequence'::character varying)::text])) AND (next_send_at IS NOT NULL))", include: ["lead_id", "sequence_position"]
    t.index ["agent_id", "delivery_status", "created_at"], name: "idx_agent_leads_agent_delivery_created_at"
    t.index ["agent_id", "delivery_status"], name: "index_agent_leads_on_agent_id_and_delivery_status"
    t.index ["agent_id", "lead_id"], name: "idx_agent_leads_unique", unique: true
    t.index ["agent_id", "next_send_at", "send_in_progress_at"], name: "idx_agent_leads_sendable_schedule_lookup", where: "((delivery_status)::text = ANY (ARRAY[('not_contacted'::character varying)::text, ('in_sequence'::character varying)::text]))"
    t.index ["agent_id", "sequence_position"], name: "idx_agent_leads_dashboard_covering"
    t.index ["agent_id", "status"], name: "index_agent_leads_on_agent_id_and_status"
    t.index ["agent_id"], name: "index_agent_leads_on_agent_id"
    t.index ["assigned_mailbox_id"], name: "index_agent_leads_on_assigned_mailbox_id"
    t.index ["created_at"], name: "idx_agent_leads_created_at"
    t.index ["current_agent_lead_run_id"], name: "index_agent_leads_on_current_agent_lead_run_id"
    t.index ["delivery_status"], name: "index_agent_leads_on_delivery_status"
    t.index ["lead_id", "agent_id"], name: "idx_agent_leads_lead_agent"
    t.index ["lead_id"], name: "index_agent_leads_on_lead_id"
    t.index ["next_send_at"], name: "index_agent_leads_on_next_send_at"
    t.index ["send_in_progress_at"], name: "index_agent_leads_on_send_in_progress_at"
    t.index ["sequence_position"], name: "index_agent_leads_on_sequence_position"
    t.index ["status"], name: "index_agent_leads_on_status"
  end

  create_table "agent_mailboxes", force: :cascade do |t|
    t.bigint "agent_id", null: false
    t.datetime "created_at", null: false
    t.bigint "mailbox_id", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_id", "mailbox_id"], name: "index_agent_mailboxes_on_agent_id_and_mailbox_id", unique: true
    t.index ["agent_id"], name: "index_agent_mailboxes_on_agent_id"
    t.index ["mailbox_id"], name: "index_agent_mailboxes_on_mailbox_id"
  end

  create_table "agents", force: :cascade do |t|
    t.boolean "buying_signals_enabled", default: false, null: false
    t.integer "buying_signals_lookback_days", default: 120, null: false
    t.integer "contacted_count", default: 0
    t.datetime "created_at", null: false
    t.bigint "created_by_id", null: false
    t.bigint "current_sample_generation_run_id"
    t.string "default_timezone", default: "Europe/Berlin", null: false
    t.datetime "deleted_at"
    t.text "description"
    t.datetime "full_generation_completed_at"
    t.datetime "full_generation_started_at"
    t.bigint "global_sequence_id"
    t.datetime "launched_at"
    t.string "llm_model", default: "deepseek/deepseek-v4-pro"
    t.string "local_sequence_name"
    t.string "locale", default: "en", null: false
    t.integer "meetings_booked_count", default: 0
    t.string "name", null: false
    t.bigint "organization_id", null: false
    t.datetime "paused_at"
    t.bigint "playbook_id"
    t.integer "replied_count", default: 0
    t.integer "sample_count", default: 50, null: false
    t.datetime "samples_approved_at"
    t.bigint "samples_approved_by_id"
    t.datetime "samples_generated_at"
    t.datetime "scheduled_launch_at"
    t.boolean "send_sequence_messages_from_same_mailbox", default: true, null: false
    t.string "status", default: "draft", null: false
    t.integer "total_leads_count", default: 0
    t.datetime "updated_at", null: false
    t.boolean "use_recipient_locale", default: false, null: false
    t.index ["created_by_id"], name: "index_agents_on_created_by_id"
    t.index ["current_sample_generation_run_id"], name: "index_agents_on_current_sample_generation_run_id"
    t.index ["deleted_at"], name: "index_agents_on_deleted_at"
    t.index ["global_sequence_id"], name: "index_agents_on_global_sequence_id"
    t.index ["launched_at"], name: "index_agents_on_launched_at"
    t.index ["llm_model"], name: "index_agents_on_llm_model"
    t.index ["organization_id", "status"], name: "idx_agents_org_status"
    t.index ["organization_id"], name: "index_agents_on_organization_id"
    t.index ["playbook_id"], name: "index_agents_on_playbook_id"
    t.index ["samples_approved_by_id"], name: "index_agents_on_samples_approved_by_id"
    t.index ["status", "launched_at"], name: "idx_agents_status_launched_at"
    t.index ["status"], name: "index_agents_on_status"
  end

  create_table "app_settings", force: :cascade do |t|
    t.jsonb "billing_plans", default: [], null: false
    t.integer "buying_signals_monthly_price", default: 999, null: false
    t.datetime "created_at", null: false
    t.jsonb "email_discovery_settings", default: {}, null: false
    t.jsonb "email_verification_providers", default: [], null: false
    t.text "global_sequence_preview_model", default: "deepseek/deepseek-v4-pro", null: false
    t.text "linkedin_connection_link", null: false
    t.datetime "updated_at", null: false
    t.boolean "zerobounce_verification_enabled", default: false, null: false
  end

  create_table "assistant_saved_prompts", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.bigint "organization_id", null: false
    t.integer "position", default: 0, null: false
    t.text "prompt", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.boolean "welcome_pinned", default: false, null: false
    t.index ["account_id", "organization_id", "welcome_pinned", "position"], name: "index_assistant_saved_prompts_on_account_org_welcome_position"
    t.index ["account_id"], name: "index_assistant_saved_prompts_on_account_id"
    t.index ["organization_id"], name: "index_assistant_saved_prompts_on_organization_id"
  end

  create_table "blacklists", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "created_by_id", null: false
    t.bigint "organization_id"
    t.text "reason"
    t.string "reason_category", default: "other", null: false
    t.string "source", null: false
    t.datetime "updated_at", null: false
    t.string "value", null: false
    t.string "value_type", null: false
    t.index ["created_by_id"], name: "index_blacklists_on_created_by_id"
    t.index ["organization_id", "value", "value_type"], name: "idx_blacklists_org_value_type", unique: true
    t.index ["organization_id"], name: "idx_blacklists_global", where: "(organization_id IS NULL)"
    t.index ["organization_id"], name: "index_blacklists_on_organization_id"
    t.index ["reason_category"], name: "index_blacklists_on_reason_category"
    t.index ["source"], name: "index_blacklists_on_source"
    t.index ["value", "value_type"], name: "idx_blacklists_value_type"
    t.index ["value_type"], name: "index_blacklists_on_value_type"
  end

  create_table "chats", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.datetime "last_message_at"
    t.bigint "model_id"
    t.bigint "organization_id"
    t.boolean "pinned", default: false, null: false
    t.boolean "streaming", default: false, null: false
    t.integer "summarized_message_count", default: 0, null: false
    t.text "summary"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["account_id", "archived_at"], name: "index_chats_on_account_id_and_archived_at"
    t.index ["account_id", "organization_id", "last_message_at"], name: "index_chats_on_account_org_and_last_message_at"
    t.index ["account_id", "organization_id", "pinned", "last_message_at"], name: "index_chats_on_account_org_pinned_and_last_message_at"
    t.index ["account_id"], name: "index_chats_on_account_id"
    t.index ["last_message_at"], name: "index_chats_on_last_message_at"
    t.index ["model_id"], name: "index_chats_on_model_id"
    t.index ["organization_id"], name: "index_chats_on_organization_id"
  end

  create_table "companies", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "domain"
    t.string "name", null: false
    t.string "normalized_domain"
    t.datetime "updated_at", null: false
    t.string "website_url"
    t.index ["normalized_domain"], name: "index_companies_on_normalized_domain", unique: true
  end

  create_table "conversation_reads", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "conversation_id", null: false
    t.datetime "created_at", null: false
    t.datetime "last_read_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_conversation_reads_on_account_id"
    t.index ["conversation_id", "account_id"], name: "index_conversation_reads_on_conversation_id_and_account_id", unique: true
    t.index ["conversation_id"], name: "index_conversation_reads_on_conversation_id"
  end

  create_table "conversations", force: :cascade do |t|
    t.bigint "agent_id"
    t.bigint "agent_lead_id"
    t.bigint "assigned_to_id"
    t.datetime "auto_forwarded_interested_at"
    t.datetime "created_at", null: false
    t.boolean "has_bounce", default: false, null: false
    t.string "interest_status"
    t.datetime "last_reply_at"
    t.text "last_reply_preview"
    t.datetime "last_sent_reply_at"
    t.boolean "latest_relevant_reply_is_out_of_office", default: false, null: false
    t.bigint "lead_id", null: false
    t.bigint "mailbox_id", null: false
    t.date "ooo_return_date"
    t.bigint "organization_id", null: false
    t.integer "replies_count", default: 0, null: false
    t.datetime "snoozed_until"
    t.string "status", default: "open", null: false
    t.integer "unread_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["agent_id"], name: "index_conversations_on_agent_id"
    t.index ["agent_lead_id"], name: "idx_conversations_unique_agent_lead", unique: true, where: "(agent_lead_id IS NOT NULL)"
    t.index ["assigned_to_id"], name: "index_conversations_on_assigned_to_id"
    t.index ["has_bounce"], name: "idx_conversations_has_bounce_true", where: "(has_bounce = true)"
    t.index ["interest_status"], name: "index_conversations_on_interest_status"
    t.index ["last_sent_reply_at"], name: "idx_conversations_last_sent_reply_at"
    t.index ["latest_relevant_reply_is_out_of_office"], name: "idx_conversations_latest_relevant_ooo_true", where: "(latest_relevant_reply_is_out_of_office = true)"
    t.index ["lead_id", "mailbox_id"], name: "index_conversations_on_lead_id_and_mailbox_id", unique: true
    t.index ["lead_id"], name: "index_conversations_on_lead_id"
    t.index ["mailbox_id"], name: "index_conversations_on_mailbox_id"
    t.index ["organization_id", "status", "last_reply_at"], name: "idx_on_organization_id_status_last_reply_at_a112dde4fd"
    t.index ["organization_id"], name: "index_conversations_on_organization_id"
    t.index ["status"], name: "index_conversations_on_status"
  end

  create_table "email_domains", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "customer_requested", default: false, null: false
    t.string "domain"
    t.string "google_admin_email"
    t.datetime "last_verified_at"
    t.string "microsoft_tenant_id"
    t.bigint "organization_id", null: false
    t.string "provider_type", null: false
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.text "verification_error"
    t.index ["organization_id", "domain"], name: "index_email_domains_on_organization_id_and_domain", unique: true, where: "((status)::text <> 'deleted'::text)"
    t.index ["organization_id"], name: "index_email_domains_on_organization_id"
    t.index ["provider_type"], name: "index_email_domains_on_provider_type"
    t.index ["status"], name: "index_email_domains_on_status"
  end

  create_table "email_two_factor_challenges", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.datetime "last_sent_at", null: false
    t.boolean "remember_login", default: false, null: false
    t.string "return_to"
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.datetime "used_at"
    t.index ["account_id"], name: "index_email_two_factor_challenges_on_account_id"
    t.index ["expires_at"], name: "index_email_two_factor_challenges_on_expires_at"
    t.index ["token_digest"], name: "index_email_two_factor_challenges_on_token_digest", unique: true
  end

  create_table "generated_messages", force: :cascade do |t|
    t.bigint "agent_lead_id", null: false
    t.bigint "agent_lead_run_id"
    t.string "ai_model"
    t.text "body", null: false
    t.text "bounce_reason"
    t.string "bounce_type"
    t.datetime "bounced_at"
    t.datetime "created_at", null: false
    t.integer "generation_time_ms"
    t.integer "input_tokens"
    t.string "instantly_message_id"
    t.text "last_send_error"
    t.bigint "mailbox_id"
    t.boolean "manually_edited", default: false, null: false
    t.string "message_id"
    t.string "message_kind", default: "sequence", null: false
    t.datetime "opened_at"
    t.text "original_body"
    t.string "original_subject"
    t.integer "output_tokens"
    t.datetime "replied_at"
    t.boolean "sample", default: false, null: false
    t.bigint "sample_generation_run_id"
    t.datetime "scheduled_at"
    t.datetime "scheduled_for"
    t.integer "send_attempts", default: 0, null: false
    t.datetime "sent_at"
    t.bigint "sequence_step_id"
    t.string "status", default: "draft", null: false
    t.string "subject"
    t.datetime "test_sent_at"
    t.string "test_sent_to"
    t.datetime "updated_at", null: false
    t.index ["agent_lead_id", "agent_lead_run_id"], name: "idx_generated_messages_sample_current_run", where: "(sample = true)"
    t.index ["agent_lead_id", "sequence_step_id"], name: "idx_gen_msgs_legacy_lead_step_unique", unique: true, where: "((agent_lead_run_id IS NULL) AND ((message_kind)::text = 'sequence'::text) AND (sample = false) AND (sample_generation_run_id IS NULL))"
    t.index ["agent_lead_id"], name: "index_generated_messages_on_agent_lead_id"
    t.index ["agent_lead_run_id", "sequence_step_id"], name: "idx_gen_msgs_run_step_unique", unique: true, where: "((agent_lead_run_id IS NOT NULL) AND ((message_kind)::text = 'sequence'::text))"
    t.index ["agent_lead_run_id"], name: "index_generated_messages_on_agent_lead_run_id"
    t.index ["ai_model"], name: "index_generated_messages_on_ai_model"
    t.index ["bounced_at"], name: "index_generated_messages_on_bounced_at"
    t.index ["instantly_message_id"], name: "index_generated_messages_on_instantly_message_id"
    t.index ["mailbox_id"], name: "index_generated_messages_on_mailbox_id"
    t.index ["message_id"], name: "index_generated_messages_on_message_id"
    t.index ["message_kind"], name: "index_generated_messages_on_message_kind"
    t.index ["sample", "agent_lead_id"], name: "idx_generated_messages_sample_agent_lead"
    t.index ["sample"], name: "index_generated_messages_on_sample"
    t.index ["sample_generation_run_id", "agent_lead_id", "sequence_step_id"], name: "idx_gen_msgs_sample_run_lead_step_unique", unique: true, where: "(sample_generation_run_id IS NOT NULL)"
    t.index ["sample_generation_run_id"], name: "index_generated_messages_on_sample_generation_run_id"
    t.index ["sent_at"], name: "index_generated_messages_on_sent_at"
    t.index ["sequence_step_id"], name: "index_generated_messages_on_sequence_step_id"
    t.index ["status", "sent_at", "agent_lead_id"], name: "idx_generated_messages_dashboard_covering"
    t.index ["status", "sent_at"], name: "idx_generated_messages_status_sent_at"
    t.index ["status"], name: "index_generated_messages_on_status"
    t.index ["test_sent_at"], name: "index_generated_messages_on_test_sent_at"
  end

  create_table "global_sequences", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
  end

  create_table "invitations", force: :cascade do |t|
    t.datetime "accepted_at"
    t.bigint "account_id"
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.datetime "expires_at", null: false
    t.string "first_name", null: false
    t.bigint "invited_by_id", null: false
    t.string "last_name", null: false
    t.bigint "organization_id", null: false
    t.string "role", null: false
    t.datetime "sent_at"
    t.string "status", default: "pending", null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_invitations_on_account_id"
    t.index ["email", "status"], name: "index_invitations_on_email_and_status"
    t.index ["email"], name: "index_invitations_on_email"
    t.index ["invited_by_id"], name: "index_invitations_on_invited_by_id"
    t.index ["organization_id"], name: "index_invitations_on_organization_id"
    t.index ["status"], name: "index_invitations_on_status"
    t.index ["token"], name: "index_invitations_on_token", unique: true
  end

  create_table "lead_import_row_provider_attempts", force: :cascade do |t|
    t.datetime "attempted_at"
    t.decimal "charged_credits", precision: 10, scale: 4, default: "0.0"
    t.datetime "created_at", null: false
    t.text "error"
    t.string "idempotency_key"
    t.string "input_digest", null: false
    t.bigint "lead_import_row_id", null: false
    t.string "provider", null: false
    t.string "request_id"
    t.datetime "reserved_at"
    t.jsonb "result", default: {}
    t.string "state", default: "reserved", null: false
    t.datetime "updated_at", null: false
    t.index ["lead_import_row_id", "provider", "input_digest"], name: "idx_lead_import_row_attempts_unique_input", unique: true
    t.index ["lead_import_row_id"], name: "index_lead_import_row_provider_attempts_on_lead_import_row_id"
    t.index ["reserved_at"], name: "index_lead_import_row_provider_attempts_on_reserved_at"
  end

  create_table "lead_import_rows", force: :cascade do |t|
    t.string "claim_token"
    t.datetime "claimed_at"
    t.string "company_domain"
    t.string "company_name"
    t.string "company_website"
    t.decimal "cost_credits", precision: 10, scale: 4, default: "0.0"
    t.datetime "created_at", null: false
    t.string "discovered_email"
    t.jsonb "email_verdict", default: {}
    t.text "error"
    t.string "first_name"
    t.string "full_name"
    t.string "job_title"
    t.datetime "last_heartbeat_at"
    t.string "last_name"
    t.bigint "lead_import_id", null: false
    t.string "linkedin_url"
    t.string "location"
    t.jsonb "raw_data", default: {}
    t.bigint "resolved_person_id"
    t.string "resolved_provider"
    t.integer "row_index", null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.string "verification_status"
    t.index ["lead_import_id", "row_index"], name: "index_lead_import_rows_on_lead_import_id_and_row_index", unique: true
    t.index ["lead_import_id", "status"], name: "index_lead_import_rows_on_lead_import_id_and_status"
    t.index ["lead_import_id"], name: "index_lead_import_rows_on_lead_import_id"
    t.index ["resolved_person_id"], name: "index_lead_import_rows_on_resolved_person_id"
    t.index ["status", "claimed_at"], name: "index_lead_import_rows_on_status_and_claimed_at"
  end

  create_table "lead_imports", force: :cascade do |t|
    t.bigint "agent_id"
    t.integer "blacklisted_count", default: 0
    t.jsonb "column_mapping", default: {}, null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.integer "created_count", default: 0
    t.datetime "discovery_completed_at"
    t.decimal "discovery_cost_credits", precision: 10, scale: 4, default: "0.0"
    t.integer "discovery_failed", default: 0
    t.integer "discovery_found", default: 0
    t.integer "discovery_not_found", default: 0
    t.datetime "discovery_started_at"
    t.string "discovery_status"
    t.integer "discovery_total", default: 0
    t.integer "error_count", default: 0
    t.jsonb "errors_detail", default: [], null: false
    t.string "external_source_id"
    t.string "external_source_name"
    t.integer "file_size_bytes"
    t.bigint "imported_by_id", null: false
    t.datetime "last_verification_heartbeat_at"
    t.bigint "organization_id", null: false
    t.string "original_filename", null: false
    t.integer "processed_rows", default: 0
    t.boolean "requires_email_discovery", default: false, null: false
    t.integer "skipped_count", default: 0
    t.string "source", default: "csv", null: false
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.integer "total_rows", default: 0
    t.datetime "updated_at", null: false
    t.integer "updated_count", default: 0
    t.datetime "verification_completed_at"
    t.decimal "verification_cost_credits", precision: 10, scale: 4, default: "0.0", null: false
    t.string "verification_mode"
    t.datetime "verification_started_at"
    t.string "verification_status"
    t.datetime "zerobounce_deleted_at"
    t.string "zerobounce_file_id"
    t.index ["agent_id"], name: "index_lead_imports_on_agent_id"
    t.index ["created_at"], name: "idx_lead_imports_created_at"
    t.index ["imported_by_id"], name: "index_lead_imports_on_imported_by_id"
    t.index ["organization_id"], name: "index_lead_imports_on_organization_id"
    t.index ["status"], name: "index_lead_imports_on_status"
  end

  create_table "leads", force: :cascade do |t|
    t.string "blacklist_reason"
    t.string "blacklist_reason_category"
    t.boolean "blacklisted", default: false, null: false
    t.datetime "blacklisted_at"
    t.string "company"
    t.string "company_website"
    t.datetime "created_at", null: false
    t.jsonb "custom_fields", default: {}, null: false
    t.string "email", null: false
    t.string "first_name"
    t.string "full_name"
    t.string "hubspot_contact_id"
    t.string "job_title"
    t.string "last_name"
    t.bigint "lead_import_id"
    t.string "linkedin_url"
    t.string "location"
    t.bigint "organization_id", null: false
    t.date "out_of_office_return_date"
    t.datetime "out_of_office_since"
    t.bigint "person_id"
    t.string "pipedrive_deal_id"
    t.string "pipedrive_organization_id"
    t.string "pipedrive_person_id"
    t.string "salesforce_contact_id"
    t.string "salesforce_opportunity_id"
    t.datetime "updated_at", null: false
    t.index ["blacklist_reason_category"], name: "index_leads_on_blacklist_reason_category"
    t.index ["blacklisted"], name: "idx_leads_blacklisted"
    t.index ["company"], name: "idx_leads_company_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["created_at"], name: "idx_leads_created_at"
    t.index ["custom_fields"], name: "idx_leads_custom_fields_gin", using: :gin
    t.index ["email"], name: "idx_leads_email"
    t.index ["email"], name: "idx_leads_email_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["first_name"], name: "idx_leads_first_name_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["last_name"], name: "idx_leads_last_name_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["lead_import_id"], name: "index_leads_on_lead_import_id"
    t.index ["organization_id", "email"], name: "idx_leads_org_email_unique", unique: true
    t.index ["organization_id", "hubspot_contact_id"], name: "index_leads_on_organization_id_and_hubspot_contact_id", where: "(hubspot_contact_id IS NOT NULL)"
    t.index ["organization_id", "person_id"], name: "idx_leads_org_person_unique", unique: true, where: "(person_id IS NOT NULL)"
    t.index ["organization_id", "pipedrive_deal_id"], name: "index_leads_on_organization_id_and_pipedrive_deal_id", where: "(pipedrive_deal_id IS NOT NULL)"
    t.index ["organization_id", "pipedrive_organization_id"], name: "index_leads_on_organization_id_and_pipedrive_organization_id", where: "(pipedrive_organization_id IS NOT NULL)"
    t.index ["organization_id", "pipedrive_person_id"], name: "index_leads_on_organization_id_and_pipedrive_person_id", where: "(pipedrive_person_id IS NOT NULL)"
    t.index ["organization_id", "salesforce_contact_id"], name: "index_leads_on_organization_id_and_salesforce_contact_id", where: "(salesforce_contact_id IS NOT NULL)"
    t.index ["organization_id", "salesforce_opportunity_id"], name: "index_leads_on_organization_id_and_salesforce_opportunity_id", where: "(salesforce_opportunity_id IS NOT NULL)"
    t.index ["organization_id"], name: "index_leads_on_organization_id"
    t.index ["person_id"], name: "index_leads_on_person_id"
  end

  create_table "mailboxes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "daily_send_limit", default: 50, null: false
    t.string "display_name"
    t.string "email", null: false
    t.bigint "email_domain_id", null: false
    t.string "first_name"
    t.string "last_name"
    t.text "last_poll_error"
    t.datetime "last_polled_at"
    t.datetime "last_sent_at"
    t.datetime "next_available_send_at"
    t.bigint "organization_id", null: false
    t.bigint "sender_id"
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.datetime "warmup_started_at"
    t.index ["email"], name: "index_mailboxes_on_email", unique: true, where: "((status)::text <> 'deleted'::text)"
    t.index ["email_domain_id"], name: "index_mailboxes_on_email_domain_id"
    t.index ["organization_id", "status", "sender_id", "warmup_started_at", "daily_send_limit"], name: "idx_mailboxes_dashboard_capacity"
    t.index ["organization_id", "status"], name: "index_mailboxes_on_organization_id_and_status"
    t.index ["organization_id"], name: "index_mailboxes_on_organization_id"
    t.index ["sender_id"], name: "index_mailboxes_on_sender_id"
    t.index ["status"], name: "index_mailboxes_on_status"
  end

  create_table "mcp_oauth_refresh_tokens", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "aud", null: false
    t.text "client_id", null: false
    t.datetime "consumed_at"
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "jti", null: false
    t.bigint "organization_id"
    t.string "scope", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_mcp_oauth_refresh_tokens_on_account_id"
    t.index ["jti"], name: "index_mcp_oauth_refresh_tokens_on_jti", unique: true
    t.index ["organization_id"], name: "index_mcp_oauth_refresh_tokens_on_organization_id"
  end

  create_table "meeting_declined_comments", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.bigint "meeting_id", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_meeting_declined_comments_on_account_id"
    t.index ["meeting_id"], name: "index_meeting_declined_comments_on_meeting_id"
  end

  create_table "meetings", force: :cascade do |t|
    t.bigint "agent_id", null: false
    t.bigint "agent_lead_id", null: false
    t.bigint "assigned_to_account_id"
    t.string "attributed_via"
    t.string "calendar_event_id"
    t.string "calendly_event_id"
    t.string "calendly_event_uri"
    t.string "calendly_invitee_uri"
    t.datetime "cancelled_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.integer "duration_minutes"
    t.string "invitee_email"
    t.string "invitee_name"
    t.bigint "lead_id", null: false
    t.string "location"
    t.string "meeting_type"
    t.text "notes"
    t.bigint "organization_id", null: false
    t.string "outcome"
    t.text "outcome_notes"
    t.text "removal_comment"
    t.datetime "scheduled_at"
    t.bigint "sender_id"
    t.string "source", default: "manual", null: false
    t.string "status", default: "scheduled", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_id"], name: "index_meetings_on_agent_id"
    t.index ["agent_lead_id"], name: "index_meetings_on_agent_lead_id"
    t.index ["assigned_to_account_id"], name: "index_meetings_on_assigned_to_account_id"
    t.index ["calendar_event_id"], name: "index_meetings_on_calendar_event_id", unique: true, where: "(calendar_event_id IS NOT NULL)"
    t.index ["calendly_event_id"], name: "index_meetings_on_calendly_event_id", unique: true, where: "(calendly_event_id IS NOT NULL)"
    t.index ["calendly_invitee_uri"], name: "index_meetings_on_calendly_invitee_uri_unique", unique: true, where: "(calendly_invitee_uri IS NOT NULL)"
    t.index ["lead_id"], name: "index_meetings_on_lead_id"
    t.index ["meeting_type"], name: "index_meetings_on_meeting_type"
    t.index ["organization_id", "created_at", "status"], name: "idx_meetings_org_created_status"
    t.index ["organization_id"], name: "index_meetings_on_organization_id"
    t.index ["outcome"], name: "index_meetings_on_outcome"
    t.index ["scheduled_at"], name: "index_meetings_on_scheduled_at"
    t.index ["sender_id"], name: "index_meetings_on_sender_id"
    t.index ["source"], name: "index_meetings_on_source"
    t.index ["status"], name: "index_meetings_on_status"
  end

  create_table "messages", force: :cascade do |t|
    t.integer "cache_creation_tokens"
    t.integer "cached_tokens"
    t.bigint "chat_id", null: false
    t.text "content"
    t.json "content_raw"
    t.datetime "created_at", null: false
    t.integer "input_tokens"
    t.bigint "model_id"
    t.integer "output_tokens"
    t.string "role", null: false
    t.bigint "tool_call_id"
    t.datetime "updated_at", null: false
    t.index ["chat_id"], name: "index_messages_on_chat_id"
    t.index ["model_id"], name: "index_messages_on_model_id"
    t.index ["role"], name: "index_messages_on_role"
    t.index ["tool_call_id"], name: "index_messages_on_tool_call_id"
  end

  create_table "models", force: :cascade do |t|
    t.jsonb "capabilities", default: []
    t.integer "context_window"
    t.datetime "created_at", null: false
    t.string "family"
    t.date "knowledge_cutoff"
    t.integer "max_output_tokens"
    t.jsonb "metadata", default: {}
    t.jsonb "modalities", default: {}
    t.datetime "model_created_at"
    t.string "model_id", null: false
    t.string "name", null: false
    t.jsonb "pricing", default: {}
    t.string "provider", null: false
    t.datetime "updated_at", null: false
    t.index ["capabilities"], name: "index_models_on_capabilities", using: :gin
    t.index ["family"], name: "index_models_on_family"
    t.index ["modalities"], name: "index_models_on_modalities", using: :gin
    t.index ["provider", "model_id"], name: "index_models_on_provider_and_model_id", unique: true
    t.index ["provider"], name: "index_models_on_provider"
  end

  create_table "organization_file_playbooks", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "organization_file_id", null: false
    t.bigint "playbook_id", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_file_id", "playbook_id"], name: "idx_organization_file_playbooks_unique", unique: true
    t.index ["organization_file_id"], name: "index_organization_file_playbooks_on_organization_file_id"
    t.index ["playbook_id"], name: "index_organization_file_playbooks_on_playbook_id"
  end

  create_table "organization_files", force: :cascade do |t|
    t.boolean "applies_to_all_playbooks", default: false, null: false
    t.string "category", default: "lead_list", null: false
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "display_name"
    t.text "extracted_text"
    t.text "extraction_error"
    t.string "extraction_status", default: "pending", null: false
    t.bigint "file_size_bytes"
    t.bigint "organization_id", null: false
    t.string "original_filename"
    t.text "source_final_url"
    t.integer "source_http_status"
    t.jsonb "source_metadata", default: {}, null: false
    t.string "source_title"
    t.string "source_type", default: "file", null: false
    t.text "source_url"
    t.text "summary"
    t.datetime "updated_at", null: false
    t.bigint "uploaded_by_id", null: false
    t.index ["created_at"], name: "index_organization_files_on_created_at"
    t.index ["extraction_status"], name: "index_organization_files_on_extraction_status"
    t.index ["organization_id", "category"], name: "index_organization_files_on_organization_id_and_category"
    t.index ["organization_id"], name: "index_organization_files_on_organization_id"
    t.index ["source_type"], name: "index_organization_files_on_source_type"
    t.index ["uploaded_by_id"], name: "index_organization_files_on_uploaded_by_id"
  end

  create_table "organization_memberships", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.datetime "deactivated_at"
    t.bigint "organization_id", null: false
    t.string "role", null: false
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "organization_id"], name: "idx_on_account_id_organization_id_f1a53245e1", unique: true
    t.index ["account_id"], name: "index_organization_memberships_on_account_id"
    t.index ["organization_id", "role"], name: "index_organization_memberships_on_organization_id_and_role"
    t.index ["organization_id"], name: "index_organization_memberships_on_organization_id"
    t.index ["status"], name: "index_organization_memberships_on_status"
  end

  create_table "organizations", force: :cascade do |t|
    t.boolean "ai_reply_agent_enabled", default: false, null: false
    t.datetime "archived_at"
    t.jsonb "auto_forward_interested_agent_comments", default: {}, null: false
    t.text "auto_forward_interested_comment"
    t.string "auto_forward_interested_comment_mode", default: "none", null: false
    t.string "auto_forward_interested_email"
    t.boolean "auto_forward_interested_enabled", default: false, null: false
    t.string "autoreply_prompt_mode", default: "standard", null: false
    t.decimal "average_contract_value", precision: 10, scale: 2
    t.date "billing_cycle_started_on"
    t.string "calendly_url"
    t.boolean "click_tracking_enabled", default: false, null: false
    t.datetime "created_at", null: false
    t.string "currency", default: "EUR", null: false
    t.datetime "deactivated_at"
    t.text "description"
    t.datetime "description_generated_at"
    t.string "industry"
    t.string "locale", default: "en", null: false
    t.decimal "meeting_price", precision: 10, scale: 2
    t.integer "monthly_meeting_limit", default: 5, null: false
    t.decimal "monthly_subscription", precision: 10, scale: 2
    t.string "name", null: false
    t.boolean "onboarded", default: false, null: false
    t.text "ooo_followup_prompt"
    t.string "plan_tier", default: "basic", null: false
    t.string "size"
    t.boolean "slack_notify_on_reply", default: false, null: false
    t.string "slack_webhook_url"
    t.string "status", default: "onboarding", null: false
    t.boolean "two_factor_authentication_required", default: false, null: false
    t.datetime "updated_at", null: false
    t.string "website"
    t.boolean "welcome_back_email_enabled", default: false, null: false
    t.string "welcome_back_prompt_mode", default: "standard", null: false
    t.index ["archived_at"], name: "index_organizations_on_archived_at"
    t.index ["autoreply_prompt_mode"], name: "index_organizations_on_autoreply_prompt_mode"
    t.index ["currency"], name: "index_organizations_on_currency"
    t.index ["deactivated_at"], name: "index_organizations_on_deactivated_at"
    t.index ["locale"], name: "index_organizations_on_locale"
    t.index ["name"], name: "index_organizations_on_name"
    t.index ["plan_tier"], name: "index_organizations_on_plan_tier"
    t.index ["status"], name: "index_organizations_on_status"
    t.index ["welcome_back_prompt_mode"], name: "index_organizations_on_welcome_back_prompt_mode"
  end

  create_table "people", force: :cascade do |t|
    t.string "company"
    t.string "company_website"
    t.text "company_website_scrape_error"
    t.datetime "company_website_scraped_at"
    t.jsonb "company_website_scraped_data", default: {}, null: false
    t.datetime "created_at", null: false
    t.bigint "current_company_id"
    t.string "disc_profile"
    t.datetime "disc_profile_assessed_at"
    t.jsonb "disc_profile_data", default: {}, null: false
    t.string "disc_profile_source"
    t.string "email", null: false
    t.string "email_provider"
    t.datetime "email_provider_detected_at"
    t.string "first_name"
    t.string "full_name"
    t.string "job_title"
    t.string "last_name"
    t.string "linkedin_handle"
    t.text "linkedin_posts_scrape_error"
    t.datetime "linkedin_posts_scraped_at"
    t.jsonb "linkedin_posts_scraped_data", default: {}, null: false
    t.datetime "linkedin_profile_photo_downloaded_at"
    t.text "linkedin_profile_photo_error"
    t.text "linkedin_scrape_error"
    t.datetime "linkedin_scraped_at"
    t.jsonb "linkedin_scraped_data", default: {}, null: false
    t.string "linkedin_url"
    t.string "locale_source"
    t.string "location"
    t.string "normalized_company_domain"
    t.string "preferred_locale"
    t.string "timezone"
    t.datetime "timezone_resolved_at"
    t.string "timezone_source"
    t.datetime "updated_at", null: false
    t.index "lower((email)::text)", name: "index_people_on_email_unique", unique: true
    t.index ["current_company_id"], name: "index_people_on_current_company_id"
    t.index ["linkedin_handle"], name: "index_people_on_linkedin_handle"
    t.index ["linkedin_url"], name: "index_people_on_linkedin_url_unique", unique: true, where: "(linkedin_url IS NOT NULL)"
    t.index ["normalized_company_domain"], name: "index_people_on_normalized_company_domain"
    t.index ["timezone"], name: "index_people_on_timezone_present", where: "(timezone IS NOT NULL)"
  end

  create_table "person_email_aliases", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.bigint "person_id", null: false
    t.datetime "updated_at", null: false
    t.index "lower((email)::text)", name: "index_person_email_aliases_on_email_unique", unique: true
    t.index ["person_id"], name: "index_person_email_aliases_on_person_id"
  end

  create_table "playbook_attachment_playbooks", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "playbook_attachment_id", null: false
    t.bigint "playbook_id", null: false
    t.datetime "updated_at", null: false
    t.index ["playbook_attachment_id", "playbook_id"], name: "idx_playbook_attachment_playbooks_unique", unique: true
    t.index ["playbook_attachment_id"], name: "index_playbook_attachment_playbooks_on_playbook_attachment_id"
    t.index ["playbook_id"], name: "index_playbook_attachment_playbooks_on_playbook_id"
  end

  create_table "playbook_attachments", force: :cascade do |t|
    t.boolean "applies_to_all_playbooks", default: false, null: false
    t.string "attachable_id", null: false
    t.string "attachable_type", null: false
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "display_name"
    t.text "extracted_text"
    t.text "extraction_error"
    t.string "extraction_status", default: "pending", null: false
    t.bigint "file_size_bytes"
    t.bigint "organization_id", null: false
    t.string "original_filename"
    t.bigint "playbook_id"
    t.text "source_final_url"
    t.integer "source_http_status"
    t.jsonb "source_metadata", default: {}, null: false
    t.string "source_title"
    t.string "source_type", default: "file", null: false
    t.text "source_url"
    t.text "summary"
    t.datetime "updated_at", null: false
    t.bigint "uploaded_by_id"
    t.index ["organization_id"], name: "index_playbook_attachments_on_organization_id"
    t.index ["playbook_id", "attachable_type", "attachable_id"], name: "index_playbook_attachments_on_playbook_and_attachable", unique: true
    t.index ["playbook_id"], name: "index_playbook_attachments_on_playbook_id"
    t.index ["source_type"], name: "index_playbook_attachments_on_source_type"
    t.index ["uploaded_by_id"], name: "index_playbook_attachments_on_uploaded_by_id"
  end

  create_table "playbook_comments", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.boolean "ai_applied", default: false, null: false
    t.text "body", null: false
    t.string "comment_type", default: "general", null: false
    t.datetime "created_at", null: false
    t.jsonb "feedback_context", default: {}, null: false
    t.bigint "playbook_id", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_playbook_comments_on_account_id"
    t.index ["comment_type"], name: "index_playbook_comments_on_comment_type"
    t.index ["playbook_id", "created_at"], name: "index_playbook_comments_on_playbook_id_and_created_at"
    t.index ["playbook_id"], name: "index_playbook_comments_on_playbook_id"
  end

  create_table "playbooks", force: :cascade do |t|
    t.text "ai_generation_notes"
    t.datetime "approved_at"
    t.bigint "approved_by_id"
    t.datetime "created_at", null: false
    t.string "language", default: "en", null: false
    t.bigint "organization_id", null: false
    t.jsonb "personae", default: [], null: false
    t.jsonb "product", default: {}, null: false
    t.jsonb "proof_points", default: [], null: false
    t.jsonb "redo_version_snapshots", default: [], null: false
    t.jsonb "references", default: [], null: false
    t.string "status", default: "draft", null: false
    t.datetime "updated_at", null: false
    t.jsonb "use_cases", default: [], null: false
    t.text "value_proposition"
    t.bigint "version_cursor_id"
    t.index ["approved_by_id"], name: "index_playbooks_on_approved_by_id"
    t.index ["language"], name: "index_playbooks_on_language"
    t.index ["organization_id", "status"], name: "index_playbooks_on_organization_id_and_status"
    t.index ["organization_id"], name: "index_playbooks_on_organization_id"
    t.index ["status"], name: "index_playbooks_on_status"
  end

  create_table "replies", force: :cascade do |t|
    t.string "api_message_id", null: false
    t.string "assignment_reason"
    t.text "body_html"
    t.text "body_plain"
    t.string "bounce_type"
    t.jsonb "calendar_event_data", default: {}, null: false
    t.text "cc_addresses", default: [], null: false, array: true
    t.bigint "conversation_id"
    t.datetime "created_at", null: false
    t.string "from_address", null: false
    t.bigint "generated_message_id"
    t.text "in_reply_to"
    t.boolean "is_bounce", default: false, null: false
    t.boolean "is_out_of_office", default: false, null: false
    t.boolean "is_warmup", default: false, null: false
    t.bigint "lead_id"
    t.bigint "mailbox_id", null: false
    t.string "match_confidence"
    t.string "match_source"
    t.string "matched_message_id"
    t.string "message_id"
    t.boolean "needs_lead_assignment", default: false, null: false
    t.date "out_of_office_return_date"
    t.datetime "read_at"
    t.datetime "received_at", null: false
    t.text "references"
    t.boolean "requires_response", default: true, null: false
    t.boolean "responded", default: false, null: false
    t.datetime "responded_at"
    t.boolean "sender_mismatch_on_match", default: false, null: false
    t.string "subject"
    t.text "to_addresses", default: [], null: false, array: true
    t.datetime "updated_at", null: false
    t.string "warmup_service"
    t.index ["api_message_id"], name: "index_replies_on_api_message_id", unique: true
    t.index ["conversation_id", "out_of_office_return_date"], name: "idx_replies_ooo_conversation_return_date", where: "(is_out_of_office = true)"
    t.index ["conversation_id", "received_at"], name: "idx_replies_latest_relevant_by_conversation", order: { received_at: :desc }, where: "((is_bounce = false) AND (is_warmup = false))"
    t.index ["conversation_id", "received_at"], name: "index_replies_on_conversation_id_and_received_at"
    t.index ["conversation_id"], name: "idx_replies_bounce_conversation", where: "(is_bounce = true)"
    t.index ["conversation_id"], name: "index_replies_on_conversation_id"
    t.index ["generated_message_id"], name: "index_replies_on_generated_message_id"
    t.index ["is_bounce"], name: "index_replies_on_is_bounce"
    t.index ["is_out_of_office"], name: "index_replies_on_is_out_of_office"
    t.index ["is_warmup"], name: "index_replies_on_is_warmup"
    t.index ["lead_id"], name: "index_replies_on_lead_id"
    t.index ["mailbox_id", "received_at"], name: "index_replies_on_mailbox_id_and_received_at"
    t.index ["mailbox_id"], name: "index_replies_on_mailbox_id"
    t.index ["match_confidence"], name: "index_replies_on_match_confidence"
    t.index ["match_source"], name: "index_replies_on_match_source"
    t.index ["needs_lead_assignment"], name: "index_replies_on_needs_lead_assignment", where: "(needs_lead_assignment = true)"
    t.index ["responded", "requires_response"], name: "index_replies_on_responded_and_requires_response"
  end

  create_table "reply_attachments", force: :cascade do |t|
    t.string "content_id"
    t.string "content_type", null: false
    t.datetime "created_at", null: false
    t.bigint "file_size_bytes", null: false
    t.string "original_filename", null: false
    t.bigint "reply_id", null: false
    t.datetime "updated_at", null: false
    t.index ["reply_id", "content_id"], name: "index_reply_attachments_on_reply_id_and_content_id"
    t.index ["reply_id"], name: "index_reply_attachments_on_reply_id"
  end

  create_table "sample_generation_runs", force: :cascade do |t|
    t.bigint "agent_id", null: false
    t.datetime "created_at", null: false
    t.datetime "ended_at"
    t.bigint "initiated_by_id"
    t.integer "run_number", null: false
    t.bigint "sample_agent_lead_ids", default: [], null: false, array: true
    t.datetime "started_at", null: false
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_id", "run_number"], name: "index_sample_generation_runs_on_agent_id_and_run_number", unique: true
    t.index ["agent_id"], name: "idx_sample_generation_runs_one_active_per_agent", unique: true, where: "((status)::text = 'active'::text)"
    t.index ["agent_id"], name: "index_sample_generation_runs_on_agent_id"
    t.index ["initiated_by_id"], name: "index_sample_generation_runs_on_initiated_by_id"
  end

  create_table "senders", force: :cascade do |t|
    t.text "calendly_access_token"
    t.datetime "calendly_connected_at"
    t.text "calendly_connection_error"
    t.string "calendly_connection_status", default: "disconnected", null: false
    t.string "calendly_organization_uri"
    t.text "calendly_refresh_token"
    t.string "calendly_selected_event_type_name"
    t.string "calendly_selected_event_type_uri"
    t.datetime "calendly_token_expires_at"
    t.string "calendly_url"
    t.string "calendly_user_uri"
    t.text "calendly_webhook_signing_key"
    t.string "calendly_webhook_uri"
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "first_name", null: false
    t.string "job_title"
    t.string "last_name", null: false
    t.string "linkedin_url"
    t.string "nickname"
    t.bigint "organization_id", null: false
    t.integer "send_window_end_hour", default: 18, null: false
    t.integer "send_window_end_minute", default: 0, null: false
    t.integer "send_window_start_hour", default: 8, null: false
    t.integer "send_window_start_minute", default: 0, null: false
    t.text "signature_template"
    t.string "status", default: "active", null: false
    t.string "timezone", default: "Europe/Berlin", null: false
    t.datetime "updated_at", null: false
    t.index ["calendly_selected_event_type_uri"], name: "index_senders_on_calendly_selected_event_type_uri", where: "(calendly_selected_event_type_uri IS NOT NULL)"
    t.index ["calendly_user_uri"], name: "index_senders_on_calendly_user_uri", where: "(calendly_user_uri IS NOT NULL)"
    t.index ["organization_id", "email"], name: "index_senders_on_organization_id_and_email", unique: true
    t.index ["organization_id"], name: "index_senders_on_organization_id"
    t.index ["status"], name: "index_senders_on_status"
  end

  create_table "sent_replies", force: :cascade do |t|
    t.string "api_message_id"
    t.text "body_html"
    t.text "body_plain", null: false
    t.text "cc_addresses", default: [], null: false, array: true
    t.bigint "conversation_id", null: false
    t.datetime "created_at", null: false
    t.boolean "include_signature", default: false, null: false
    t.bigint "mailbox_id", null: false
    t.string "message_id"
    t.bigint "reply_id"
    t.text "send_error"
    t.datetime "sent_at"
    t.bigint "sent_by_id", null: false
    t.string "status", default: "draft", null: false
    t.string "subject", null: false
    t.string "to_address", null: false
    t.datetime "updated_at", null: false
    t.index ["conversation_id", "created_at"], name: "index_sent_replies_on_conversation_id_and_created_at"
    t.index ["conversation_id"], name: "index_sent_replies_on_conversation_id"
    t.index ["mailbox_id"], name: "index_sent_replies_on_mailbox_id"
    t.index ["message_id"], name: "index_sent_replies_on_message_id"
    t.index ["reply_id"], name: "index_sent_replies_on_reply_id"
    t.index ["sent_by_id"], name: "index_sent_replies_on_sent_by_id"
    t.index ["status"], name: "index_sent_replies_on_status"
  end

  create_table "sent_reply_attachments", force: :cascade do |t|
    t.string "content_type", null: false
    t.datetime "created_at", null: false
    t.bigint "file_size_bytes", null: false
    t.string "original_filename", null: false
    t.bigint "sent_reply_id", null: false
    t.datetime "updated_at", null: false
    t.index ["sent_reply_id"], name: "index_sent_reply_attachments_on_sent_reply_id"
  end

  create_table "sequence_steps", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.bigint "agent_id"
    t.boolean "archived", default: false, null: false
    t.datetime "created_at", null: false
    t.integer "delay_days", default: 0, null: false
    t.jsonb "event_config", default: {}, null: false
    t.string "event_type", default: "email", null: false
    t.bigint "global_sequence_id"
    t.string "name"
    t.integer "position", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_sequence_steps_on_active"
    t.index ["agent_id", "position"], name: "idx_sequence_steps_active_email_agent_position", where: "((active = true) AND (archived = false) AND ((event_type)::text = 'email'::text) AND (agent_id IS NOT NULL))"
    t.index ["agent_id", "position"], name: "index_sequence_steps_on_agent_id_and_position", unique: true
    t.index ["agent_id"], name: "index_sequence_steps_on_agent_id"
    t.index ["archived"], name: "index_sequence_steps_on_archived"
    t.index ["event_type"], name: "index_sequence_steps_on_event_type"
    t.index ["global_sequence_id", "position"], name: "idx_sequence_steps_active_email_global_position", where: "((active = true) AND (archived = false) AND ((event_type)::text = 'email'::text) AND (global_sequence_id IS NOT NULL))"
    t.index ["global_sequence_id", "position"], name: "index_sequence_steps_on_global_sequence_id_and_position", unique: true, where: "(global_sequence_id IS NOT NULL)"
    t.index ["global_sequence_id"], name: "index_sequence_steps_on_global_sequence_id"
  end

  create_table "tool_calls", force: :cascade do |t|
    t.jsonb "arguments", default: {}
    t.datetime "created_at", null: false
    t.bigint "message_id", null: false
    t.string "name", null: false
    t.jsonb "result"
    t.string "tool_call_id", null: false
    t.datetime "updated_at", null: false
    t.index ["message_id"], name: "index_tool_calls_on_message_id"
    t.index ["name"], name: "index_tool_calls_on_name"
    t.index ["tool_call_id"], name: "index_tool_calls_on_tool_call_id", unique: true
  end

  create_table "versions", force: :cascade do |t|
    t.datetime "created_at"
    t.string "event", null: false
    t.bigint "item_id", null: false
    t.string "item_type", null: false
    t.text "object"
    t.string "whodunnit"
    t.index ["item_type", "item_id"], name: "index_versions_on_item_type_and_item_id"
  end

  add_foreign_key "account_login_change_keys", "accounts", column: "id"
  add_foreign_key "account_password_reset_keys", "accounts", column: "id"
  add_foreign_key "account_remember_keys", "accounts", column: "id"
  add_foreign_key "account_verification_keys", "accounts", column: "id"
  add_foreign_key "accounts", "accounts", column: "impersonating_id"
  add_foreign_key "accounts", "organizations"
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "admin_activities", "accounts"
  add_foreign_key "admin_activities", "organizations"
  add_foreign_key "agent_lead_runs", "accounts", column: "restarted_by_id"
  add_foreign_key "agent_lead_runs", "agent_leads"
  add_foreign_key "agent_lead_runs", "mailboxes", column: "assigned_mailbox_id"
  add_foreign_key "agent_leads", "agent_lead_runs", column: "current_agent_lead_run_id", validate: false
  add_foreign_key "agent_leads", "agents"
  add_foreign_key "agent_leads", "leads"
  add_foreign_key "agent_leads", "mailboxes", column: "assigned_mailbox_id"
  add_foreign_key "agent_mailboxes", "agents"
  add_foreign_key "agent_mailboxes", "mailboxes"
  add_foreign_key "agents", "accounts", column: "created_by_id"
  add_foreign_key "agents", "accounts", column: "samples_approved_by_id"
  add_foreign_key "agents", "global_sequences"
  add_foreign_key "agents", "organizations"
  add_foreign_key "agents", "playbooks"
  add_foreign_key "agents", "sample_generation_runs", column: "current_sample_generation_run_id", validate: false
  add_foreign_key "blacklists", "accounts", column: "created_by_id"
  add_foreign_key "blacklists", "organizations"
  add_foreign_key "chats", "accounts"
  add_foreign_key "chats", "models"
  add_foreign_key "chats", "organizations"
  add_foreign_key "conversation_reads", "accounts"
  add_foreign_key "conversation_reads", "conversations"
  add_foreign_key "conversations", "accounts", column: "assigned_to_id"
  add_foreign_key "conversations", "agent_leads"
  add_foreign_key "conversations", "agents"
  add_foreign_key "conversations", "leads"
  add_foreign_key "conversations", "mailboxes"
  add_foreign_key "conversations", "organizations"
  add_foreign_key "email_domains", "organizations"
  add_foreign_key "email_two_factor_challenges", "accounts"
  add_foreign_key "generated_messages", "agent_lead_runs", validate: false
  add_foreign_key "generated_messages", "agent_leads"
  add_foreign_key "generated_messages", "mailboxes"
  add_foreign_key "generated_messages", "sample_generation_runs", validate: false
  add_foreign_key "generated_messages", "sequence_steps"
  add_foreign_key "invitations", "accounts"
  add_foreign_key "invitations", "accounts", column: "invited_by_id"
  add_foreign_key "invitations", "organizations"
  add_foreign_key "lead_import_row_provider_attempts", "lead_import_rows"
  add_foreign_key "lead_import_rows", "lead_imports"
  add_foreign_key "lead_imports", "accounts", column: "imported_by_id"
  add_foreign_key "lead_imports", "agents"
  add_foreign_key "lead_imports", "organizations"
  add_foreign_key "leads", "lead_imports"
  add_foreign_key "leads", "organizations"
  add_foreign_key "leads", "people"
  add_foreign_key "mailboxes", "email_domains"
  add_foreign_key "mailboxes", "organizations"
  add_foreign_key "mailboxes", "senders"
  add_foreign_key "mcp_oauth_refresh_tokens", "accounts"
  add_foreign_key "mcp_oauth_refresh_tokens", "organizations"
  add_foreign_key "meeting_declined_comments", "accounts"
  add_foreign_key "meeting_declined_comments", "meetings"
  add_foreign_key "meetings", "accounts", column: "assigned_to_account_id"
  add_foreign_key "meetings", "agent_leads"
  add_foreign_key "meetings", "agents"
  add_foreign_key "meetings", "leads"
  add_foreign_key "meetings", "organizations"
  add_foreign_key "meetings", "senders"
  add_foreign_key "messages", "chats"
  add_foreign_key "messages", "models"
  add_foreign_key "messages", "tool_calls"
  add_foreign_key "organization_file_playbooks", "organization_files"
  add_foreign_key "organization_file_playbooks", "playbooks"
  add_foreign_key "organization_files", "accounts", column: "uploaded_by_id"
  add_foreign_key "organization_files", "organizations"
  add_foreign_key "organization_memberships", "accounts"
  add_foreign_key "organization_memberships", "organizations"
  add_foreign_key "people", "companies", column: "current_company_id"
  add_foreign_key "person_email_aliases", "people"
  add_foreign_key "playbook_attachment_playbooks", "playbook_attachments"
  add_foreign_key "playbook_attachment_playbooks", "playbooks"
  add_foreign_key "playbook_attachments", "accounts", column: "uploaded_by_id"
  add_foreign_key "playbook_attachments", "organizations"
  add_foreign_key "playbook_attachments", "playbooks"
  add_foreign_key "playbook_comments", "accounts"
  add_foreign_key "playbook_comments", "playbooks"
  add_foreign_key "playbooks", "accounts", column: "approved_by_id"
  add_foreign_key "playbooks", "organizations"
  add_foreign_key "replies", "conversations"
  add_foreign_key "replies", "generated_messages"
  add_foreign_key "replies", "leads"
  add_foreign_key "replies", "mailboxes"
  add_foreign_key "reply_attachments", "replies"
  add_foreign_key "sample_generation_runs", "accounts", column: "initiated_by_id"
  add_foreign_key "sample_generation_runs", "agents"
  add_foreign_key "senders", "organizations"
  add_foreign_key "sent_replies", "accounts", column: "sent_by_id"
  add_foreign_key "sent_replies", "conversations"
  add_foreign_key "sent_replies", "mailboxes"
  add_foreign_key "sent_replies", "replies"
  add_foreign_key "sent_reply_attachments", "sent_replies"
  add_foreign_key "sequence_steps", "agents"
  add_foreign_key "sequence_steps", "global_sequences"
  add_foreign_key "tool_calls", "messages"
end
