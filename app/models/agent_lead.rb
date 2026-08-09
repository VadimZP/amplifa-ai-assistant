# frozen_string_literal: true

# Junction table linking agents to leads, extended with sequence tracking.
class AgentLead < ApplicationRecord
  # Constants
  STATUSES = %w[pending generating generated paused error].freeze
  DELIVERY_STATUSES = %w[not_contacted in_sequence paused replied bounced completed].freeze
  SEND_RESERVATION_TIMEOUT = 30.minutes
  # Associations
  belongs_to :agent
  belongs_to :lead
  belongs_to :assigned_mailbox, class_name: 'Mailbox', optional: true
  belongs_to :current_agent_lead_run, class_name: 'AgentLeadRun', optional: true
  has_many :generated_messages, dependent: :destroy
  has_many :agent_lead_runs, dependent: :destroy
  has_many :meetings, dependent: :destroy

  after_create :ensure_current_run!
  before_destroy :clear_current_agent_lead_run, prepend: true

  # Validations
  validates :agent, presence: true
  validates :lead, presence: true
  validates :lead_id, uniqueness: { scope: :agent_id, message: 'is already assigned to this agent' }
  validates :sequence_position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :delivery_status, presence: true, inclusion: { in: DELIVERY_STATUSES }

  # Custom validation to ensure agent and lead belong to same organization
  validate :same_organization
  validate :assigned_mailbox_same_organization

  # Scopes
  scope :for_agent, ->(agent) { where(agent_id: agent.id) }
  scope :for_lead, ->(lead) { where(lead_id: lead.id) }
  scope :recent, -> { order(created_at: :desc) }

  # Status scopes
  scope :pending, -> { where(status: 'pending') }
  scope :generating, -> { where(status: 'generating') }
  scope :generated, -> { where(status: 'generated') }
  scope :paused, -> { where(status: 'paused') }
  scope :with_errors, -> { where(status: 'error') }
  scope :ready_for_generation, -> { where(status: %w[pending error]) }
  scope :at_position, ->(pos) { where(sequence_position: pos) }

  # Sample leads scope - first N by created_at (not random)
  scope :sample_leads, ->(count) { order(created_at: :asc, id: :asc).limit(count) }

  # Delivery status scopes
  scope :not_contacted, -> { where(delivery_status: 'not_contacted') }
  scope :in_sequence, -> { where(delivery_status: 'in_sequence') }
  scope :delivery_paused, -> { where(delivery_status: 'paused') }
  scope :replied, -> { where(delivery_status: 'replied') }
  scope :bounced, -> { where(delivery_status: 'bounced') }
  scope :delivery_completed, -> { where(delivery_status: 'completed') }
  # Sendable: leads eligible to receive emails (not_contacted waiting for first, or in_sequence for follow-ups)
  scope :sendable, -> { where(delivery_status: %w[not_contacted in_sequence]) }
  scope :stale_sent_progression, lambda {
    joins(generated_messages: :sequence_step)
      .merge(GeneratedMessage.sent)
      .where(delivery_status: %w[not_contacted in_sequence])
      .where(sequence_steps: { archived: false })
      .where(
        'generated_messages.agent_lead_run_id = agent_leads.current_agent_lead_run_id OR ' \
        '(generated_messages.agent_lead_run_id IS NULL AND agent_leads.current_agent_lead_run_id IS NULL)'
      )
      .where(
        'sequence_steps.position > agent_leads.sequence_position OR ' \
        '(sequence_steps.position = agent_leads.sequence_position AND agent_leads.next_send_at IS NULL)'
      )
      .distinct
  }
  scope :ready_to_send, lambda {
    sendable
      .joins(:lead)
      .merge(Lead.effectively_not_blacklisted)
      .where('agent_leads.next_send_at <= ?', Time.current)
      .where(
        'agent_leads.send_in_progress_at IS NULL OR agent_leads.send_in_progress_at < ?',
        Time.current - SEND_RESERVATION_TIMEOUT
      )
  }
  scope :needs_scheduling, -> { sendable.where(next_send_at: nil) }

  # Meeting tracking scopes
  scope :with_meeting, -> { where.not(meeting_booked_at: nil) }
  scope :without_meeting, -> { where(meeting_booked_at: nil) }

  # Status predicates
  def pending?
    status == 'pending'
  end

  def generating?
    status == 'generating'
  end

  def generated?
    status == 'generated'
  end

  def paused?
    status == 'paused'
  end

  def error?
    status == 'error'
  end

  # Returns the current sequence step for this lead
  def current_step
    return nil if sequence_position.zero?

    agent.effective_sequence_steps.find_by(position: sequence_position)
  end

  # Returns the next sequence step for this lead
  def next_step
    agent.effective_sequence_steps.active.where('position > ?', sequence_position).order(position: :asc).first
  end

  # Advances the lead to the next position in the sequence
  def advance_position!
    next_active = agent.effective_sequence_steps.active.where('position > ?', sequence_position).order(position: :asc).first
    if next_active
      update!(sequence_position: next_active.position)
    else
      max_pos = agent.effective_sequence_steps.maximum(:position) || 0
      update!(sequence_position: max_pos + 1) if sequence_position < max_pos
    end
  end

  def advance_after_send!(sent_at:)
    next_active = agent.effective_sequence_steps.active.where('position > ?', sequence_position).order(position: :asc).first

    if next_active
      next_send_time = sent_at + next_active.delay_days.days
      update!(sequence_position: next_active.position, next_send_at: next_send_time)
    else
      max_pos = agent.effective_sequence_steps.maximum(:position) || 0
      update!(sequence_position: max_pos + 1) if sequence_position < max_pos
    end
  end

  def reconcile_sent_message!(message)
    raise ArgumentError, 'message must belong to agent lead' unless message.agent_lead_id == id
    raise ArgumentError, 'message must be sent before reconciliation' unless message.sent?

    authoritative_message = authoritative_sent_message(reference_message: message)
    sent_at = authoritative_message.sent_at || Time.current
    authoritative_position = authoritative_message.sequence_step.position
    desired_next_send_at = sent_at + authoritative_message.sequence_step.delay_days.days
    changed = false

    transaction do
      desired_last_sent_at = [last_sent_at, sent_at].compact.max
      lead_updates = {}
      lead_updates[:delivery_status] = 'in_sequence' unless delivery_status == 'in_sequence'
      lead_updates[:last_sent_at] = desired_last_sent_at if last_sent_at != desired_last_sent_at
      if sequence_position < authoritative_position
        lead_updates[:sequence_position] = authoritative_position
        lead_updates[:next_send_at] = desired_next_send_at
      elsif sequence_position == authoritative_position && next_send_at.nil?
        lead_updates[:next_send_at] = desired_next_send_at
      end

      if lead_updates.any?
        update!(lead_updates)
        changed = true
      end
    end

    changed
  end

  # Marks this lead as currently generating messages
  def mark_generating!
    update!(status: 'generating', generation_error: nil)
  end

  # Marks this lead as having completed message generation
  def mark_generated!
    update!(status: 'generated', last_generated_at: Time.current, generation_error: nil)
  end

  # Marks this lead as having an error during generation
  def mark_error!(error_message)
    update!(status: 'error', generation_error: error_message)
  end

  # Resets the lead for regeneration
  def reset_for_regeneration!
    update!(status: 'pending', sequence_position: 0, generation_error: nil)
  end

  def current_run_generated_messages
    if current_agent_lead_run_id.present?
      generated_messages.where(agent_lead_run_id: current_agent_lead_run_id)
    else
      generated_messages.where(agent_lead_run_id: nil)
    end
  end

  def current_run_message_for(sequence_step)
    current_run_generated_messages.find_by(sequence_step: sequence_step)
  end

  def current_run_message_exists_for?(sequence_step)
    current_run_generated_messages.exists?(sequence_step: sequence_step)
  end

  def current_run_message_attributes
    return {} unless current_agent_lead_run_id.present?

    { agent_lead_run: current_agent_lead_run }
  end

  def ensure_current_run!
    return current_agent_lead_run if current_agent_lead_run.present?

    existing_active_run = agent_lead_runs.active.order(run_number: :desc).first
    if existing_active_run
      update_column(:current_agent_lead_run_id, existing_active_run.id)
      return existing_active_run
    end

    run = agent_lead_runs.create!(
      run_number: next_agent_lead_run_number,
      status: 'active',
      assigned_mailbox: assigned_mailbox,
      started_at: Time.current
    )
    update_column(:current_agent_lead_run_id, run.id)
    run
  end

  def restart_sequence!(restarted_by: nil, restart_reason: nil)
    with_lock do
      timestamp = Time.current
      current_agent_lead_run&.update!(status: 'restarted', ended_at: timestamp)
      new_run = agent_lead_runs.create!(
        run_number: next_agent_lead_run_number,
        status: 'active',
        started_at: timestamp,
        restarted_by: restarted_by,
        restart_reason: restart_reason
      )

      update!(
        current_agent_lead_run: new_run,
        status: 'pending',
        assigned_mailbox: nil,
        delivery_status: 'not_contacted',
        sequence_position: 0,
        next_send_at: nil,
        last_sent_at: nil,
        send_in_progress_at: nil,
        generation_error: nil
      )

      new_run
    end
  end

  # Delivery status predicates
  def not_contacted?
    delivery_status == 'not_contacted'
  end

  def in_sequence?
    delivery_status == 'in_sequence'
  end

  def sendable?
    %w[not_contacted in_sequence].include?(delivery_status)
  end

  def delivery_paused?
    delivery_status == 'paused'
  end

  def delivery_replied?
    delivery_status == 'replied'
  end

  def delivery_bounced?
    delivery_status == 'bounced'
  end

  def delivery_completed?
    delivery_status == 'completed'
  end

  # Delivery status transitions
  def start_sequence!
    update!(delivery_status: 'in_sequence')
  end

  def pause_delivery!
    update!(delivery_status: 'paused')
  end

  def resume_delivery!
    update!(delivery_status: 'in_sequence')
  end

  def mark_replied!
    update!(delivery_status: 'replied')
  end

  def mark_delivery_bounced!
    update!(delivery_status: 'bounced')
  end

  def mark_delivery_completed!
    update!(delivery_status: 'completed')
  end

  # Updates the next send time
  def schedule_next_send!(time)
    update!(next_send_at: time)
  end

  # Records a reschedule due to mailbox cooldown and updates next send time
  def record_cooldown_reschedule!(rescheduled_to_at)
    update!(
      reschedule_count: reschedule_count + 1,
      last_rescheduled_at: Time.current,
      last_rescheduled_to_at: rescheduled_to_at,
      next_send_at: rescheduled_to_at
    )
  end

  # Records when an email was sent
  def record_send!
    update!(last_sent_at: Time.current, next_send_at: nil)
  end

  # Meeting tracking predicate - returns true if any active (non-cancelled) meeting exists
  def meeting_booked?
    meetings.where.not(status: 'cancelled').exists? || meeting_booked_at.present?
  end

  # Returns true if there's an upcoming (scheduled) meeting
  def has_upcoming_meeting?
    meetings.scheduled.upcoming.exists?
  end

  # Returns the most recent meeting
  def latest_meeting
    meetings.order(created_at: :desc).first
  end

  # Creates a new Meeting record for this lead.
  # This is the preferred way to book meetings (replaces mark_meeting!)
  def schedule_meeting!(
    meeting_type: nil,
    scheduled_at: nil,
    duration_minutes: nil,
    location: nil,
    notes: nil,
    status: nil
  )
    resolved_status = status.presence || (scheduled_at&.future? ? 'scheduled' : 'completed')
    resolved_scheduled_at = scheduled_at
    resolved_scheduled_at ||= Time.current unless resolved_status == 'scheduling'

    transaction do
      meeting = meetings.create!(
        lead: lead,
        agent: agent,
        meeting_type: meeting_type,
        scheduled_at: resolved_scheduled_at,
        duration_minutes: duration_minutes,
        location: location,
        notes: notes,
        status: resolved_status
      )

      # Also set legacy flag for backward compatibility
      update!(meeting_booked_at: Time.current, meeting_notes: notes)

      meeting
    end
  end

  # Legacy method: Marks this lead as having a meeting booked.
  # Creates a Meeting record and sets the legacy flag.
  # DEPRECATED: Use schedule_meeting! instead for full meeting features.
  def mark_meeting!(notes: nil)
    schedule_meeting!(notes: notes)
  end

  # Cancels the most recent modifiable meeting and clears the legacy flag.
  # If no modifiable meeting exists, just clears the legacy flag.
  def unmark_meeting!
    transaction do
      latest = latest_meeting
      latest.mark_cancelled! if latest&.modifiable?
      # Always clear the legacy flag for backward compatibility
      update!(meeting_booked_at: nil, meeting_notes: nil)
    end
  end

  private

  def authoritative_sent_message(reference_message:)
    current_run_generated_messages
      .sent
      .joins(:sequence_step)
      .where(sequence_steps: { archived: false })
      .order(
        Arel.sql(
          'sequence_steps.position DESC, generated_messages.sent_at DESC NULLS LAST, generated_messages.id DESC'
        )
      )
      .first || reference_message
  end

  def next_agent_lead_run_number
    last_run_number = agent_lead_runs.maximum(:run_number).to_i
    last_run_number = 1 if last_run_number.zero? && generated_messages.exists?
    last_run_number + 1
  end

  def clear_current_agent_lead_run
    update_column(:current_agent_lead_run_id, nil) if current_agent_lead_run_id.present?
  end

  def same_organization
    return unless agent && lead

    return unless agent.organization_id != lead.organization_id

    errors.add(:base, 'Lead and Agent must belong to the same organization')
  end

  def assigned_mailbox_same_organization
    return unless assigned_mailbox.present? && agent.present?

    return unless assigned_mailbox.organization_id != agent.organization_id

    errors.add(:assigned_mailbox, 'must belong to the same organization')
  end
end
