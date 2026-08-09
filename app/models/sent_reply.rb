# frozen_string_literal: true

class SentReply < ApplicationRecord
  STATUSES = %w[draft sending sent failed].freeze

  before_validation :normalize_recipient_addresses
  after_save :refresh_conversation_reply_center_status!, if: :reply_center_status_changed?
  after_destroy :refresh_conversation_reply_center_status!

  belongs_to :conversation
  belongs_to :reply, optional: true
  belongs_to :mailbox
  belongs_to :sent_by, class_name: 'Account'
  has_many :sent_reply_attachments, dependent: :destroy

  validates :subject, presence: true
  validates :to_address, presence: true
  validates :body_plain, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }

  scope :sent, -> { where(status: 'sent') }
  scope :failed, -> { where(status: 'failed') }
  scope :pending, -> { where(status: %w[draft sending]) }

  def draft?
    status == 'draft'
  end

  def sending?
    status == 'sending'
  end

  def sent?
    status == 'sent'
  end

  def failed?
    status == 'failed'
  end

  def mark_sending!
    update!(status: 'sending')
  end

  def mark_sent!(api_message_id:, message_id:)
    update!(
      status: 'sent',
      api_message_id: api_message_id,
      message_id: message_id,
      sent_at: Time.current,
      send_error: nil
    )
  end

  def mark_failed!(error)
    update!(status: 'failed', send_error: error)
  end

  def rendered_body_plain_for(lead:)
    body = body_plain.to_s
    signature_plain = strip_html(rendered_signature_for(lead: lead))

    return body if signature_plain.blank? || body.include?(signature_plain)

    "#{body}\n\n#{signature_plain}"
  end

  def rendered_body_html_for(lead:)
    html = body_html.presence || "<p>#{ERB::Util.html_escape(body_plain.to_s).gsub("\n", '<br>')}</p>"
    signature_html = rendered_signature_for(lead: lead)

    return html if signature_html.blank? || html.include?(signature_html)

    "#{html}<br><br>#{signature_html}"
  end

  def additional_cc_addresses(excluding: nil)
    filtered_recipient_addresses(cc_addresses, excluding: Array(excluding) + [to_address])
  end

  private

  def reply_center_status_changed?
    (previous_changes.keys & %w[conversation_id sent_at status]).any?
  end

  def refresh_conversation_reply_center_status!
    conversation_ids = if previous_changes.key?('conversation_id')
                         previous_changes['conversation_id']
                       else
                         [conversation_id]
                       end

    Conversation.where(id: Array(conversation_ids).compact.uniq).find_each(&:refresh_counters!)
  end

  def normalize_recipient_addresses
    self.to_address = normalize_recipient_address(to_address.presence || conversation&.reply_to_address)
    self.cc_addresses = dedupe_recipient_addresses(cc_addresses)
  end

  def filtered_recipient_addresses(addresses, excluding: nil)
    normalized_exclusions = Array(excluding).filter_map do |address|
      normalize_recipient_address(address)&.downcase
    end

    dedupe_recipient_addresses(addresses).reject do |address|
      normalized_exclusions.include?(address.downcase)
    end
  end

  def normalize_recipient_address(address)
    address.to_s.strip.presence
  end

  def dedupe_recipient_addresses(addresses)
    seen = {}

    Array(addresses).filter_map do |address|
      normalized = normalize_recipient_address(address)
      next if normalized.blank?

      dedupe_key = normalized.downcase
      next if seen[dedupe_key]

      seen[dedupe_key] = true
      normalized
    end
  end

  def rendered_signature_for(lead:)
    return nil unless include_signature?

    sender = mailbox.sender
    return nil if sender.blank?

    sender.rendered_signature_for(lead: lead).presence
  end

  def strip_html(html)
    html.to_s.gsub(/<[^>]*>/, '').gsub(/\s+/, ' ').strip
  end
end
