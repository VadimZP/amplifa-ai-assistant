# frozen_string_literal: true

require 'test_helper'

class MeetingTest < ActiveSupport::TestCase
  # === Test Setup ===

  setup do
    @agent_lead = agent_leads(:john_in_draft)
    @lead = leads(:john_doe)
    @agent = agents(:draft_agent)
    @meeting = meetings(:scheduled_discovery)
  end

  # === Association Tests ===

  test 'belongs to organization' do
    assert_respond_to @meeting, :organization
    assert_kind_of Organization, @meeting.organization
  end

  test 'belongs to agent_lead' do
    assert_respond_to @meeting, :agent_lead
    assert_kind_of AgentLead, @meeting.agent_lead
  end

  test 'belongs to lead' do
    assert_respond_to @meeting, :lead
    assert_kind_of Lead, @meeting.lead
  end

  test 'belongs to agent' do
    assert_respond_to @meeting, :agent
    assert_kind_of Agent, @meeting.agent
  end

  test 'assigned_to_account association is optional' do
    assert_respond_to @meeting, :assigned_to_account
    assert_nil @meeting.assigned_to_account
    assert @meeting.valid?
  end

  test 'auto-sets organization_id from agent on create' do
    new_meeting = Meeting.new(
      agent_lead: @agent_lead,
      lead: @lead,
      agent: @agent,
      status: 'scheduled'
    )
    assert_nil new_meeting.organization_id
    new_meeting.valid?
    assert_equal @agent.organization_id, new_meeting.organization_id
  end

  test 'does not override organization_id if already set' do
    other_org = organizations(:beta)
    new_meeting = Meeting.new(
      organization: other_org,
      agent_lead: @agent_lead,
      lead: @lead,
      agent: @agent,
      status: 'scheduled'
    )
    new_meeting.valid?
    assert_equal other_org.id, new_meeting.organization_id
  end

  # === Validation Tests ===

  test 'validates presence of status' do
    meeting = Meeting.new(
      organization: @agent.organization,
      agent_lead: @agent_lead,
      lead: @lead,
      agent: @agent,
      status: nil
    )
    assert_not meeting.valid?
    assert_includes meeting.errors[:status], "can't be blank"
  end

  # WHY: Only valid statuses should be allowed
  test 'validates inclusion of status in STATUSES' do
    Meeting::STATUSES.each do |status|
      @meeting.status = status
      assert @meeting.valid?, "#{status} should be a valid status"
    end

    @meeting.status = 'invalid_status'
    assert_not @meeting.valid?
    assert_includes @meeting.errors[:status], 'is not included in the list'
  end

  # WHY: Only valid meeting types should be allowed
  test 'validates inclusion of meeting_type in MEETING_TYPES' do
    Meeting::MEETING_TYPES.each do |type|
      @meeting.meeting_type = type
      assert @meeting.valid?, "#{type} should be a valid meeting type"
    end

    @meeting.meeting_type = 'invalid_type'
    assert_not @meeting.valid?
    assert_includes @meeting.errors[:meeting_type], 'is not included in the list'
  end

  # WHY: Meeting type is optional (blank is allowed)
  test 'allows blank meeting_type' do
    @meeting.meeting_type = nil
    assert @meeting.valid?

    @meeting.meeting_type = ''
    assert @meeting.valid?
  end

  # WHY: Only valid outcomes should be allowed
  test 'validates inclusion of outcome in OUTCOMES' do
    Meeting::OUTCOMES.each do |outcome|
      @meeting.outcome = outcome
      assert @meeting.valid?, "#{outcome} should be a valid outcome"
    end

    @meeting.outcome = 'invalid_outcome'
    assert_not @meeting.valid?
    assert_includes @meeting.errors[:outcome], 'is not included in the list'
  end

  # WHY: Outcome is optional until meeting is completed
  test 'allows blank outcome' do
    @meeting.outcome = nil
    assert @meeting.valid?
  end

  # WHY: Duration should be positive if provided
  test 'validates duration_minutes is positive' do
    @meeting.duration_minutes = 30
    assert @meeting.valid?

    @meeting.duration_minutes = 0
    assert_not @meeting.valid?
    assert_includes @meeting.errors[:duration_minutes], 'must be greater than 0'

    @meeting.duration_minutes = -10
    assert_not @meeting.valid?
  end

  # WHY: Duration is optional
  test 'allows nil duration_minutes' do
    @meeting.duration_minutes = nil
    assert @meeting.valid?
  end

  test 'allows blank removal_comment' do
    @meeting.removal_comment = nil
    assert @meeting.valid?

    @meeting.removal_comment = ''
    assert @meeting.valid?
  end

  test 'validates removal_comment maximum length' do
    @meeting.removal_comment = 'x' * (Meeting::REMOVAL_COMMENT_MAX_LENGTH + 1)

    assert_not @meeting.valid?
    assert_includes @meeting.errors[:removal_comment],
                    "is too long (maximum is #{Meeting::REMOVAL_COMMENT_MAX_LENGTH} characters)"
  end

  # WHY: Lead must match the agent_lead's lead for consistency
  test 'validates lead matches agent_lead' do
    other_lead = leads(:jane_smith)
    @meeting.lead = other_lead
    assert_not @meeting.valid?
    assert_includes @meeting.errors[:lead], "must match the agent_lead's lead"
  end

  # WHY: Agent must match the agent_lead's agent for consistency
  test 'validates agent matches agent_lead' do
    other_agent = agents(:ready_agent)
    @meeting.agent = other_agent
    assert_not @meeting.valid?
    assert_includes @meeting.errors[:agent], "must match the agent_lead's agent"
  end

  test 'validates assigned_to_account belongs to same organization' do
    @meeting.assigned_to_account = accounts(:growth_lab_user)

    assert_not @meeting.valid?
    assert_includes @meeting.errors[:assigned_to_account], 'must belong to the same organization'
  end

  test 'allows assigned_to_account with active membership in meeting organization' do
    multi_org_user = accounts(:growth_lab_user)
    multi_org_user.update!(organization: organizations(:growth_lab), role: 'customer_user')
    OrganizationMembership.create!(
      account: multi_org_user,
      organization: @meeting.organization,
      role: 'customer_user',
      status: 'active'
    )

    @meeting.assigned_to_account = multi_org_user

    assert @meeting.valid?
  end

  # === Status Predicate Tests ===

  # WHY: Status predicates provide clean API for checking meeting state
  test 'status predicates return correct values' do
    @meeting.status = 'scheduled'
    assert @meeting.scheduled?
    assert_not @meeting.completed?

    @meeting.status = 'completed'
    assert @meeting.completed?
    assert_not @meeting.scheduled?

    @meeting.status = 'no_show'
    assert @meeting.no_show?

    @meeting.status = 'cancelled'
    assert @meeting.cancelled?

    @meeting.status = 'rescheduled'
    assert @meeting.rescheduled?
  end

  # === Lifecycle Method Tests ===

  # WHY: mark_completed! should update status and record outcome
  test 'mark_completed! updates status and outcome' do
    @meeting.mark_completed!(outcome_value: 'positive', outcome_notes_text: 'Great meeting!')

    assert_equal 'completed', @meeting.status
    assert_equal 'positive', @meeting.outcome
    assert_equal 'Great meeting!', @meeting.outcome_notes
    assert_not_nil @meeting.completed_at
  end

  # WHY: mark_no_show! should update status and set outcome to no_show
  test 'mark_no_show! updates status and outcome' do
    @meeting.mark_no_show!

    assert_equal 'no_show', @meeting.status
    assert_equal 'no_show', @meeting.outcome
    assert_not_nil @meeting.completed_at
  end

  # WHY: mark_cancelled! should update status and record cancellation time
  test 'mark_cancelled! updates status' do
    @meeting.mark_cancelled!

    assert_equal 'cancelled', @meeting.status
    assert_not_nil @meeting.cancelled_at
  end

  # WHY: reschedule! should update scheduled_at and set status to rescheduled
  test 'reschedule! updates scheduled_at and status' do
    new_time = 1.week.from_now
    @meeting.reschedule!(new_time)

    assert_equal 'rescheduled', @meeting.status
    assert_in_delta new_time.to_i, @meeting.scheduled_at.to_i, 1
  end

  test 'assign_to! updates assigned_to_account' do
    assignee = accounts(:customer_user)

    @meeting.assign_to!(assignee)

    assert_equal assignee, @meeting.assigned_to_account
  end

  test 'mark_pending_removal! stores optional trimmed comment' do
    @meeting.mark_pending_removal!(comment_body: '  Prospect merged into another opportunity.  ')

    assert_equal 'pending_removal', @meeting.status
    assert_equal 'Prospect merged into another opportunity.', @meeting.removal_comment
  end

  # === Terminal/Modifiable Tests ===

  # WHY: terminal? helps identify meetings that can't be changed
  test 'terminal? returns true for completed, no_show, and cancelled' do
    @meeting.status = 'completed'
    assert @meeting.terminal?

    @meeting.status = 'no_show'
    assert @meeting.terminal?

    @meeting.status = 'cancelled'
    assert @meeting.terminal?

    @meeting.status = 'scheduled'
    assert_not @meeting.terminal?

    @meeting.status = 'rescheduled'
    assert_not @meeting.terminal?
  end

  # WHY: modifiable? helps identify meetings that can be changed
  test 'modifiable? returns true for scheduled and rescheduled' do
    @meeting.status = 'scheduled'
    assert @meeting.modifiable?

    @meeting.status = 'rescheduled'
    assert @meeting.modifiable?

    @meeting.status = 'completed'
    assert_not @meeting.modifiable?

    @meeting.status = 'cancelled'
    assert_not @meeting.modifiable?
  end

  # === Scope Tests ===

  # WHY: Status scopes allow easy filtering of meetings
  test 'status scopes filter correctly' do
    assert_includes Meeting.scheduled, meetings(:scheduled_discovery)
    assert_includes Meeting.completed, meetings(:completed_demo)
    assert_includes Meeting.no_show, meetings(:no_show_meeting)
    assert_includes Meeting.cancelled, meetings(:cancelled_meeting)
  end

  # WHY: Type scopes allow filtering by meeting type
  test 'meeting_type scopes filter correctly' do
    assert_includes Meeting.discovery, meetings(:scheduled_discovery)
    assert_includes Meeting.demo, meetings(:completed_demo)
    assert_includes Meeting.follow_up, meetings(:no_show_meeting)
    assert_includes Meeting.closing, meetings(:cancelled_meeting)
  end

  # WHY: upcoming scope returns only scheduled meetings in the future
  test 'upcoming scope returns future scheduled meetings' do
    upcoming = Meeting.upcoming

    assert_includes upcoming, meetings(:scheduled_discovery)
    assert_not_includes upcoming, meetings(:completed_demo)
  end

  # === Display Name Test ===

  # WHY: display_name provides user-friendly meeting description
  test 'display_name returns formatted meeting description' do
    @meeting.meeting_type = 'discovery'
    assert_match(/Discovery/, @meeting.display_name)
    assert_match(/John Doe/, @meeting.display_name)
  end

  test 'display_name handles nil meeting_type' do
    @meeting.meeting_type = nil
    assert_match(/Meeting/, @meeting.display_name)
  end

  # === Source and Attribution Tests ===

  # WHY: Source tracks how the meeting was created (manual vs Calendly)
  test 'validates inclusion of source in SOURCES' do
    Meeting::SOURCES.each do |source|
      @meeting.source = source
      assert @meeting.valid?, "#{source} should be a valid source"
    end

    @meeting.source = 'invalid_source'
    assert_not @meeting.valid?
    assert_includes @meeting.errors[:source], 'is not included in the list'
  end

  test 'source defaults to manual' do
    meeting = Meeting.new(
      organization: @agent.organization,
      agent_lead: @agent_lead,
      lead: @lead,
      agent: @agent,
      status: 'scheduled'
    )
    assert_equal 'manual', meeting.source
  end

  # WHY: Attribution method tracks how meeting was linked to agent_lead
  test 'validates inclusion of attributed_via in ATTRIBUTION_METHODS' do
    Meeting::ATTRIBUTION_METHODS.each do |method|
      @meeting.attributed_via = method
      assert @meeting.valid?, "#{method} should be a valid attribution method"
    end

    @meeting.attributed_via = 'invalid_method'
    assert_not @meeting.valid?
    assert_includes @meeting.errors[:attributed_via], 'is not included in the list'
  end

  # WHY: attributed_via is optional
  test 'allows blank attributed_via' do
    @meeting.attributed_via = nil
    assert @meeting.valid?
  end

  # === Source Predicate Tests ===

  # WHY: from_calendly? predicate provides clean API for checking source
  test 'from_calendly? returns true when source is calendly' do
    @meeting.source = 'calendly'
    assert @meeting.from_calendly?
    assert_not @meeting.from_manual?
  end

  # WHY: from_manual? predicate provides clean API for checking source
  test 'from_manual? returns true when source is manual' do
    @meeting.source = 'manual'
    assert @meeting.from_manual?
    assert_not @meeting.from_calendly?
  end

  # === Attribution Predicate Tests ===

  # WHY: attributed? should return true for meaningful attribution
  test 'attributed? returns true when attributed_via is present and not unattributed' do
    @meeting.attributed_via = 'agent_lead_id_param'
    assert @meeting.attributed?

    @meeting.attributed_via = 'email_match'
    assert @meeting.attributed?

    @meeting.attributed_via = 'manual'
    assert @meeting.attributed?
  end

  # WHY: attributed? should return false for unattributed meetings
  test 'attributed? returns false when attributed_via is unattributed' do
    @meeting.attributed_via = 'unattributed'
    assert_not @meeting.attributed?
  end

  # WHY: attributed? should return false when attributed_via is nil
  test 'attributed? returns false when attributed_via is nil' do
    @meeting.attributed_via = nil
    assert_not @meeting.attributed?
  end

  # === Source Scope Tests ===

  test 'from_calendly scope returns only calendly meetings' do
    calendly_meeting = Meeting.create!(
      organization: @agent.organization,
      agent_lead: @agent_lead,
      lead: @lead,
      agent: @agent,
      status: 'scheduled',
      source: 'calendly'
    )

    assert_includes Meeting.from_calendly, calendly_meeting
    assert_not_includes Meeting.from_calendly, @meeting
  end

  # WHY: from_manual scope filters manually created meetings
  test 'from_manual scope returns only manual meetings' do
    assert_includes Meeting.from_manual, @meeting

    @meeting.update!(source: 'calendly')
    assert_not_includes Meeting.from_manual, @meeting
  end

  # WHY: attributed scope filters meetings with meaningful attribution
  test 'attributed scope returns only attributed meetings' do
    @meeting.update!(attributed_via: 'agent_lead_id_param')
    assert_includes Meeting.attributed, @meeting

    @meeting.update!(attributed_via: 'unattributed')
    assert_not_includes Meeting.attributed, @meeting
  end

  # WHY: unattributed scope filters meetings without attribution
  test 'unattributed scope returns only unattributed meetings' do
    @meeting.update!(attributed_via: 'unattributed')
    assert_includes Meeting.unattributed, @meeting

    @meeting.update!(attributed_via: 'email_match')
    assert_not_includes Meeting.unattributed, @meeting
  end

  # === Sender Association Tests ===

  # WHY: Meeting can optionally belong to a sender (for Calendly-created meetings)
  test 'sender association is optional' do
    assert_respond_to @meeting, :sender
    assert_nil @meeting.sender
    assert @meeting.valid?
  end

  # WHY: Meeting can be associated with a sender
  test 'can associate meeting with sender' do
    sender = senders(:acme_john)
    @meeting.sender = sender
    assert @meeting.valid?
    assert_equal sender, @meeting.sender
  end
end
