# frozen_string_literal: true

# Reads one full conversation thread for the assistant, so it can summarize or analyze a specific
# exchange. Read-only on purpose: it does NOT mark the conversation as read — the user asking the
# assistant about a thread is not the same as having reviewed it in the inbox.
module Assistant
  class ConversationReadTool < BaseTool
    MAX_MESSAGES = 30
    BODY_LENGTH = 1_500

    description 'Reads one conversation: lead details plus the email thread (newest messages last). ' \
                'Use conversation_list first to find the conversation id.'

    param :conversation_id, type: :integer, desc: 'The id of the conversation to read', required: true

    def execute(conversation_id:)
      conversation = scoped(Conversation).find_by(id: conversation_id)
      # WHY the same message for foreign and unknown ids: a distinguishable answer would let a
      # caller probe which ids exist in other organizations.
      return { error: 'Conversation not found.' } unless conversation

      authorize!(conversation, :show?)

      thread = conversation.thread_messages
      shown = thread.last(MAX_MESSAGES)

      {
        id: conversation.id,
        status: conversation.status,
        interest_status: conversation.interest_status,
        lead: lead_json(conversation.lead),
        agent: conversation.agent&.name,
        message_count: thread.size,
        showing_last: shown.size,
        messages: shown.map { |message| message_json(message) }
      }
    end

    private

    def lead_json(lead)
      {
        name: lead.display_name,
        email: lead.email,
        company: lead.company,
        job_title: lead.job_title
      }
    end

    def message_json(message)
      {
        direction: message[:type].to_s,
        from: message[:from_address],
        subject: message[:subject],
        body: body_text(message),
        at: message[:message_at]&.iso8601,
        is_bounce: message[:is_bounce],
        is_out_of_office: message[:is_out_of_office]
      }
    end

    def body_text(message)
      plain = message[:body_plain].presence || strip_html(message[:body_html])
      plain.to_s.truncate(BODY_LENGTH)
    end

    def strip_html(html)
      return nil if html.blank?

      ActionView::Base.full_sanitizer.sanitize(html)
    end
  end
end
