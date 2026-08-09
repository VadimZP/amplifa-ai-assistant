# frozen_string_literal: true

class RepliesController < ApplicationController
  include ConversationReplyStatus
  include ReplyInlineImageRendering
  include InboxLeadContextSerialization

  before_action :redirect_amplifa_admin_to_global_reply_center, only: :index
  before_action :set_conversation, only: %i[mark_read update_interest_status]

  PER_PAGE = 25
  REPLY_CENTER_REPLY_TYPES = %w[all bounced ooo interested meeting_request not_interested wrong_person].freeze

  def index
    persist_reply_center_filter_preferences

    conversations = scoped_conversations.visible_in_reply_center
                                        .includes(:mailbox, :agent,
                                                  lead: { person: { linkedin_profile_photo_attachment: :blob } })
                                        .recent
    conversations = apply_filters(conversations)

    page = (params[:page] || 1).to_i
    paginated_conversations = -> { conversations.offset((page - 1) * PER_PAGE).limit(PER_PAGE) }

    selected_conversation = selected_conversation_for_reply_center

    render inertia: 'Admin/Organizations/Replies/Index', props: {
      organization: serialize_organization,
      conversations: -> { serialize_conversations(prepend_selected_conversation(paginated_conversations.call, selected_conversation)) },
      filters: current_filters,
      stats: -> { conversation_stats },
      mailbox_status: -> { mailbox_polling_status },
      sender_options: -> { serialize_reply_center_senders },
      pagination: -> { pagination_payload(conversations, page) },
      current_tab: 'replies',
      selected_id: params[:selected_id]&.to_i,
      selected_detail: -> { build_selected_detail(selected_conversation) },
      auto_open_composer: params[:compose] == '1',
      return_to: params[:return_to],
      layout_mode: 'full',
      base_path: replies_path,
      reply_filter_menu_enabled: true,
      show_unassigned_link: false
    }
  end

  def mark_read
    authorize @conversation, :mark_read?, policy_class: ConversationPolicy

    reply = @conversation.replies.find(params[:reply_id])
    reply.mark_read!

    head :ok
  end

  def update_interest_status
    authorize @conversation, :update_interest_status?, policy_class: ConversationPolicy

    result = ConversationInterestStatusUpdater.new(
      conversation: @conversation,
      target_status: params[:interest_status],
      actor: current_account,
      reason_context: params[:reason_context]
    ).call

    if result.success?
      render json: { success: true, interest_status: @conversation.reload.interest_status }, status: :ok
    else
      render json: { error: result.error }, status: :unprocessable_entity
    end
  end

  private

  def redirect_amplifa_admin_to_global_reply_center
    return unless current_account&.amplifa_admin?

    skip_policy_scope
    redirect_to admin_replies_path
  end

  def current_organization
    Current.organization
  end

  def scoped_conversations
    policy_scope(Conversation).where(organization_id: current_organization.id)
  end

  def set_conversation
    @conversation = scoped_conversations.find(params[:id])
  end

  def apply_filters(conversations)
    conversations = conversations.where(status: params[:status]) if params[:status].present? && params[:status] != 'all'
    conversations = conversations.where(mailbox_id: params[:mailbox_id]) if params[:mailbox_id].present?
    if reply_center_sender_id.present?
      conversations = conversations.where(mailbox_id: reply_center_sender_mailbox_ids)
    end
    conversations = conversations.where(agent_id: params[:agent_id]) if params[:agent_id].present?
    conversations = conversations.unread_for(current_account) if params[:unread_only] == 'true'

    reply_type = reply_center_reply_type
    human_conversations = conversations.human_reply_type

    conversations = case reply_type
                    when 'bounced'
                      conversations.with_bounce
                    when 'ooo'
                      conversations.with_latest_relevant_out_of_office.where(has_bounce: false)
                    when 'interested'
                      human_conversations.where(interest_status: 'interested')
                    when 'meeting_request'
                      human_conversations.where(interest_status: 'meeting_request')
                    when 'not_interested'
                      human_conversations.where(interest_status: 'not_interested')
                    when 'wrong_person'
                      human_conversations.where(interest_status: 'wrong_person')
                    when 'all'
                      human_conversations
                    else
                      human_conversations
                    end

    if params[:search].present?
      search_term = reply_search_term
      conversations = conversations.joins(:lead).where(
        'leads.email ILIKE :term OR leads.first_name ILIKE :term OR leads.last_name ILIKE :term OR leads.company ILIKE :term',
        term: search_term
      )
    end

    conversations
  end

  def current_filters
    {
      status: params[:status] || 'open',
      mailbox_id: params[:mailbox_id],
      sender_id: reply_center_sender_id,
      agent_id: params[:agent_id],
      unread_only: params[:unread_only],
      search: normalized_reply_search_param,
      reply_type: reply_center_reply_type
    }
  end

  def persist_reply_center_filter_preferences
    return unless params.key?(:reply_type) || params.key?(:sender_id)

    next_filters = current_account.reply_center_filters.deep_dup
    if params.key?(:reply_type)
      next_filters['reply_type'] = reply_center_reply_type_from(params[:reply_type])
    end
    if params.key?(:sender_id)
      next_filters['sender_id'] = reply_center_sender_id_from(params[:sender_id])
    end

    current_account.update!(reply_center_filters: next_filters)
  end

  def reply_center_filter_preferences
    current_account.reply_center_filters || {}
  end

  def reply_center_reply_type
    reply_center_reply_type_from(params[:reply_type].presence || reply_center_filter_preferences['reply_type'])
  end

  def reply_center_reply_type_from(value)
    reply_type = value.to_s.presence || 'all'
    return reply_type if REPLY_CENTER_REPLY_TYPES.include?(reply_type)

    'all'
  end

  def reply_center_sender_id
    reply_center_sender_id_from(params[:sender_id].presence || reply_center_filter_preferences['sender_id'])
  end

  def reply_center_sender_id_from(value)
    sender_id = value.to_s.presence
    return nil if sender_id.blank? || sender_id == 'all'

    current_organization.senders.exists?(id: sender_id) ? sender_id : nil
  end

  def reply_center_sender_mailbox_ids
    current_organization.mailboxes.not_deleted.where(sender_id: reply_center_sender_id).select(:id)
  end

  def normalized_reply_search_param
    params[:search].to_s.unicode_normalize(:nfc).presence
  end

  def reply_search_term
    "%#{ActiveRecord::Base.sanitize_sql_like(normalized_reply_search_param)}%"
  end

  def conversation_stats
    base = scoped_conversations.visible_in_reply_center
    unassigned_count = Reply.needs_human_assignment
                            .joins(:mailbox)
                            .where(mailboxes: { organization_id: current_organization.id })
                            .count

    counts = conversation_stat_counts(base)

    {
      total: counts[:total],
      open: counts[:open],
      unread: base.unread_for(current_account).human_reply_type.count,
      snoozed: counts[:snoozed],
      closed: counts[:closed],
      unassigned: unassigned_count,
      bounced: counts[:bounced],
      out_of_office: counts[:out_of_office],
      human: counts[:human],
      interested: counts[:interested],
      meeting_request: counts[:meeting_request],
      not_interested: counts[:not_interested],
      wrong_person: counts[:wrong_person]
    }
  end

  def conversation_stat_counts(base)
    snoozed_count_sql = ActiveRecord::Base.sanitize_sql_array([
                                                                  "COUNT(*) FILTER (WHERE conversations.status = 'snoozed' AND conversations.snoozed_until > ?) AS snoozed_count",
                                                                  Time.current
                                                                ])
    human_condition = 'conversations.has_bounce = FALSE AND conversations.latest_relevant_reply_is_out_of_office = FALSE'
    row = base.unscope(:order).select(Arel.sql(<<~SQL.squish)).take
      COUNT(*) AS total_count,
      COUNT(*) FILTER (WHERE conversations.status = 'open') AS open_count,
      #{snoozed_count_sql},
      COUNT(*) FILTER (WHERE conversations.status = 'closed') AS closed_count,
      COUNT(*) FILTER (WHERE conversations.has_bounce = TRUE) AS bounced_count,
      COUNT(*) FILTER (WHERE conversations.latest_relevant_reply_is_out_of_office = TRUE AND conversations.has_bounce = FALSE) AS out_of_office_count,
      COUNT(*) FILTER (WHERE #{human_condition}) AS human_count,
      COUNT(*) FILTER (WHERE #{human_condition} AND conversations.interest_status = 'interested') AS interested_count,
      COUNT(*) FILTER (WHERE #{human_condition} AND conversations.interest_status = 'meeting_request') AS meeting_request_count,
      COUNT(*) FILTER (WHERE #{human_condition} AND conversations.interest_status = 'not_interested') AS not_interested_count,
      COUNT(*) FILTER (WHERE #{human_condition} AND conversations.interest_status = 'wrong_person') AS wrong_person_count
    SQL

    {
      total: row.total_count.to_i,
      open: row.open_count.to_i,
      snoozed: row.snoozed_count.to_i,
      closed: row.closed_count.to_i,
      bounced: row.bounced_count.to_i,
      out_of_office: row.out_of_office_count.to_i,
      human: row.human_count.to_i,
      interested: row.interested_count.to_i,
      meeting_request: row.meeting_request_count.to_i,
      not_interested: row.not_interested_count.to_i,
      wrong_person: row.wrong_person_count.to_i
    }
  end

  def mailbox_polling_status
    mailboxes = current_organization.mailboxes.active
    return { last_polled_at: nil, status: 'no_mailboxes', mailbox_count: 0 } if mailboxes.empty?

    most_recent = mailboxes.maximum(:last_polled_at)
    error_count = mailboxes.where.not(last_poll_error: nil).count

    {
      last_polled_at: most_recent,
      status: error_count > 0 ? 'some_errors' : 'ok',
      mailbox_count: mailboxes.count,
      error_count: error_count
    }
  end

  def serialize_organization
    { id: current_organization.id, name: current_organization.name,
      ai_reply_agent_enabled: current_organization.ai_reply_agent_enabled }
  end

  def serialize_reply_center_senders
    current_organization.senders.active
                        .joins(:mailboxes)
                        .merge(Mailbox.not_deleted)
                        .distinct
                        .order(:first_name, :last_name, :email)
                        .map do |sender|
      {
        id: sender.id,
        name: sender.full_name,
        email: sender.email
      }
    end
  end

  def pagination_payload(conversations, page)
    total_count = conversations.count

    {
      current_page: page,
      total_pages: (total_count.to_f / PER_PAGE).ceil,
      total_count: total_count,
      per_page: PER_PAGE
    }
  end

  def serialize_conversations(conversations)
    conversation_ids = conversations.map(&:id)

    reads_by_conversation_id = ConversationRead
                               .where(conversation_id: conversation_ids, account_id: current_account.id)
                               .index_by(&:conversation_id)

    conversations.map do |conversation|
      serialize_conversation(
        conversation,
        read_record: reads_by_conversation_id[conversation.id],
        compact: true
      )
    end
  end

  def serialize_conversation(conv, last_sent_reply_at: :not_provided, read_record: :not_provided, has_bounce: nil,
                             has_out_of_office: nil, ooo_return_date: nil, compact: false)
    last_sent_reply_at = conv.last_sent_reply_at if last_sent_reply_at == :not_provided
    last_incoming_at = conv.last_reply_at
    awaiting_reply = last_incoming_at.present? && (last_sent_reply_at.nil? || last_incoming_at > last_sent_reply_at)

    is_unread = if read_record == :not_provided
                  conv.unread_for?(current_account)
                else
                  conv.last_reply_at.present? && (read_record.nil? || conv.last_reply_at > read_record.last_read_at)
                end

    current_has_bounce = has_bounce.nil? ? conv.has_bounce : has_bounce
    current_has_out_of_office = has_out_of_office.nil? ? conv.latest_relevant_reply_is_out_of_office : has_out_of_office
    current_ooo_return_date = ooo_return_date.nil? ? conv.ooo_return_date : ooo_return_date

    payload = {
      id: conv.id,
      status: conv.status,
      interest_status: conv.interest_status,
      is_unread: is_unread,
      last_reply_at: conv.last_reply_at,
      last_reply_preview: conv.last_reply_preview,
      awaiting_reply: awaiting_reply,
      has_bounce: current_has_bounce,
      has_out_of_office: current_has_out_of_office,
      ooo_return_date: current_ooo_return_date,
      lead: {
        email: conv.lead.email,
        first_name: conv.lead.first_name,
        last_name: conv.lead.last_name,
        company: conv.lead.company,
        linkedin_profile_photo_url: conv.lead.person&.linkedin_profile_photo&.attached? ? url_for(conv.lead.person.linkedin_profile_photo) : nil
      }
    }

    unless compact
      payload[:replies_count] = conv.replies_count
      payload[:unread_count] = conv.unread_count
      payload[:snoozed_until] = conv.snoozed_until
      payload[:lead][:id] = conv.lead.id
      payload[:agent_name] = conv.agent&.name
      payload[:mailbox] = {
        id: conv.mailbox.id,
        email: conv.mailbox.email
      }
    end

    payload
  end

  def serialize_lead(lead)
    buying_signals_summary = lead.latest_buying_signals_summary

    {
      id: lead.id,
      email: lead.email,
      first_name: lead.first_name,
      last_name: lead.last_name,
      display_name: lead.display_name,
      company: lead.company,
      job_title: lead.job_title,
      location: lead.location,
      linkedin_url: lead.linkedin_url,
      company_website: lead.company_website,
      linkedin_profile_photo_url: lead.person&.linkedin_profile_photo&.attached? ? url_for(lead.person.linkedin_profile_photo) : nil,
      timezone: lead.timezone,
      timezone_resolved_at: lead.timezone_resolved_at,
      disc_profile: lead.disc_profile,
      disc_profile_data: lead.person&.disc_profile_data,
      disc_profile_assessed_at: lead.person&.disc_profile_assessed_at,
      disc_profile_source: lead.person&.disc_profile_source,
      linkedin_scraped_at: lead.linkedin_scraped_at,
      linkedin_scraped_data: lead.linkedin_scraped_data,
      linkedin_headline: lead.linkedin_headline,
      linkedin_summary: lead.linkedin_summary,
      linkedin_posts_scraped_at: lead.linkedin_posts_scraped_at,
      linkedin_posts: lead.linkedin_posts&.first(5),
      company_website_scraped_at: lead.company_website_scraped_at,
      company_website_content: lead.company_website_content&.truncate(3000),
      company_website_summary: lead.company_website_summary,
      buying_signals_summary_status: buying_signals_summary&.status,
      buying_signals_markdown: buying_signals_summary&.markdown || '',
      buying_signals_generated_at: buying_signals_summary&.generated_at,
      person: lead.person ? { id: lead.person.id, display_name: lead.person.display_name } : nil,
      agent_leads: serialize_inbox_agent_leads_for(lead)
    }
  end

  def serialize_mailbox(mailbox)
    {
      id: mailbox.id,
      email: mailbox.email,
      display_name: mailbox.display_name
    }
  end

  def serialize_sender(sender)
    return nil unless sender

    {
      id: sender.id,
      full_name: sender.full_name,
      email: sender.email,
      job_title: sender.job_title,
      has_signature: sender.signature_template.present?
    }
  end

  def build_thread_messages_for(conversation)
    conversation.thread_messages.map do |msg|
      {
        id: msg[:id],
        type: msg[:type].to_s,
        source: msg[:source].to_s,
        from: msg[:from_address],
        subject: msg[:subject],
        to_addresses: msg[:to_addresses],
        cc_addresses: msg[:cc_addresses],
        body_plain: msg[:body_plain],
        body_html: body_html_for_thread_message(msg),
        calendar_event: serialize_calendar_event(msg[:calendar_event]),
        attachments: serialize_thread_attachments(msg[:attachments], body_html: msg[:body_html]),
        message_at: msg[:message_at],
        is_bounce: msg[:is_bounce],
        is_out_of_office: msg[:is_out_of_office]
      }
    end
  end

  def serialize_thread_attachments(attachments, body_html: nil)
    Array(attachments).map do |attachment|
      {
        id: attachment[:id],
        filename: attachment[:original_filename],
        content_type: attachment[:content_type],
        file_size_bytes: attachment[:file_size_bytes],
        content_id: attachment[:content_id],
        inline: inline_image_attachment?(attachment) && html_references_attachment_content_id?(body_html, attachment),
        download_url: rails_blob_path(attachment[:file], disposition: 'attachment', only_path: true),
        view_url: image_content_type?(attachment[:content_type]) ? rails_blob_path(attachment[:file], disposition: 'inline', only_path: true) : nil,
        calendar_links: calendar_links_for(attachment)
      }
    end
  end

  def calendar_links_for(attachment)
    unless attachment[:content_type] == 'text/calendar' || attachment[:original_filename].to_s.downcase.ends_with?('.ics')
      return nil
    end

    CalendarInviteLinkBuilder.build(file: attachment[:file],
                                    file_size_bytes: attachment[:file_size_bytes],
                                    fallback_title: attachment[:original_filename].to_s.sub(
                                      /\.ics\z/i, ''
                                    ))
  end

  def serialize_calendar_event(calendar_event)
    return nil unless calendar_event.is_a?(Hash) && calendar_event.present?

    calendar_event.deep_stringify_keys.merge(
      CalendarEventTimeResolver.resolve(event_data: calendar_event)
    ).merge(
      'calendar_links' => CalendarInviteLinkBuilder.build_from_event_data(event_data: calendar_event)
    )
  end

  def build_selected_detail(selected_conversation = nil)
    return nil unless selected_conversation

    authorize selected_conversation, policy_class: ConversationPolicy
    selected_conversation.mark_read_for!(current_account)

    {
      conversation: serialize_conversation(selected_conversation),
      thread: build_thread_messages_for(selected_conversation),
      lead: serialize_lead(selected_conversation.lead),
      mailbox: serialize_mailbox(selected_conversation.mailbox),
      sender: serialize_sender(selected_conversation.mailbox.sender)
    }
  end

  def selected_conversation_for_reply_center
    return nil unless params[:selected_id].present?

    scoped_conversations
      .includes(:mailbox, :agent, mailbox: :sender,
                                     lead: { person: { linkedin_profile_photo_attachment: :blob } })
      .find_by(id: params[:selected_id])
  end

  def prepend_selected_conversation(conversations, selected_conversation)
    collection = conversations.to_a
    return collection unless selected_conversation
    return collection if selected_conversation.last_reply_at.present? && selected_conversation.replies_count.positive?
    return collection if collection.any? { |conversation| conversation.id == selected_conversation.id }

    [selected_conversation, *collection].first(PER_PAGE)
  end
end
