# frozen_string_literal: true

require 'cgi'

# Represents an incoming email reply detected from a lead.
class Reply < ApplicationRecord
  BOUNCE_TYPES = %w[hard soft].freeze
  WARMUP_SERVICES = %w[warmy lemwarm mailwarm warmbox instantly_warmup unknown].freeze

  before_validation :normalize_recipient_addresses
  after_save :refresh_conversation_summary!, if: :conversation_summary_changed?
  after_destroy :refresh_conversation_summary!

  belongs_to :generated_message, optional: true
  belongs_to :lead, optional: true
  belongs_to :mailbox
  belongs_to :conversation, optional: true
  has_many :reply_attachments, dependent: :destroy

  # Validations
  validates :api_message_id, presence: true, uniqueness: true
  validates :from_address, presence: true
  validates :received_at, presence: true
  validates :bounce_type, inclusion: { in: BOUNCE_TYPES }, allow_nil: true
  validate :calendar_event_data_must_be_hash

  scope :unresponded, -> { where(responded: false, requires_response: true) }
  scope :responded, -> { where(responded: true) }
  scope :requires_attention, -> { unresponded.where(is_bounce: false, is_out_of_office: false) }
  scope :bounces, -> { where(is_bounce: true) }
  scope :hard_bounces, -> { bounces.where(bounce_type: 'hard') }
  scope :soft_bounces, -> { bounces.where(bounce_type: 'soft') }
  scope :out_of_office, -> { where(is_out_of_office: true) }
  scope :recent, -> { order(received_at: :desc) }
  scope :for_mailbox, ->(mailbox) { where(mailbox_id: mailbox.id) }
  scope :for_lead, ->(lead) { where(lead_id: lead.id) }
  scope :warmup, -> { where(is_warmup: true) }
  scope :not_warmup, -> { where(is_warmup: false) }
  scope :human, -> { not_warmup.where(is_bounce: false, is_out_of_office: false) }
  scope :unread, -> { where(read_at: nil) }
  scope :read, -> { where.not(read_at: nil) }
  scope :needs_assignment, -> { where(needs_lead_assignment: true) }
  scope :needs_human_assignment, -> { needs_assignment.human }
  scope :assigned, -> { where(needs_lead_assignment: false) }

  def bounce?
    is_bounce
  end

  def hard_bounce?
    is_bounce && bounce_type == 'hard'
  end

  def soft_bounce?
    is_bounce && bounce_type == 'soft'
  end

  def out_of_office?
    is_out_of_office
  end

  def warmup?
    is_warmup
  end

  def human?
    !bounce? && !out_of_office? && !warmup?
  end

  def unread?
    read_at.nil?
  end

  def read?
    read_at.present?
  end

  def responded?
    responded
  end

  def needs_response?
    requires_response && !responded
  end

  # Marks this reply as responded to
  def mark_responded!
    update!(responded: true, responded_at: Time.current)
  end

  def mark_no_response_needed!
    update!(requires_response: false)
  end

  def mark_read!
    return if read?

    update!(read_at: Time.current)
  end

  def body_preview
    text = body_plain_stripped.presence || body_html_stripped&.gsub(/<[^>]*>/, '')
    return nil unless text

    text.strip.truncate(200)
  end

  def body_plain_stripped
    return nil if body_plain.blank?

    strip_plain_text_quotes(body_plain)
  end

  def body_html_stripped
    return nil if body_html.blank?

    strip_html_quotes(body_html)
  end

  def body_plain_for_classification
    body_plain_stripped.presence || body_html_as_plain_text
  end

  def needs_lead_assignment?
    needs_lead_assignment
  end

  def assign_lead!(lead)
    raise ArgumentError, 'Lead cannot be nil' if lead.nil?
    raise ArgumentError, 'Reply already has a lead assigned' if self.lead.present?

    if lead.organization_id != mailbox.organization_id
      raise ArgumentError,
            'Lead must belong to the same organization as the reply mailbox'
    end

    transaction do
      update!(lead: lead, needs_lead_assignment: false)
      ConversationService.find_or_create_for_reply(self)
    end
  end

  def additional_to_addresses(excluding: nil)
    filtered_recipient_addresses(to_addresses, excluding: excluding)
  end

  def additional_cc_addresses(excluding: nil)
    filtered_recipient_addresses(cc_addresses, excluding: excluding)
  end

  def calendar_event
    value = calendar_event_data
    value.is_a?(Hash) && value.present? ? value : nil
  end

  private

  def conversation_summary_changed?
    (previous_changes.keys & %w[
      body_html
      body_plain
      conversation_id
      is_bounce
      is_out_of_office
      is_warmup
      out_of_office_return_date
      read_at
      received_at
    ]).any?
  end

  def refresh_conversation_summary!
    conversation_ids = if previous_changes.key?('conversation_id')
                         previous_changes['conversation_id']
                       else
                         [conversation_id]
                       end

    Conversation.where(id: Array(conversation_ids).compact.uniq).find_each(&:refresh_counters!)
  end

  def calendar_event_data_must_be_hash
    return if calendar_event_data.is_a?(Hash)

    errors.add(:calendar_event_data, 'must be a hash')
  end

  def normalize_recipient_addresses
    self.to_addresses = dedupe_recipient_addresses(to_addresses)
    self.cc_addresses = dedupe_recipient_addresses(cc_addresses)
  end

  def filtered_recipient_addresses(addresses, excluding: nil)
    normalized_exclusion = excluding.to_s.strip.downcase

    dedupe_recipient_addresses(addresses).reject do |address|
      normalized_exclusion.present? && address.casecmp?(normalized_exclusion)
    end
  end

  def dedupe_recipient_addresses(addresses)
    seen = {}

    Array(addresses).filter_map do |address|
      normalized = address.to_s.strip
      next if normalized.blank?

      dedupe_key = normalized.downcase
      next if seen[dedupe_key]

      seen[dedupe_key] = true
      normalized
    end
  end

  def strip_plain_text_quotes(text)
    lines = text.lines
    result_lines = []

    lines.each do |line|
      break if quote_header_start?(line)
      break if line.strip.start_with?('>')
      break if outlook_separator?(line)

      result_lines << line
    end

    result_lines.join.strip
  end

  def quote_header_start?(line)
    line.match?(/^On .+\d{1,2},\s*\d{4}.+[<@]/i) ||
      line.match?(/^On .+ wrote:\s*$/i) ||
      line.match?(/^-{3,}\s*Original Message/i) ||
      line.match?(/^Gesendet:\s*.+/i) ||
      line.match?(/^Sent:\s*.+/i) ||
      line.match?(/^Datum:\s*.+/i) ||
      line.match?(/^Date:\s*.+/i) ||
      line.match?(/^_{5,}\s*$/) ||
      line.match?(/^>{3,}\s*$/)
  end

  def outlook_separator?(line)
    line.match?(/^(From|Von):\s*.+$/i) && line.include?('@')
  end

  def body_html_as_plain_text
    html = body_html_stripped.to_s
    return nil if html.blank?

    document = Nokogiri::HTML(html)
    document.xpath('//comment()').remove
    document.css('script, style, meta, title, head').remove
    document.css('br, p, div, li, tr').each { |node| node.after("\n") }

    strip_plain_text_quotes(normalize_plain_text(CGI.unescapeHTML(document.text))).presence
  end

  def normalize_plain_text(text)
    text.to_s
        .gsub(/\\r\\n?/, "\n")
        .gsub(/\\n/, "\n")
        .gsub(/\u00a0/, ' ')
        .gsub(/\r\n?/, "\n")
        .gsub(/[ \t]+/, ' ')
        .gsub(/ *\n+ */, "\n")
        .gsub(/\n{3,}/, "\n\n")
        .strip
  end

  def strip_html_quotes(html)
    doc = Nokogiri::HTML.fragment(html)

    doc.css('blockquote').remove
    doc.css('.gmail_quote').remove
    doc.css('.gmail_quote_container').remove
    doc.css('.yahoo_quoted').remove
    doc.css('.ms-outlook-quote').remove
    doc.css('[class*="quote"]').each do |node|
      node.remove if node.text.length > 100
    end

    cleaned = doc.to_html.strip
    cleaned.presence
  end
end
