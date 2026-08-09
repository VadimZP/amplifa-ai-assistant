# frozen_string_literal: true

module CustomerLeadModalSerialization
  private

  def serialize_lead_for_modal(lead)
    buying_signals_summary = lead.latest_buying_signals_summary

    {
      id: lead.id,
      email: lead.email,
      first_name: lead.first_name,
      last_name: lead.last_name,
      full_name: lead.full_name,
      display_name: lead.display_name,
      company: lead.company,
      company_website: lead.company_website,
      job_title: lead.job_title,
      location: lead.location,
      linkedin_url: lead.linkedin_url,
      timezone: lead.timezone,
      blacklisted: lead.blacklisted,
      blacklist_reason: lead.blacklist_reason,
      custom_fields: lead.custom_fields,
      disc_profile: lead.disc_profile,
      disc_profile_data: lead.person&.disc_profile_data,
      disc_profile_assessed_at: lead.person&.disc_profile_assessed_at,
      disc_profile_source: lead.person&.disc_profile_source,
      linkedin_scraped_at: lead.linkedin_scraped_at,
      linkedin_scraped_data: lead.linkedin_scraped_data,
      linkedin_headline: lead.linkedin_headline,
      linkedin_summary: lead.linkedin_summary,
      linkedin_profile_photo_url: lead.person&.linkedin_profile_photo&.attached? ? url_for(lead.person.linkedin_profile_photo) : nil,
      linkedin_posts_scraped_at: lead.linkedin_posts_scraped_at,
      linkedin_posts: lead.linkedin_posts&.first(5),
      buying_signals_summary_status: buying_signals_summary&.status,
      buying_signals_markdown: buying_signals_summary&.markdown || '',
      buying_signals_highlights: buying_signals_summary&.highlight_bullets || [],
      buying_signals_relevance_rating: buying_signals_summary&.relevance_rating,
      buying_signals_generated_at: buying_signals_summary&.generated_at,
      company_website_scraped_at: lead.company_website_scraped_at,
      company_website_content: lead.company_website_content&.truncate(3000),
      company_website_summary: lead.company_website_summary,
      person: lead.person ? { id: lead.person.id, display_name: lead.person.display_name } : nil,
      email_provider: lead.email_provider,
      agent_leads: serialize_agent_leads_for_modal(
        lead.agent_leads.joins(:agent).merge(Agent.not_deleted).includes(
          :assigned_mailbox,
          :generated_messages,
          agent: :sequence_steps
        )
      ),
      conversations: serialize_conversations_for_lead(lead)
    }
  end

  def serialize_agent_leads_for_modal(agent_leads)
    agent_leads.map do |al|
      {
        id: al.id,
        delivery_status: al.delivery_status,
        sequence_position: al.sequence_position,
        has_meeting: al.meeting_booked?,
        agent: {
          id: al.agent.id,
          name: al.agent.name,
          status: al.agent.status,
          sequence_steps: al.agent.active_email_sequence_steps.ordered.map do |step|
            {
              id: step.id,
              position: step.position,
              name: step.name,
              display_name: step.display_name,
              event_type: step.event_type,
              delay_days: step.delay_days
            }
          end
        },
        assigned_mailbox: if al.assigned_mailbox
                            {
                              id: al.assigned_mailbox.id,
                              email: al.assigned_mailbox.email
                            }
                          end,
        generated_messages: serialize_generated_messages(al.generated_messages)
      }
    end
  end

  def serialize_generated_messages(messages)
    messages.map do |msg|
      {
        id: msg.id,
        sequence_step_id: msg.sequence_step_id,
        subject: msg.subject,
        body: msg.body,
        status: msg.status,
        sent_at: msg.sent_at,
        created_at: msg.created_at
      }
    end
  end

  def serialize_conversations_for_lead(lead)
    conversations = Conversation
                    .for_organization(Current.organization)
                    .includes(:mailbox, :replies, :sent_replies)
                    .where(lead_id: lead.id)
                    .order(last_reply_at: :desc)

    conversations.map do |conversation|
      {
        id: conversation.id,
        status: conversation.status,
        interest_status: conversation.interest_status,
        mailbox: {
          id: conversation.mailbox.id,
          email: conversation.mailbox.email
        },
        thread: serialize_thread_messages_for(conversation)
      }
    end
  end

  def serialize_thread_messages_for(conversation)
    conversation.thread_messages.map do |msg|
      {
        id: msg[:id],
        type: msg[:type].to_s,
        source: msg[:source].to_s,
        from: msg[:from_address],
        subject: msg[:subject],
        body_plain: msg[:body_plain],
        body_html: msg[:body_html],
        message_at: msg[:message_at],
        is_bounce: msg[:is_bounce],
        is_out_of_office: msg[:is_out_of_office]
      }
    end
  end
end
