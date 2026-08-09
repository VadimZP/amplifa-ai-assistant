# frozen_string_literal: true

# Lists and searches inbox conversations for the assistant. Mirrors the filters the inbox UI
# offers (RepliesController#apply_filters) so the assistant can answer the same questions the
# user could answer by clicking around.
module Assistant
  class ConversationListTool < BaseTool
    DEFAULT_LIMIT = 20
    MAX_LIMIT = 50
    MAX_OFFSET = 1_000
    PREVIEW_LENGTH = 160

    description 'Lists and searches email conversations in the inbox, newest reply first. ' \
                'Returns matching rows plus total_count. Call this before answering any inbox or ' \
                'conversation question — never claim a conversation does not exist without calling ' \
                'this tool first. Prefer filters over fetching everything; for aggregate counts ' \
                'use conversation_stats instead.'

    param :status, desc: "Filter by conversation status. One of: #{Conversation::STATUSES.join(', ')}",
                   required: false
    param :interest_status,
          desc: "Filter by the lead's interest classification. One of: #{Conversation::INTEREST_STATUSES.join(', ')}",
          required: false
    param :search, desc: 'Free-text search over lead first name, last name, email and company', required: false
    param :unread_only, type: :boolean, desc: 'Only conversations with replies the user has not read yet',
                        required: false
    param :awaiting_reply_only, type: :boolean,
                                desc: 'Only conversations where the lead sent the last message and is waiting for an answer',
                                required: false
    param :last_reply_after, desc: 'ISO 8601 date or datetime — only conversations whose last reply is at or after this moment',
                             required: false
    param :last_reply_before, desc: 'ISO 8601 date or datetime — only conversations whose last reply is at or before this moment',
                              required: false
    param :limit, type: :integer, desc: "Rows to return (default #{DEFAULT_LIMIT}, max #{MAX_LIMIT})",
                  required: false
    param :offset, type: :integer, desc: 'Rows to skip, for paging through more results', required: false

    def execute(status: nil, interest_status: nil, search: nil, unread_only: nil, awaiting_reply_only: nil,
                last_reply_after: nil, last_reply_before: nil, limit: DEFAULT_LIMIT, offset: 0)
      if status.present? && Conversation::STATUSES.exclude?(status.to_s)
        return invalid_enum('status', status, Conversation::STATUSES)
      end
      if interest_status.present? && Conversation::INTEREST_STATUSES.exclude?(interest_status.to_s)
        return invalid_enum('interest_status', interest_status, Conversation::INTEREST_STATUSES)
      end

      after = parse_time(last_reply_after)
      return invalid_time('last_reply_after', last_reply_after) if last_reply_after.present? && after.nil?

      before = parse_time(last_reply_before)
      return invalid_time('last_reply_before', last_reply_before) if last_reply_before.present? && before.nil?

      scope = filtered_scope(status:, interest_status:, search:, unread_only:, awaiting_reply_only:,
                             after:, before:)

      total = scope.count
      rows = scope.recent
                  .includes(:lead, :agent)
                  .offset(offset.to_i.clamp(0, MAX_OFFSET))
                  .limit(limit.to_i.clamp(1, MAX_LIMIT))
                  .to_a

      { total_count: total, returned_count: rows.size, conversations: serialize(rows) }
    end

    private

    def filtered_scope(status:, interest_status:, search:, unread_only:, awaiting_reply_only:, after:, before:)
      scope = scoped(Conversation).visible_in_reply_center
      scope = scope.where(status: status.to_s) if status.present?
      scope = scope.human_reply_type.where(interest_status: interest_status.to_s) if interest_status.present?
      scope = scope.unread_for(account) if unread_only
      scope = scope.where(awaiting_reply_condition) if awaiting_reply_only
      scope = scope.where(conversations: { last_reply_at: after.. }) if after
      scope = scope.where(conversations: { last_reply_at: ..before }) if before
      scope = apply_search(scope, search) if search.present?
      scope
    end

    def apply_search(scope, search)
      LeadSearchSql.apply(scope.joins(:lead), search)
    end

    def awaiting_reply_condition
      <<~SQL.squish
        conversations.last_reply_at IS NOT NULL
        AND (conversations.last_sent_reply_at IS NULL OR conversations.last_reply_at > conversations.last_sent_reply_at)
      SQL
    end

    def serialize(rows)
      reads = ConversationRead.where(account: account, conversation_id: rows.map(&:id))
                              .index_by(&:conversation_id)

      rows.map do |conversation|
        read_record = reads[conversation.id]
        {
          id: conversation.id,
          lead_name: conversation.lead.display_name,
          lead_email: conversation.lead.email,
          company: conversation.lead.company,
          status: conversation.status,
          interest_status: conversation.interest_status,
          unread: unread?(conversation, read_record),
          awaiting_reply: awaiting_reply?(conversation),
          last_reply_at: conversation.last_reply_at&.iso8601,
          last_reply_preview: conversation.last_reply_preview&.truncate(PREVIEW_LENGTH),
          agent: conversation.agent&.name
        }
      end
    end

    def unread?(conversation, read_record)
      conversation.last_reply_at.present? &&
        (read_record.nil? || conversation.last_reply_at > read_record.last_read_at)
    end

    def awaiting_reply?(conversation)
      conversation.last_reply_at.present? &&
        (conversation.last_sent_reply_at.nil? || conversation.last_reply_at > conversation.last_sent_reply_at)
    end

    def parse_time(value)
      return nil if value.blank?

      Time.zone.parse(value.to_s)
    rescue ArgumentError
      nil
    end

    def invalid_enum(field, value, allowed)
      { error: "Unknown #{field} '#{value.to_s.truncate(30)}'. Valid values: #{allowed.join(', ')}." }
    end

    def invalid_time(field, value)
      { error: "Could not parse #{field} '#{value.to_s.truncate(30)}'. Use an ISO 8601 date like 2026-08-01." }
    end
  end
end
