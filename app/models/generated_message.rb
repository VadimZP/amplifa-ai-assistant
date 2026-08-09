# frozen_string_literal: true

# Stores AI-generated messages for each agent-lead-step combination.
class GeneratedMessage < ApplicationRecord
  CURRENT_AGENT_LEAD_RUN_SQL = <<~SQL.squish.freeze
    generated_messages.agent_lead_run_id = agent_leads.current_agent_lead_run_id OR
    (generated_messages.agent_lead_run_id IS NULL AND agent_leads.current_agent_lead_run_id IS NULL)
  SQL

  # Constants
  STATUSES = %w[draft approved scheduled sent failed bounced replied].freeze
  BOUNCE_TYPES = %w[hard soft].freeze
  MESSAGE_KINDS = %w[sequence welcome_back].freeze

  # Associations
  belongs_to :agent_lead
  belongs_to :agent_lead_run, optional: true
  belongs_to :sequence_step, optional: true
  belongs_to :mailbox, optional: true
  has_many :replies, dependent: :nullify

  before_validation :assign_current_agent_lead_run

  # Delegates for convenience
  delegate :lead, to: :agent_lead
  delegate :agent, to: :agent_lead

  # Validations
  validates :agent_lead, presence: true
  validates :message_kind, presence: true, inclusion: { in: MESSAGE_KINDS }
  validates :sequence_step, presence: true, if: -> { sequence_message? }
  validates :body, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :sequence_step_id, uniqueness: { scope: :agent_lead_run_id, message: 'already has a message for this step' },
                               if: -> { agent_lead_run_id.present? && sequence_step_id.present? }
  validates :sequence_step_id, uniqueness: { scope: :agent_lead_id, message: 'already has a message for this step' },
                               unless: -> { agent_lead_run_id.present? || sequence_step_id.blank? }
  validates :subject, presence: true, if: -> { welcome_back? || sequence_step&.email? }
  validates :scheduled_for, presence: true, if: -> { welcome_back? }

  validate :same_agent
  validate :agent_lead_run_matches_agent_lead

  # Scopes
  scope :drafts, -> { where(status: 'draft') }
  scope :approved, -> { where(status: 'approved') }
  scope :scheduled, -> { where(status: 'scheduled') }
  scope :sent, -> { where(status: 'sent') }
  scope :failed, -> { where(status: 'failed') }

  scope :for_agent, ->(agent) { joins(:agent_lead).where(agent_leads: { agent_id: agent.id }) }
  scope :for_step, ->(step) { where(sequence_step_id: step.id) }
  scope :for_lead, ->(lead) { joins(:agent_lead).where(agent_leads: { lead_id: lead.id }) }
  scope :for_mailbox, ->(mailbox) { where(mailbox_id: mailbox.id) }
  scope :test_sent, -> { where.not(test_sent_at: nil) }
  scope :not_test_sent, -> { where(test_sent_at: nil) }
  scope :sent_today, -> { where(sent_at: Time.current.beginning_of_day..Time.current.end_of_day) }
  scope :bounced, -> { where.not(bounced_at: nil) }

  scope :sequence_messages, -> { where(message_kind: 'sequence') }
  scope :welcome_back_messages, -> { where(message_kind: 'welcome_back') }

  # Sample scopes
  scope :samples, -> { where(sample: true) }
  scope :non_samples, -> { where(sample: false) }
  scope :for_current_agent_lead_run, -> { joins(:agent_lead).where(CURRENT_AGENT_LEAD_RUN_SQL) }
  scope :samples_for_agent, lambda { |agent|
    samples
      .joins(agent_lead: :lead)
      .where(agent_leads: { agent_id: agent.id }, leads: { blacklisted: false })
      .where(CURRENT_AGENT_LEAD_RUN_SQL)
  }

  # Status predicates
  def draft?
    status == 'draft'
  end

  def approved?
    status == 'approved'
  end

  def scheduled?
    status == 'scheduled'
  end

  def sent?
    status == 'sent'
  end

  def failed?
    status == 'failed'
  end

  def bounced?
    status == 'bounced'
  end

  def replied?
    status == 'replied'
  end

  def sequence_message?
    message_kind == 'sequence'
  end

  def welcome_back?
    message_kind == 'welcome_back'
  end

  # Approves this message for sending
  def approve!
    update!(status: 'approved')
  end

  # Marks the message as edited and stores originals
  def mark_edited!(new_subject, new_body)
    unless manually_edited?
      self.original_subject = subject
      self.original_body = body
    end

    self.subject = new_subject
    self.body = new_body
    self.manually_edited = true
    save!
  end

  # Reverts to original AI-generated content
  def revert_to_original!
    return unless manually_edited?

    self.subject = original_subject
    self.body = original_body
    self.manually_edited = false
    self.original_subject = nil
    self.original_body = nil
    save!
  end

  # Records when a test email was sent
  def record_test_send!(email)
    update!(test_sent_at: Time.current, test_sent_to: email)
  end

  # Estimates the cost of generation based on tokens
  def generation_cost_estimate
    return nil unless input_tokens.present? && output_tokens.present?

    # Rough estimate for Gemini 2.5 Flash Lite pricing
    # Input: ~$0.075/million, Output: ~$0.30/million
    input_cost = (input_tokens / 1_000_000.0) * 0.075
    output_cost = (output_tokens / 1_000_000.0) * 0.30
    (input_cost + output_cost).round(6)
  end

  # Records a successful send via API
  def record_send!(new_message_id)
    update!(
      status: 'sent',
      sent_at: Time.current,
      message_id: new_message_id,
      last_send_error: nil
    )
  end

  # Records a bounce
  def record_bounce!(reason, type = 'hard')
    update!(
      status: 'bounced',
      bounced_at: Time.current,
      bounce_reason: reason,
      bounce_type: type
    )
  end

  # Checks if this message has bounced
  def email_bounced?
    bounced_at.present?
  end

  # Checks if this message is a hard bounce
  def hard_bounce?
    email_bounced? && bounce_type == 'hard'
  end

  # Checks if this message is a soft bounce
  def soft_bounce?
    email_bounced? && bounce_type == 'soft'
  end

  def body_with_signature
    sender = sender_for_signature
    return body if sender.blank?

    signature = if agent_lead
                  sender.rendered_signature_for(lead: agent_lead.lead, agent: agent, agent_lead: agent_lead)
                else
                  sender.rendered_signature
                end

    return body if signature.blank?

    "#{body}\n\n#{signature}"
  end

  def rendered_body_plain
    plain_body = body.to_s
    plain_signature = strip_html(rendered_signature)

    return plain_body if plain_signature.blank? || plain_body.include?(plain_signature)

    "#{plain_body}\n\n#{plain_signature}"
  end

  def rendered_body_html
    body_html = "<p>#{ERB::Util.html_escape(body.to_s).gsub("\n", '<br>')}</p>"
    html_signature = rendered_signature

    return body_html if html_signature.blank? || body_html.include?(html_signature)

    "#{body_html}<br><br>#{html_signature}"
  end

  def sender_for_signature
    agent_lead&.assigned_mailbox&.sender || agent&.mailboxes&.joins(:sender)&.first&.sender
  end

  # Increments send attempt counter
  def increment_send_attempt!(error_message = nil)
    update!(
      send_attempts: send_attempts + 1,
      last_send_error: error_message
    )
  end

  private

  def rendered_signature
    sender = mailbox&.sender || sender_for_signature
    return nil if sender.blank?

    if agent_lead
      sender.rendered_signature_for(lead: agent_lead.lead, agent: agent, agent_lead: agent_lead)
    else
      sender.rendered_signature
    end.presence
  end

  def strip_html(html)
    html.to_s.gsub(/<[^>]*>/, '').gsub(/&nbsp;/, ' ').gsub(/&amp;/, '&').gsub(/\s+/, ' ').strip
  end

  def same_agent
    return unless agent_lead.present? && sequence_step.present?

    return if sequence_step.available_to_agent?(agent_lead.agent)

    errors.add(:base, 'AgentLead and SequenceStep must belong to the same Agent')
  end

  def assign_current_agent_lead_run
    return if agent_lead_run_id.present? || agent_lead.blank?

    self.agent_lead_run = agent_lead.current_agent_lead_run if agent_lead.current_agent_lead_run_id.present?
  end

  def agent_lead_run_matches_agent_lead
    return unless agent_lead.present? && agent_lead_run.present?
    return if agent_lead_run.agent_lead_id == agent_lead.id

    errors.add(:agent_lead_run, 'must belong to the same agent lead')
  end
end
