# frozen_string_literal: true

# Shared query helpers for deriving conversation-level reply status from the latest relevant reply.
module ConversationReplyStatus
  extend ActiveSupport::Concern

  private

  def bounce_conversation_ids(conversations)
    conversations.unscope(:order).joins(:replies).where(replies: { is_bounce: true }).select(:id)
  end

  def latest_out_of_office_conversation_ids(conversations)
    conversations
      .unscope(:order)
      .joins(latest_relevant_replies_inner_join(conversations: conversations))
      .where('latest_relevant_replies.is_out_of_office = TRUE')
      .select(:id)
  end

  def latest_relevant_replies_inner_join(conversations: nil)
    <<~SQL.squish
      INNER JOIN (#{latest_relevant_replies_sql(conversations: conversations)}) latest_relevant_replies
      ON latest_relevant_replies.conversation_id = conversations.id
    SQL
  end

  def latest_relevant_replies_join(conversations: nil)
    <<~SQL.squish
      LEFT JOIN (#{latest_relevant_replies_sql(conversations: conversations)}) latest_relevant_replies
      ON latest_relevant_replies.conversation_id = conversations.id
    SQL
  end

  def latest_out_of_office_sql
    'COALESCE(latest_relevant_replies.is_out_of_office, FALSE)'
  end

  def latest_relevant_reply_rows_by_conversation_id(conversation_ids)
    ids = conversation_ids.compact.uniq
    return {} if ids.empty?

    rows = ActiveRecord::Base.connection.exec_query(<<~SQL.squish)
      SELECT latest_relevant_replies.conversation_id,
             latest_relevant_replies.is_out_of_office,
             latest_relevant_replies.out_of_office_return_date
      FROM (#{latest_relevant_replies_sql(conversation_ids: ids)}) latest_relevant_replies
    SQL

    rows.index_by { |row| row['conversation_id'] }
  end

  def latest_relevant_reply_for(conversation)
    conversation.replies
                .where(is_bounce: false, is_warmup: false)
                .order(received_at: :desc, id: :desc)
                .first
  end

  def latest_relevant_reply_out_of_office?(latest_relevant_reply)
    latest_relevant_reply&.fetch('is_out_of_office', false) || false
  end

  def latest_relevant_reply_out_of_office_return_date(latest_relevant_reply)
    return nil unless latest_relevant_reply_out_of_office?(latest_relevant_reply)

    latest_relevant_reply['out_of_office_return_date']
  end

  def latest_relevant_replies_sql(conversation_ids: nil, conversations: nil)
    <<~SQL.squish
      SELECT DISTINCT ON (replies.conversation_id)
             replies.conversation_id,
             replies.is_out_of_office,
             replies.out_of_office_return_date
      FROM replies
      WHERE #{latest_relevant_reply_conditions(conversation_ids: conversation_ids, conversations: conversations)}
      ORDER BY replies.conversation_id, replies.received_at DESC, replies.id DESC
    SQL
  end

  def latest_relevant_reply_conditions(conversation_ids: nil, conversations: nil)
    conditions = ['replies.is_bounce = FALSE', 'replies.is_warmup = FALSE']
    conditions << "replies.conversation_id IN (#{conversation_ids.map(&:to_i).join(',')})" if conversation_ids.present?
    conditions << "replies.conversation_id IN (#{conversation_scope_sql(conversations)})" unless conversations.nil?
    conditions.join(' AND ')
  end

  def conversation_scope_sql(conversations)
    conversations.unscope(:order).select(:id).to_sql
  end
end
