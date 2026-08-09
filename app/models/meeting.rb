# frozen_string_literal: true

# Represents a scheduled meeting with a lead.
# Supports the full meeting lifecycle from scheduling through completion/no-show.
# Meetings can be created manually or automatically from inbound replies.
class Meeting < ApplicationRecord
  # Constants
  MEETING_TYPES = %w[discovery demo follow_up closing other].freeze
  STATUSES = %w[scheduled scheduling completed positive neutral no_show cancelled rescheduled pending_removal].freeze
  OUTCOMES = %w[positive neutral negative no_show].freeze
  SOURCES = %w[manual calendly].freeze
  ATTRIBUTION_METHODS = %w[agent_lead_id_param email_match unattributed manual].freeze
  REMOVAL_COMMENT_MAX_LENGTH = 1000

  # Associations
  belongs_to :organization
  belongs_to :agent_lead
  belongs_to :lead
  belongs_to :agent
  belongs_to :sender, optional: true
  belongs_to :assigned_to_account, class_name: 'Account', optional: true
  has_many :meeting_declined_comments, dependent: :destroy

  # Callbacks
  before_validation :set_organization_from_agent, on: :create

  # Validations
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :meeting_type, inclusion: { in: MEETING_TYPES }, allow_blank: true
  validates :outcome, inclusion: { in: OUTCOMES }, allow_blank: true
  validates :source, inclusion: { in: SOURCES }
  validates :attributed_via, inclusion: { in: ATTRIBUTION_METHODS }, allow_blank: true
  validates :duration_minutes, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :removal_comment, length: { maximum: REMOVAL_COMMENT_MAX_LENGTH }, allow_blank: true
  validate :lead_matches_agent_lead
  validate :agent_matches_agent_lead
  validate :assigned_account_belongs_to_organization

  # Scopes by status
  scope :scheduled, -> { where(status: 'scheduled') }
  scope :completed, -> { where(status: 'completed') }
  scope :positive, -> { where(status: 'positive') }
  scope :neutral, -> { where(status: 'neutral') }
  scope :no_show, -> { where(status: 'no_show') }
  scope :cancelled, -> { where(status: 'cancelled') }
  scope :rescheduled, -> { where(status: 'rescheduled') }

  # Time-based scopes
  scope :upcoming, -> { scheduled.where('scheduled_at > ?', Time.current).order(scheduled_at: :asc) }
  scope :past, -> { where('scheduled_at <= ?', Time.current).order(scheduled_at: :desc) }
  scope :today, -> { where(scheduled_at: Time.current.beginning_of_day..Time.current.end_of_day) }
  scope :this_week, -> { where(scheduled_at: Time.current.beginning_of_week..Time.current.end_of_week) }

  # Type-based scopes
  scope :discovery, -> { where(meeting_type: 'discovery') }
  scope :demo, -> { where(meeting_type: 'demo') }
  scope :follow_up, -> { where(meeting_type: 'follow_up') }
  scope :closing, -> { where(meeting_type: 'closing') }

  # Outcome-based scopes
  scope :positive_outcome, -> { where(outcome: 'positive') }
  scope :neutral_outcome, -> { where(outcome: 'neutral') }
  scope :negative_outcome, -> { where(outcome: 'negative') }

  # Source-based scopes
  scope :from_calendly, -> { where(source: 'calendly') }
  scope :from_manual, -> { where(source: 'manual') }
  scope :attributed, -> { where.not(attributed_via: [nil, 'unattributed']) }
  scope :unattributed, -> { where(attributed_via: 'unattributed') }

  # Status predicates
  def scheduled?
    status == 'scheduled'
  end

  def completed?
    status == 'completed'
  end

  def positive?
    status == 'positive'
  end

  def neutral?
    status == 'neutral'
  end

  def no_show?
    status == 'no_show'
  end

  def cancelled?
    status == 'cancelled'
  end

  def rescheduled?
    status == 'rescheduled'
  end

  def pending_removal?
    status == 'pending_removal'
  end

  def removal_requestable?
    modifiable? && !pending_removal?
  end

  # Source predicates
  def from_calendly?
    source == 'calendly'
  end

  def from_manual?
    source == 'manual'
  end

  # Returns true if the meeting was attributed to an agent_lead
  def attributed?
    attributed_via.present? && attributed_via != 'unattributed'
  end

  # Lifecycle methods

  # Marks the meeting as completed with optional outcome and notes
  def mark_completed!(outcome_value: nil, outcome_notes_text: nil)
    update!(
      status: 'completed',
      completed_at: Time.current,
      outcome: outcome_value,
      outcome_notes: outcome_notes_text
    )
  end

  def mark_positive!(outcome_notes_text: nil)
    update!(
      status: 'positive',
      completed_at: Time.current,
      outcome: 'positive',
      outcome_notes: outcome_notes_text
    )
  end

  def mark_neutral!(outcome_notes_text: nil)
    update!(
      status: 'neutral',
      completed_at: Time.current,
      outcome: 'neutral',
      outcome_notes: outcome_notes_text
    )
  end

  # Marks the meeting as no-show
  def mark_no_show!
    update!(
      status: 'no_show',
      completed_at: Time.current,
      outcome: 'no_show'
    )
  end

  # Marks the meeting as cancelled
  def mark_cancelled!
    update!(
      status: 'cancelled',
      cancelled_at: Time.current
    )
  end

  # Reschedules the meeting to a new time
  def reschedule!(new_scheduled_at)
    update!(
      status: 'rescheduled',
      scheduled_at: new_scheduled_at
    )
  end

  def mark_pending_removal!(comment_body: nil)
    update!(status: 'pending_removal', removal_comment: normalize_removal_comment(comment_body))
  end

  def assign_to!(account)
    update!(assigned_to_account: account)
  end

  def decline_pending_removal!(account:, comment_body:)
    comment = nil

    transaction do
      comment = meeting_declined_comments.create!(
        account: account,
        body: comment_body.to_s.strip.truncate(MeetingDeclinedComment::BODY_MAX_LENGTH, omission: '')
      )
      update!(status: 'scheduling')
    end

    comment
  end

  # Returns true if the meeting is in a terminal state
  def terminal?
    %w[completed positive neutral no_show cancelled].include?(status)
  end

  # Returns true if the meeting can be modified
  def modifiable?
    %w[scheduled scheduling rescheduled pending_removal].include?(status)
  end

  # Returns the display name for the meeting
  def display_name
    type_name = meeting_type&.titleize || 'Meeting'
    lead_name = lead.full_name || lead.email
    "#{type_name} with #{lead_name}"
  end

  def customer_display_status
    return outcome if status == 'completed' && outcome.in?(%w[positive neutral no_show])

    status
  end

  private

  def lead_matches_agent_lead
    return unless agent_lead.present? && lead.present?

    return unless agent_lead.lead_id != lead.id

    errors.add(:lead, "must match the agent_lead's lead")
  end

  def agent_matches_agent_lead
    return unless agent_lead.present? && agent.present?

    return unless agent_lead.agent_id != agent.id

    errors.add(:agent, "must match the agent_lead's agent")
  end

  def assigned_account_belongs_to_organization
    return unless assigned_to_account.present?

    unless assigned_to_account.active_organization_memberships.exists?(organization_id: organization_id)
      errors.add(:assigned_to_account, 'must belong to the same organization')
    end
  end

  def normalize_removal_comment(comment_body)
    comment_body.to_s.strip.presence&.truncate(REMOVAL_COMMENT_MAX_LENGTH, omission: '')
  end

  def set_organization_from_agent
    self.organization_id ||= agent&.organization_id
  end
end
