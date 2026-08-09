# frozen_string_literal: true

class Agent < ApplicationRecord
  has_paper_trail on: [:update]

  # Constants
  STATUSES = %w[draft ready active paused completed deleted].freeze
  VISIBLE_STATUSES = (STATUSES - %w[deleted]).freeze
  LOCALES = SupportedLocale::ALL
  DEFAULT_LLM_MODEL = 'deepseek/deepseek-v4-pro'
  before_destroy :ensure_no_conversations

  # Associations
  belongs_to :organization
  belongs_to :playbook, optional: true
  belongs_to :global_sequence, optional: true
  belongs_to :created_by, class_name: 'Account'
  belongs_to :samples_approved_by, class_name: 'Account', optional: true
  has_many :agent_leads, dependent: :destroy
  has_many :leads, through: :agent_leads
  has_many :agent_mailboxes, dependent: :destroy
  has_many :mailboxes, through: :agent_mailboxes
  has_many :lead_imports, dependent: :nullify
  has_many :conversations, dependent: :nullify
  has_many :sequence_steps, dependent: :destroy
  has_many :generated_messages, through: :agent_leads
  has_many :meetings, dependent: :destroy

  # Validations
  validates :name, presence: true
  validates :organization, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :locale, presence: true, inclusion: { in: LOCALES }
  validates :default_timezone, presence: true
  validates :sample_count, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 200 }
  validates :buying_signals_lookback_days, numericality: { only_integer: true, greater_than: 0 }
  validate :default_timezone_is_valid_iana
  validate :playbook_belongs_to_organization
  validate :playbook_must_be_approved, if: -> { playbook.present? && status_changed_to_ready_or_active? }
  validate :deleted_status_requires_deleted_at

  # Scopes
  scope :for_organization, ->(org) { where(organization_id: org.id) }
  scope :draft, -> { where(status: 'draft') }
  scope :ready, -> { where(status: 'ready') }
  scope :active, -> { where(status: 'active') }
  scope :paused, -> { where(status: 'paused') }
  scope :completed, -> { where(status: 'completed') }
  scope :not_deleted, -> { where.not(status: 'deleted') }
  scope :recent, -> { order(created_at: :desc) }

  def effective_sequence_steps
    steps = global_sequence_id.present? ? global_sequence.sequence_steps : sequence_steps
    steps.not_archived
  end

  def active_email_sequence_steps
    effective_sequence_steps.active.email_steps
  end

  def using_global_sequence?
    global_sequence_id.present?
  end

  # Returns true if this agent can be launched (has leads, mailboxes, and approved playbook)
  def can_launch?
    return false if deleted?

    leads.exists? && mailboxes.active.exists? && playbook&.approved? && samples_approved?
  end

  # Calculates the reply rate as a percentage
  def reply_rate
    return 0.0 if contacted_count.zero?

    (replied_count.to_f / contacted_count * 100).round(1)
  end

  # Returns the count of meetings from the Meeting model.
  # This replaces the legacy meetings_booked_count counter column.
  def meetings_count
    meetings.count
  end

  # Calculates the meeting rate as a percentage
  def meeting_rate
    return 0.0 if contacted_count.zero?

    (meetings_count.to_f / contacted_count * 100).round(1)
  end

  # Returns meetings grouped by status
  def meetings_by_status
    meetings.group(:status).count
  end

  # Returns upcoming scheduled meetings
  def upcoming_meetings
    meetings.upcoming
  end

  # Returns completed meetings
  def completed_meetings
    meetings.completed
  end

  # Returns true if this agent is a draft
  def draft?
    status == 'draft'
  end

  # Returns true if this agent is ready to launch
  def ready?
    status == 'ready'
  end

  # Returns true if this agent is actively running
  def active?
    status == 'active'
  end

  # Returns true if this agent is paused
  def paused?
    status == 'paused'
  end

  # Returns true if this agent has completed
  def completed?
    status == 'completed'
  end

  def deleted?
    status == 'deleted'
  end

  def mark_deleted!
    transaction do
      agent_leads.update_all(send_in_progress_at: nil, updated_at: Time.current)
      update!(status: 'deleted', deleted_at: Time.current, paused_at: Time.current, scheduled_launch_at: nil)
    end
  end

  # Returns the sample agent_leads (first N by created_at)
  def sample_agent_leads
    visible_agent_leads = sample_generation_agent_leads
    tracked_ids = current_run_generated_messages_for(visible_agent_leads).where(sample: true).distinct.pluck(:agent_lead_id)
    tracked_ids += visible_agent_leads.where(status: %w[generating error]).pluck(:id)
    tracked_ids = tracked_ids.uniq

    return visible_agent_leads.sample_leads(sample_count) if tracked_ids.empty?

    tracked_visible_ids = visible_agent_leads.where(id: tracked_ids).order(created_at: :asc, id: :asc).pluck(:id)
    return visible_agent_leads.sample_leads(sample_count) if tracked_visible_ids.empty?

    remaining_slots = sample_count - tracked_visible_ids.size
    if remaining_slots.positive?
      top_up_ids = visible_agent_leads.where.not(id: tracked_visible_ids).sample_leads(remaining_slots).pluck(:id)
      tracked_visible_ids += top_up_ids
    end

    visible_agent_leads.where(id: tracked_visible_ids).order(created_at: :asc, id: :asc)
  end

  # Returns generated messages for sample leads
  def sample_messages
    GeneratedMessage.samples_for_agent(self)
  end

  def sample_generation_agent_leads
    eligible_agent_leads = agent_leads.joins(:lead).merge(Lead.not_blacklisted)
    non_sample_message_lead_ids = current_run_generated_messages_for(eligible_agent_leads)
                                  .where(sample: false)
                                  .where(sequence_step: active_email_sequence_steps)
                                  .select(:agent_lead_id)

    eligible_agent_leads.where.not(id: non_sample_message_lead_ids)
  end

  # Returns true if samples have been generated
  def samples_generated?
    samples_generated_at.present?
  end

  # Returns true if samples have been approved
  def samples_approved?
    samples_approved_at.present?
  end

  # Returns true if this agent is ready for sample generation
  def ready_for_sample_generation?
    leads.exists? && active_email_sequence_steps.exists?
  end

  # Marks samples as generated
  def mark_samples_generated!
    update!(samples_generated_at: Time.current)
  end

  # Marks samples as approved and also approves the sample messages themselves.
  # This allows the full generation to proceed knowing the approach was validated.
  def mark_samples_approved!(account)
    transaction do
      update!(samples_approved_at: Time.current, samples_approved_by: account)
      # Approve all draft sample messages
      sample_messages.where(status: 'draft').update_all(status: 'approved')
    end
  end

  # Resets sample approval (for regeneration)
  def reset_sample_approval!
    update!(
      samples_generated_at: nil,
      samples_approved_at: nil,
      samples_approved_by: nil
    )
  end

  # Campaign launch methods

  # Checks if this agent has been launched
  def launched?
    launched_at.present?
  end

  # Checks if agent is ready to launch (has mailboxes and sequence steps)
  def ready_to_launch?
    return false if deleted?

    mailboxes.active.exists? && active_email_sequence_steps.exists? && samples_approved?
  end

  # Launches the campaign
  # Note: Leads remain 'not_contacted' until their first email is actually sent.
  # They transition to 'in_sequence' when ApiEmailSender successfully delivers.
  def launch!
    return if deleted?

    update!(status: 'active', launched_at: Time.current)
  end

  # Pauses the campaign - stops all sends but preserves schedule
  def pause!
    return if deleted? || !active?

    update!(status: 'paused', paused_at: Time.current)
  end

  # Resumes a paused campaign
  def resume!
    return if deleted? || !paused?

    update!(status: 'active', paused_at: nil)
  end

  def restart_leads!(restarted_by: nil)
    restartable_agent_leads.find_each.sum do |agent_lead|
      agent_lead.restart_sequence!(restarted_by: restarted_by)
      1
    end
  end

  # Returns true if the campaign can be paused
  def can_pause?
    launched? && active?
  end

  # Returns true if the campaign can be resumed
  def can_resume?
    launched? && paused?
  end

  # Returns total pro-rata daily send cap across all assigned mailboxes.
  # Divides each mailbox's daily_send_limit by the number of active+launched agents sharing it.
  def daily_send_cap
    eligible_mailboxes = mailboxes.active.warmup_complete.where.not(sender_id: nil).to_a
    sharer_counts = active_launched_sharer_counts(eligible_mailboxes)

    eligible_mailboxes.sum do |mailbox|
      active_agent_count = [sharer_counts[mailbox.id].to_i, 1].max
      (mailbox.daily_send_limit.to_f / active_agent_count).floor
    end
  end

  # Returns total available capacity across all assigned mailboxes
  # Divides each mailbox's capacity by the number of active+launched agents sharing it
  def available_mailbox_capacity(mailboxes: nil)
    eligible_mailboxes = if mailboxes
                           Array(mailboxes).select do |mailbox|
                             mailbox.active? && mailbox.warmup_complete? && mailbox.sender_id.present?
                           end
                         else
                           self.mailboxes.active.warmup_complete.where.not(sender_id: nil).to_a
                         end

    sharer_counts = active_launched_sharer_counts(eligible_mailboxes)

    eligible_mailboxes.sum do |mailbox|
      active_agent_count = [sharer_counts[mailbox.id].to_i, 1].max
      (mailbox.daily_capacity_remaining.to_f / active_agent_count).floor
    end
  end

  # Returns count of mailboxes eligible for sending
  def sendable_mailbox_count
    mailboxes.active.warmup_complete.where.not(sender_id: nil).count
  end

  def buying_signals_available?
    !deleted? && buying_signals_enabled?
  end

  # Returns count of leads with scheduled sends today
  def scheduled_sends_today
    agent_leads.sendable.where(
      'next_send_at >= ? AND next_send_at <= ?',
      Time.current.beginning_of_day,
      Time.current.end_of_day
    ).count
  end

  private

  def restartable_agent_leads
    agent_leads.joins(:lead)
               .where.not(delivery_status: 'replied')
               .merge(Lead.not_blacklisted)
  end

  def current_run_generated_messages_for(agent_leads_scope)
    GeneratedMessage.joins(:agent_lead)
                    .where(agent_leads: { id: agent_leads_scope.select(:id) })
                    .where(
                      'generated_messages.agent_lead_run_id = agent_leads.current_agent_lead_run_id OR ' \
                      '(generated_messages.agent_lead_run_id IS NULL AND agent_leads.current_agent_lead_run_id IS NULL)'
                    )
  end

  def playbook_belongs_to_organization
    return unless playbook.present?

    return unless playbook.organization_id != organization_id

    errors.add(:playbook, 'must belong to the same organization')
  end

  def playbook_must_be_approved
    return unless playbook.present?

    return if playbook.approved?

    errors.add(:playbook, 'must be approved before the agent can be made ready or active')
  end

  def status_changed_to_ready_or_active?
    status_changed? && %w[ready active].include?(status)
  end

  def default_timezone_is_valid_iana
    return if default_timezone.blank?

    begin
      ActiveSupport::TimeZone[default_timezone] || TZInfo::Timezone.get(default_timezone)
    rescue TZInfo::InvalidTimezoneIdentifier
      errors.add(:default_timezone, 'must be a valid IANA timezone identifier')
    end
  end

  def deleted_status_requires_deleted_at
    return unless deleted? && deleted_at.blank?

    errors.add(:status, 'must be changed via agent removal')
  end

  def ensure_no_conversations
    return unless conversations.exists?

    errors.add(:base, 'Cannot delete agent with associated conversations')
    throw :abort
  end

  def active_launched_sharer_counts(eligible_mailboxes)
    mailbox_ids = eligible_mailboxes.map(&:id)
    return {} if mailbox_ids.empty?

    AgentMailbox.joins(:agent)
                .where(mailbox_id: mailbox_ids)
                .merge(Agent.active.where.not(launched_at: nil))
                .group(:mailbox_id)
                .count
  end
end
