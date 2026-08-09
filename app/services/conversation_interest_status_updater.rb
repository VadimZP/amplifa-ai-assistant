# frozen_string_literal: true

class ConversationInterestStatusUpdater
  Result = Struct.new(:success?, :error, keyword_init: true)

  MEETING_CREATION_STATUSES = %w[interested meeting_request].freeze
  SUPPORTED_STATUSES = %w[interested meeting_request not_interested wrong_person].freeze

  def initialize(conversation:, target_status:, actor:, reason_context: :reply)
    @conversation = conversation
    @target_status = target_status.to_s
    @actor = actor
    @reason_context = reason_context.to_s.presence&.to_sym || :reply
  end

  def call
    unless SUPPORTED_STATUSES.include?(@target_status)
      return failure('Interest status can only be changed between Interested, Meeting Request, Not Interested, ' \
                     'and Wrong Person.')
    end
    if conversation.interest_status.present? && !Conversation::INTEREST_STATUSES.include?(conversation.interest_status)
      return failure('Only valid conversation interest statuses can be manually changed.')
    end
    return success if conversation.interest_status == @target_status

    ActiveRecord::Base.transaction do
      meeting_creation_status? ? ensure_meeting_for_positive_interest! : remove_associated_meeting!
      conversation.update!(interest_status: @target_status)
      sync_blacklist_reason_data!
    end

    success
  rescue ActiveRecord::RecordInvalid => e
    failure(e.record.errors.full_messages.to_sentence.presence || e.message)
  rescue StandardError => e
    failure(e.message)
  end

  private

  attr_reader :conversation, :actor

  def manual_reason?
    @reason_context == :manual
  end

  def ensure_meeting_for_positive_interest!
    agent_lead = resolve_agent_lead!
    return if latest_active_meeting_for(agent_lead).present?

    agent_lead.schedule_meeting!(
      status: 'scheduling',
      notes: meeting_creation_note
    )
  end

  def meeting_creation_status?
    @target_status.in?(MEETING_CREATION_STATUSES)
  end

  def meeting_creation_note
    @target_status == 'meeting_request' ? 'Auto-created from meeting request' : 'Auto-created from interested reply'
  end

  def remove_associated_meeting!
    agent_lead = resolve_agent_lead
    return if agent_lead.nil?

    meeting = latest_active_meeting_for(agent_lead)
    return if meeting.nil?

    if actor&.amplifa_admin?
      meeting.destroy!
    else
      meeting.mark_pending_removal!
    end

    return unless agent_lead.meetings.where.not(status: %w[cancelled pending_removal]).none?

    agent_lead.update!(meeting_booked_at: nil, meeting_notes: nil)
  end

  def resolve_agent_lead!
    resolve_agent_lead || raise('No matching campaign lead found for this conversation.')
  end

  def resolve_agent_lead
    by_generated_message = AgentLead
                           .joins(:generated_messages, :agent)
                           .where(lead_id: conversation.lead_id)
                           .where(agents: { organization_id: conversation.organization_id })
                           .where(generated_messages: { mailbox_id: conversation.mailbox_id, status: 'sent' })
                           .order(Arel.sql('generated_messages.sent_at DESC NULLS LAST, generated_messages.id DESC'))
                           .first
    return by_generated_message if by_generated_message

    return nil if conversation.agent_id.blank?

    AgentLead
      .joins(:agent)
      .where(agent_id: conversation.agent_id, lead_id: conversation.lead_id)
      .where(agents: { organization_id: conversation.organization_id })
      .first
  end

  def latest_active_meeting_for(agent_lead)
    agent_lead.meetings.where.not(status: %w[cancelled pending_removal]).order(created_at: :desc).first
  end

  def sync_blacklist_reason_data!
    lead = conversation.lead
    return if lead.email.blank?

    reason = Blacklist.reply_interest_reason(@target_status, manual: manual_reason?)

    lead.blacklist!(
      reason: reason,
      category: Blacklist.reply_interest_reason_category(@target_status)
    )
    Blacklist.upsert_reply_interest_entry!(lead: lead, interest_status: @target_status, actor: actor, reason: reason)
  end

  def success
    Result.new(success?: true, error: nil)
  end

  def failure(message)
    Result.new(success?: false, error: message)
  end
end
