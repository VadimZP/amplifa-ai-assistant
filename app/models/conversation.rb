# frozen_string_literal: true

class Conversation < ApplicationRecord
  STATUSES = %w[open snoozed closed].freeze
  INTEREST_STATUSES = %w[interested meeting_request not_interested wrong_person].freeze

  belongs_to :organization
  belongs_to :lead
  belongs_to :mailbox
  belongs_to :agent, optional: true
  belongs_to :agent_lead, optional: true
  belongs_to :assigned_to, class_name: 'Account', optional: true
  has_many :replies, dependent: :nullify
  has_many :sent_replies, dependent: :destroy
  has_many :conversation_reads, dependent: :destroy

  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :interest_status, inclusion: { in: INTEREST_STATUSES }, allow_nil: true
  validates :lead_id, uniqueness: { scope: :mailbox_id }
  validates :agent_lead_id, uniqueness: true, allow_nil: true

  scope :open, -> { where(status: 'open') }
  scope :snoozed, -> { where(status: 'snoozed').where('snoozed_until > ?', Time.current) }
  scope :closed, -> { where(status: 'closed') }
  scope :with_unread, -> { where('unread_count > 0') }
  scope :with_bounce, -> { where(has_bounce: true) }
  scope :with_latest_relevant_out_of_office, -> { where(latest_relevant_reply_is_out_of_office: true) }
  scope :human_reply_type, -> { where(has_bounce: false, latest_relevant_reply_is_out_of_office: false) }
  scope :inbound_backed, -> { where.not(last_reply_at: nil).where('replies_count > 0') }
  scope :visible_in_reply_center, -> { inbound_backed }
  scope :recent, -> { order(last_reply_at: :desc) }
  scope :for_organization, ->(org) { where(organization_id: org.id) }
  scope :unread_for, lambda { |account|
    joins(
      sanitize_sql_array([
                           <<~SQL.squish,
                             LEFT JOIN conversation_reads
                             ON conversation_reads.conversation_id = conversations.id
                             AND conversation_reads.account_id = ?
                           SQL
                           account.id
                          ])
    )
      .where('conversations.last_reply_at IS NOT NULL')
      .where('conversation_reads.id IS NULL OR conversations.last_reply_at > conversation_reads.last_read_at')
  }

  def open?
    status == 'open'
  end

  def snoozed?
    status == 'snoozed' && snoozed_until&.future?
  end

  def closed?
    status == 'closed'
  end

  def reopen!
    update!(status: 'open', snoozed_until: nil)
  end

  def snooze!(until_time)
    update!(status: 'snoozed', snoozed_until: until_time)
  end

  def close!
    update!(status: 'closed', snoozed_until: nil)
  end

  def refresh_counters!
    update!(reply_counter_attributes.merge(last_sent_reply_at: sent_replies.sent.maximum(:sent_at)))
  end

  def reply_counter_attributes
    latest_relevant_reply = latest_relevant_reply_for_summary
    latest_relevant_reply_is_out_of_office = latest_relevant_reply&.is_out_of_office? || false

    {
      replies_count: replies.count,
      unread_count: replies.unread.human.count,
      last_reply_at: replies.maximum(:received_at),
      last_reply_preview: replies.order(received_at: :desc).first&.body_preview,
      has_bounce: replies.where(is_bounce: true).exists?,
      latest_relevant_reply_is_out_of_office: latest_relevant_reply_is_out_of_office,
      ooo_return_date: latest_relevant_reply_is_out_of_office ? latest_relevant_reply.out_of_office_return_date : nil
    }
  end

  def latest_relevant_reply_for_summary
    replies
      .where(is_bounce: false, is_warmup: false)
      .order(received_at: :desc, id: :desc)
      .first
  end

  def mark_all_read!
    replies.where(read_at: nil).update_all(read_at: Time.current)
    update!(unread_count: 0)
  end

  def unread_for?(account)
    return false unless last_reply_at.present?
    return true unless account

    read_record = conversation_reads.find_by(account: account)
    return true unless read_record

    last_reply_at > read_record.last_read_at
  end

  def mark_read_for!(account)
    conversation_reads.find_or_initialize_by(account: account).tap do |cr|
      cr.last_read_at = Time.current
      cr.save!
    end
  end

  def reply_to_address
    latest_incoming_from = replies
                           .where(is_warmup: false)
                           .where.not(from_address: [nil, ''])
                           .order(received_at: :desc, created_at: :desc, id: :desc)
                           .first&.from_address

    normalize_participant_address(latest_incoming_from).presence || normalize_participant_address(lead.email)
  end

  def reply_cc_addresses(to_address: reply_to_address)
    excluded_addresses = [reply_mailbox.email, to_address]
    conversation_participant_addresses(excluding: excluded_addresses)
  end

  def reply_mailbox
    replies
      .where(is_warmup: false)
      .includes(:mailbox)
      .order(Arel.sql('COALESCE(replies.received_at, replies.created_at) DESC'), id: :desc)
      .first&.mailbox || mailbox
  end

  def thread_messages
    original_messages = generated_messages_for_thread.map do |msg|
      {
        id: msg.id,
        type: :outgoing,
        source: :generated_message,
        subject: msg.subject,
        to_addresses: nil,
        cc_addresses: nil,
        body_plain: msg.rendered_body_plain,
        body_html: msg.rendered_body_html,
        from_address: msg.mailbox.email,
        attachments: [],
        is_bounce: false,
        is_out_of_office: false,
        message_at: msg.sent_at || msg.created_at
      }
    end

    incoming = replies.where(is_warmup: false).includes(reply_attachments: { file_attachment: :blob }).map do |reply|
      {
        id: reply.id,
        type: :incoming,
        source: :reply,
        subject: reply.subject,
        to_addresses: reply.additional_to_addresses(excluding: reply.mailbox.email).presence,
        cc_addresses: reply.additional_cc_addresses(excluding: reply.mailbox.email).presence,
        body_plain: reply.body_plain_stripped,
        body_html: reply.body_html_stripped,
        calendar_event: reply.calendar_event,
        from_address: reply.from_address,
        attachments: reply.reply_attachments.map do |attachment|
          {
             id: attachment.id,
             original_filename: attachment.original_filename,
             content_type: attachment.content_type,
             file_size_bytes: attachment.file_size_bytes,
             content_id: attachment.content_id,
             file: attachment.file
           }
        end,
        is_bounce: reply.is_bounce,
        is_out_of_office: reply.is_out_of_office,
        message_at: reply.received_at || reply.created_at
      }
    end

    outgoing = sent_replies
               .where(status: 'sent')
               .includes(:reply, sent_reply_attachments: { file_attachment: :blob })
               .map do |sent|
      {
        id: sent.id,
        type: :outgoing,
        source: :sent_reply,
        subject: sent.subject,
        to_addresses: sent_reply_thread_to_addresses(sent),
        cc_addresses: sent.additional_cc_addresses(excluding: sent.mailbox.email).presence,
        body_plain: sent.rendered_body_plain_for(lead: lead),
        body_html: sent.rendered_body_html_for(lead: lead),
        from_address: sent.mailbox.email,
        attachments: sent.sent_reply_attachments.map do |attachment|
          {
             id: attachment.id,
             original_filename: attachment.original_filename,
             content_type: attachment.content_type,
             file_size_bytes: attachment.file_size_bytes,
             content_id: nil,
             file: attachment.file
           }
        end,
        is_bounce: false,
        is_out_of_office: false,
        message_at: sent.sent_at || sent.created_at
      }
    end

    (original_messages + incoming + outgoing).sort_by do |m|
      [m[:message_at] || Time.at(0), m[:type].to_s, m[:id]]
    end
  end

  private

  def generated_messages_for_thread
    # Keep inbox history independent from Agent.not_deleted so soft-deleted campaigns
    # still show the outbound messages that started the conversation.
    scope = GeneratedMessage
            .joins(agent_lead: :lead)
            .includes(:mailbox)
            .where(status: %w[sent replied bounced])

    if agent_lead_id.present?
      scope.where(agent_lead_id: agent_lead_id)
    else
      scope.where(agent_leads: { lead_id: lead_id }).where(mailbox_id: mailbox_id)
    end
  end

  def conversation_participant_addresses(excluding: [])
    excluded_keys = Array(excluding).filter_map do |address|
      normalize_participant_address(address)&.downcase
    end

    dedupe_participant_addresses(conversation_participant_address_candidates).reject do |address|
      excluded_keys.include?(address.downcase)
    end
  end

  def conversation_participant_address_candidates
    candidates = [lead.email]

    replies.where(is_warmup: false).order(:received_at, :created_at, :id).each do |reply|
      candidates << reply.from_address
      candidates.concat(Array(reply.to_addresses))
      candidates.concat(Array(reply.cc_addresses))
    end

    sent_replies.order(:sent_at, :created_at, :id).each do |sent_reply|
      candidates << sent_reply.to_address
      candidates.concat(Array(sent_reply.cc_addresses))
    end

    candidates
  end

  def dedupe_participant_addresses(addresses)
    seen = {}

    Array(addresses).filter_map do |address|
      normalized = normalize_participant_address(address)
      next if normalized.blank?

      dedupe_key = normalized.downcase
      next if seen[dedupe_key]

      seen[dedupe_key] = true
      normalized
    end
  end

  def normalize_participant_address(address)
    address.to_s.strip.presence
  end

  def sent_reply_thread_to_addresses(sent_reply)
    to_address = normalize_participant_address(sent_reply.to_address)
    lead_address = normalize_participant_address(lead.email)

    return nil if to_address.blank? || to_address.casecmp?(lead_address)

    [to_address]
  end
end
