# frozen_string_literal: true

# Aggregate inbox statistics for the assistant. One SQL pass answers "how is my inbox doing?"
# without the model paging through individual conversations. Mirrors the stat definitions the
# inbox UI shows (RepliesController#conversation_stat_counts).
module Assistant
  class ConversationStatsTool < BaseTool
    description 'Returns aggregate statistics for the inbox: totals by status, unread count, ' \
                'conversations awaiting a reply, bounces, out-of-office, and a breakdown by ' \
                'interest status. Use this for "how many" and "how is my inbox doing" questions.'

    # WHY "human": conversations whose latest relevant reply is a real person (not a bounce and
    # not an auto out-of-office) — the same definition the inbox UI uses for its filters.
    HUMAN_CONDITION = 'conversations.has_bounce = FALSE AND conversations.latest_relevant_reply_is_out_of_office = FALSE'
    AWAITING_CONDITION = 'conversations.last_reply_at IS NOT NULL AND ' \
                         '(conversations.last_sent_reply_at IS NULL OR conversations.last_reply_at > conversations.last_sent_reply_at)'

    def execute
      base = scoped(Conversation).visible_in_reply_center
      row = base.unscope(:order).select(Arel.sql(stats_select_sql)).take

      {
        total: row.total_count.to_i,
        open: row.open_count.to_i,
        snoozed: row.snoozed_count.to_i,
        closed: row.closed_count.to_i,
        unread: base.unread_for(account).human_reply_type.count,
        awaiting_reply: row.awaiting_count.to_i,
        bounced: row.bounced_count.to_i,
        out_of_office: row.out_of_office_count.to_i,
        by_interest_status: {
          interested: row.interested_count.to_i,
          meeting_request: row.meeting_request_count.to_i,
          not_interested: row.not_interested_count.to_i,
          wrong_person: row.wrong_person_count.to_i,
          unclassified: row.unclassified_count.to_i
        }
      }
    end

    private

    def stats_select_sql
      snoozed_filter = ActiveRecord::Base.sanitize_sql_array(
        ["COUNT(*) FILTER (WHERE conversations.status = 'snoozed' AND conversations.snoozed_until > ?) AS snoozed_count",
         Time.current]
      )

      <<~SQL.squish
        COUNT(*) AS total_count,
        COUNT(*) FILTER (WHERE conversations.status = 'open') AS open_count,
        #{snoozed_filter},
        COUNT(*) FILTER (WHERE conversations.status = 'closed') AS closed_count,
        COUNT(*) FILTER (WHERE #{AWAITING_CONDITION}) AS awaiting_count,
        COUNT(*) FILTER (WHERE conversations.has_bounce = TRUE) AS bounced_count,
        COUNT(*) FILTER (WHERE conversations.latest_relevant_reply_is_out_of_office = TRUE AND conversations.has_bounce = FALSE) AS out_of_office_count,
        COUNT(*) FILTER (WHERE #{HUMAN_CONDITION} AND conversations.interest_status = 'interested') AS interested_count,
        COUNT(*) FILTER (WHERE #{HUMAN_CONDITION} AND conversations.interest_status = 'meeting_request') AS meeting_request_count,
        COUNT(*) FILTER (WHERE #{HUMAN_CONDITION} AND conversations.interest_status = 'not_interested') AS not_interested_count,
        COUNT(*) FILTER (WHERE #{HUMAN_CONDITION} AND conversations.interest_status = 'wrong_person') AS wrong_person_count,
        COUNT(*) FILTER (WHERE #{HUMAN_CONDITION} AND conversations.interest_status IS NULL) AS unclassified_count
      SQL
    end
  end
end
