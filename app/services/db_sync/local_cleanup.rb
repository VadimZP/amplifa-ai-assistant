# frozen_string_literal: true

module DbSync
  class LocalCleanup
    def initialize(local_conn:, delete_row:)
      @local_conn = local_conn
      @delete_row = delete_row
    end

    def call(org_name:)
      local_org = local_conn.select_one(
        "SELECT id FROM organizations WHERE name = #{local_conn.quote(org_name)} LIMIT 1"
      )
      return false if local_org.blank?

      local_org_id_sql = local_conn.quote(local_org['id'])
      dev_account_ids = local_conn.select_values("SELECT id FROM accounts WHERE organization_id = #{local_org_id_sql}").map(&:to_i)
      dev_account_ids_sql = in_list_sql(dev_account_ids)
      agent_scope_sql = or_conditions_sql([
                                            "organization_id = #{local_org_id_sql}",
                                            ("created_by_id IN #{dev_account_ids_sql}" if dev_account_ids_sql.present?),
                                            (if dev_account_ids_sql.present?
                                               "samples_approved_by_id IN #{dev_account_ids_sql}"
                                             end)
                                          ])
      dev_agent_ids = if agent_scope_sql.present?
                        local_conn.select_values("SELECT id FROM agents WHERE #{agent_scope_sql}").map(&:to_i)
                      else
                        []
                      end
      dev_agent_ids_sql = in_list_sql(dev_agent_ids)
      dev_lead_ids = local_conn.select_values("SELECT id FROM leads WHERE organization_id = #{local_org_id_sql}").map(&:to_i)
      dev_lead_ids_sql = in_list_sql(dev_lead_ids)
      dev_mailbox_ids = local_conn.select_values("SELECT id FROM mailboxes WHERE organization_id = #{local_org_id_sql}").map(&:to_i)
      dev_mailbox_ids_sql = in_list_sql(dev_mailbox_ids)
      local_org_website_scrape_ids = local_conn.select_values(
        "SELECT website_scrape_id FROM organizations WHERE id = #{local_org_id_sql} AND website_scrape_id IS NOT NULL"
      ).map(&:to_i)
      local_org_website_scrape_ids_sql = in_list_sql(local_org_website_scrape_ids, quote: false)

      agent_lead_scope_sql = or_conditions_sql([
                                                 ("agent_id IN #{dev_agent_ids_sql}" if dev_agent_ids_sql.present?),
                                                 ("lead_id IN #{dev_lead_ids_sql}" if dev_lead_ids_sql.present?),
                                                 (if dev_mailbox_ids_sql.present?
                                                    "assigned_mailbox_id IN #{dev_mailbox_ids_sql}"
                                                  end)
                                               ])
      dev_agent_lead_ids = if agent_lead_scope_sql.present?
                              local_conn.select_values("SELECT id FROM agent_leads WHERE #{agent_lead_scope_sql}").map(&:to_i)
                           else
                              []
                           end
      dev_agent_lead_ids_sql = in_list_sql(dev_agent_lead_ids)
      agent_lead_run_scope_sql = or_conditions_sql([
                                                     (if dev_agent_lead_ids_sql.present?
                                                        "agent_lead_id IN #{dev_agent_lead_ids_sql}"
                                                      end),
                                                     (if dev_mailbox_ids_sql.present?
                                                        "assigned_mailbox_id IN #{dev_mailbox_ids_sql}"
                                                      end),
                                                     (if dev_account_ids_sql.present?
                                                        "restarted_by_id IN #{dev_account_ids_sql}"
                                                      end)
                                                   ])
      dev_agent_lead_run_ids = if agent_lead_run_scope_sql.present?
                                 local_conn.select_values("SELECT id FROM agent_lead_runs WHERE #{agent_lead_run_scope_sql}").map(&:to_i)
                               else
                                 []
                               end
      dev_agent_lead_run_ids_sql = in_list_sql(dev_agent_lead_run_ids)
      dev_conversation_scope_sql = or_conditions_sql([
                                                        "organization_id = #{local_org_id_sql}",
                                                       ("lead_id IN #{dev_lead_ids_sql}" if dev_lead_ids_sql.present?),
                                                       (if dev_agent_ids_sql.present?
                                                          "agent_id IN #{dev_agent_ids_sql}"
                                                        end),
                                                       (if dev_mailbox_ids_sql.present?
                                                          "mailbox_id IN #{dev_mailbox_ids_sql}"
                                                        end),
                                                       (if dev_account_ids_sql.present?
                                                          "assigned_to_id IN #{dev_account_ids_sql}"
                                                        end)
                                                     ])
      dev_conversation_ids = if dev_conversation_scope_sql.present?
                               local_conn.select_values("SELECT id FROM conversations WHERE #{dev_conversation_scope_sql}").map(&:to_i)
                             else
                               []
                             end
      dev_conversation_ids_sql = in_list_sql(dev_conversation_ids)
      dev_playbook_ids = local_conn.select_values("SELECT id FROM playbooks WHERE organization_id = #{local_org_id_sql}").map(&:to_i)
      dev_playbook_ids_sql = in_list_sql(dev_playbook_ids)

      invitation_scope_sql = or_conditions_sql([
                                                 "organization_id = #{local_org_id_sql}",
                                                 (if dev_account_ids_sql.present?
                                                    "account_id IN #{dev_account_ids_sql}"
                                                  end),
                                                 (if dev_account_ids_sql.present?
                                                    "invited_by_id IN #{dev_account_ids_sql}"
                                                  end)
                                               ])
      reply_scope_sql = or_conditions_sql([
                                            (if dev_conversation_ids_sql.present?
                                               "conversation_id IN #{dev_conversation_ids_sql}"
                                             end),
                                            ("lead_id IN #{dev_lead_ids_sql}" if dev_lead_ids_sql.present?),
                                            ("mailbox_id IN #{dev_mailbox_ids_sql}" if dev_mailbox_ids_sql.present?)
                                          ])
      meeting_scope_sql = or_conditions_sql([
                                              "organization_id = #{local_org_id_sql}",
                                              ("agent_id IN #{dev_agent_ids_sql}" if dev_agent_ids_sql.present?),
                                              ("lead_id IN #{dev_lead_ids_sql}" if dev_lead_ids_sql.present?),
                                              (if dev_agent_lead_ids_sql.present?
                                                 "agent_lead_id IN #{dev_agent_lead_ids_sql}"
                                               end)
                                            ])
      click_event_scope_sql = or_conditions_sql([
                                                  "organization_id = #{local_org_id_sql}",
                                                  ("lead_id IN #{dev_lead_ids_sql}" if dev_lead_ids_sql.present?),
                                                  (if dev_agent_lead_ids_sql.present?
                                                     "agent_lead_id IN #{dev_agent_lead_ids_sql}"
                                                   end)
                                                ])
      out_of_office_period_scope_sql = or_conditions_sql([
                                                           "organization_id = #{local_org_id_sql}",
                                                           (if dev_lead_ids_sql.present?
                                                              "lead_id IN #{dev_lead_ids_sql}"
                                                            end),
                                                           (if dev_agent_lead_ids_sql.present?
                                                              "welcome_back_agent_lead_id IN #{dev_agent_lead_ids_sql}"
                                                            end)
                                                         ])

      if click_event_scope_sql.present?
        delete_row.call('click_events',
                        "DELETE FROM click_events WHERE #{click_event_scope_sql}")
      end
      if dev_agent_lead_ids_sql.present?
        delete_row.call('click_tracking_links',
                        "DELETE FROM click_tracking_links WHERE agent_lead_id IN #{dev_agent_lead_ids_sql}")
      end
      if out_of_office_period_scope_sql.present?
        delete_row.call('out_of_office_periods',
                        "DELETE FROM out_of_office_periods WHERE #{out_of_office_period_scope_sql}")
      end
      if dev_conversation_ids_sql.present?
        delete_row.call('active_storage_attachments', <<~SQL.squish)
          DELETE FROM active_storage_attachments
          WHERE record_type = 'SentReplyAttachment'
            AND name = 'file'
            AND record_id IN (
              SELECT sent_reply_attachments.id
              FROM sent_reply_attachments
              INNER JOIN sent_replies ON sent_replies.id = sent_reply_attachments.sent_reply_id
              WHERE sent_replies.conversation_id IN #{dev_conversation_ids_sql}
            )
        SQL
        delete_row.call('sent_reply_attachments', <<~SQL.squish)
          DELETE FROM sent_reply_attachments
          WHERE sent_reply_id IN (SELECT id FROM sent_replies WHERE conversation_id IN #{dev_conversation_ids_sql})
        SQL
        delete_row.call('sent_replies', "DELETE FROM sent_replies WHERE conversation_id IN #{dev_conversation_ids_sql}")
      end
      if reply_scope_sql.present?
        delete_row.call('active_storage_attachments', <<~SQL.squish)
          DELETE FROM active_storage_attachments
          WHERE record_type = 'ReplyAttachment'
            AND name = 'file'
            AND record_id IN (
              SELECT reply_attachments.id
              FROM reply_attachments
              INNER JOIN replies ON replies.id = reply_attachments.reply_id
              WHERE #{reply_scope_sql}
            )
        SQL
        delete_row.call('reply_attachments', <<~SQL.squish)
          DELETE FROM reply_attachments
          WHERE reply_id IN (SELECT id FROM replies WHERE #{reply_scope_sql})
        SQL
      end
      delete_row.call('replies', "DELETE FROM replies WHERE #{reply_scope_sql}") if reply_scope_sql.present?
      if dev_agent_lead_ids_sql.present?
        delete_row.call('generated_messages',
                        "DELETE FROM generated_messages WHERE agent_lead_id IN #{dev_agent_lead_ids_sql}")
      end
      if dev_agent_lead_run_ids_sql.present?
        delete_row.call('generated_messages',
                        "DELETE FROM generated_messages WHERE agent_lead_run_id IN #{dev_agent_lead_run_ids_sql}")
        local_conn.update(<<~SQL.squish)
          UPDATE agent_leads
          SET current_agent_lead_run_id = NULL
          WHERE current_agent_lead_run_id IN #{dev_agent_lead_run_ids_sql}
        SQL
        delete_row.call('agent_lead_runs', "DELETE FROM agent_lead_runs WHERE id IN #{dev_agent_lead_run_ids_sql}")
      end
      if dev_conversation_ids_sql.present?
        delete_row.call('conversation_reads',
                        "DELETE FROM conversation_reads WHERE conversation_id IN #{dev_conversation_ids_sql}")
      end
      if dev_playbook_ids_sql.present?
        delete_row.call('playbook_attachment_playbooks',
                        "DELETE FROM playbook_attachment_playbooks WHERE playbook_id IN #{dev_playbook_ids_sql}")
        delete_row.call('playbook_attachments',
                        "DELETE FROM playbook_attachments WHERE playbook_id IN #{dev_playbook_ids_sql} OR organization_id = #{local_org_id_sql}")
        delete_row.call('playbook_comments',
                        "DELETE FROM playbook_comments WHERE playbook_id IN #{dev_playbook_ids_sql}")
      end
      delete_row.call('organization_files', "DELETE FROM organization_files WHERE organization_id = #{local_org_id_sql}")
      if invitation_scope_sql.present?
        delete_row.call('invitations',
                        "DELETE FROM invitations WHERE #{invitation_scope_sql}")
      end
      delete_row.call('admin_activities', "DELETE FROM admin_activities WHERE organization_id = #{local_org_id_sql}")

      delete_row.call('meetings', "DELETE FROM meetings WHERE #{meeting_scope_sql}") if meeting_scope_sql.present?
      if dev_conversation_scope_sql.present?
        delete_row.call('conversations', "DELETE FROM conversations WHERE #{dev_conversation_scope_sql}")
      end
      if agent_lead_scope_sql.present?
        delete_row.call('agent_leads',
                        "DELETE FROM agent_leads WHERE #{agent_lead_scope_sql}")
      end
      agent_mailbox_scope_sql = or_conditions_sql([
                                                    ("agent_id IN #{dev_agent_ids_sql}" if dev_agent_ids_sql.present?),
                                                    (if dev_mailbox_ids_sql.present?
                                                       "mailbox_id IN #{dev_mailbox_ids_sql}"
                                                     end)
                                                  ])
      if agent_mailbox_scope_sql.present?
        delete_row.call('agent_mailboxes', "DELETE FROM agent_mailboxes WHERE #{agent_mailbox_scope_sql}")
      end
      if dev_agent_ids_sql.present? || dev_mailbox_ids_sql.present?
        counter_scope_sql = or_conditions_sql([
                                                ("agent_id IN #{dev_agent_ids_sql}" if dev_agent_ids_sql.present?),
                                                ("mailbox_id IN #{dev_mailbox_ids_sql}" if dev_mailbox_ids_sql.present?)
                                              ])
        delete_row.call('agent_mailbox_daily_counters',
                        "DELETE FROM agent_mailbox_daily_counters WHERE #{counter_scope_sql}")
      end
      if dev_agent_ids_sql.present?
        delete_row.call('sequence_steps', "DELETE FROM sequence_steps WHERE agent_id IN #{dev_agent_ids_sql}")
        delete_row.call('agent_daily_send_stats',
                        "DELETE FROM agent_daily_send_stats WHERE agent_id IN #{dev_agent_ids_sql}")
      end

      delete_row.call('leads', "DELETE FROM leads WHERE organization_id = #{local_org_id_sql}")
      lead_import_sql = "DELETE FROM lead_imports WHERE organization_id = #{local_org_id_sql}"
      lead_import_sql += " OR agent_id IN #{dev_agent_ids_sql}" if dev_agent_ids_sql.present?
      delete_row.call('lead_imports', lead_import_sql)
      delete_row.call('agents', "DELETE FROM agents WHERE #{agent_scope_sql}") if agent_scope_sql.present?
      delete_row.call('mailboxes', "DELETE FROM mailboxes WHERE organization_id = #{local_org_id_sql}")
      delete_row.call('playbooks', "DELETE FROM playbooks WHERE organization_id = #{local_org_id_sql}")
      delete_row.call('blacklists', "DELETE FROM blacklists WHERE organization_id = #{local_org_id_sql}")

      if dev_account_ids_sql.present?
        delete_row.call('account_login_change_keys',
                        "DELETE FROM account_login_change_keys WHERE id IN #{dev_account_ids_sql}")
        delete_row.call('account_password_reset_keys',
                        "DELETE FROM account_password_reset_keys WHERE id IN #{dev_account_ids_sql}")
        delete_row.call('account_remember_keys', "DELETE FROM account_remember_keys WHERE id IN #{dev_account_ids_sql}")
        delete_row.call('account_verification_keys',
                        "DELETE FROM account_verification_keys WHERE id IN #{dev_account_ids_sql}")
        delete_row.call('organization_memberships',
                        "DELETE FROM organization_memberships WHERE account_id IN #{dev_account_ids_sql}")
      end

      delete_row.call('organization_memberships',
                      "DELETE FROM organization_memberships WHERE organization_id = #{local_org_id_sql}")

      delete_row.call('accounts', "DELETE FROM accounts WHERE organization_id = #{local_org_id_sql}")
      delete_row.call('email_domains', "DELETE FROM email_domains WHERE organization_id = #{local_org_id_sql}")
      delete_row.call('senders', "DELETE FROM senders WHERE organization_id = #{local_org_id_sql}")
      local_conn.update(<<~SQL.squish)
        UPDATE organizations
        SET autoreply_prompt_id = NULL
        WHERE id = #{local_org_id_sql}
          AND autoreply_prompt_id IN (SELECT id FROM prompts WHERE organization_id = #{local_org_id_sql})
      SQL
      delete_row.call('prompts', "DELETE FROM prompts WHERE organization_id = #{local_org_id_sql}")
      delete_row.call('integration_credentials',
                      "DELETE FROM integration_credentials WHERE organization_id = #{local_org_id_sql}")
      delete_row.call('organization_webhook_endpoints',
                      "DELETE FROM organization_webhook_endpoints WHERE organization_id = #{local_org_id_sql}")
      delete_row.call('organizations', "DELETE FROM organizations WHERE id = #{local_org_id_sql}")
      if local_org_website_scrape_ids_sql.present?
        delete_row.call('website_scrapes', <<~SQL.squish)
          DELETE FROM website_scrapes
          WHERE id IN #{local_org_website_scrape_ids_sql}
            AND NOT EXISTS (
              SELECT 1 FROM organizations WHERE organizations.website_scrape_id = website_scrapes.id
            )
            AND NOT EXISTS (
              SELECT 1 FROM people WHERE people.company_website_scrape_id = website_scrapes.id
            )
            AND NOT EXISTS (
              SELECT 1 FROM companies WHERE companies.website_scrape_id = website_scrapes.id
            )
        SQL
      end

      true
    end

    private

    attr_reader :delete_row, :local_conn

    def in_list_sql(values, quote: true)
      items = values.compact.uniq
      return nil if items.empty?

      list = items.map { |value| quote ? local_conn.quote(value) : value.to_s }.join(', ')
      "(#{list})"
    end

    def or_conditions_sql(conditions)
      clauses = conditions.compact.reject(&:blank?)
      return nil if clauses.empty?

      clauses.map { |clause| "(#{clause})" }.join(' OR ')
    end
  end
end
