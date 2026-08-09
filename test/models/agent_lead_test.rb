# frozen_string_literal: true

require 'test_helper'

class AgentLeadTest < ActiveSupport::TestCase
  # Tests cover basic validation (WHY: ensure junction table integrity)
  test 'requires agent' do
    agent_lead = AgentLead.new(lead: leads(:john_doe))
    assert_not agent_lead.valid?
    assert_includes agent_lead.errors[:agent], "can't be blank"
  end

  test 'requires lead' do
    agent_lead = AgentLead.new(agent: agents(:draft_agent))
    assert_not agent_lead.valid?
    assert_includes agent_lead.errors[:lead], "can't be blank"
  end

  test 'valid with agent and lead' do
    # Create a new lead that's not already in this agent
    lead = Lead.create!(organization: organizations(:acme), email: 'unique-agent-lead@test.com')
    agent_lead = AgentLead.new(agent: agents(:draft_agent), lead: lead)
    assert agent_lead.valid?
  end

  # Tests cover uniqueness (WHY: prevent duplicate lead assignments to same agent)
  test 'prevents duplicate lead in same agent' do
    existing = agent_leads(:john_in_draft)
    duplicate = AgentLead.new(agent: existing.agent, lead: existing.lead)

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:lead_id], 'is already assigned to this agent'
  end

  test 'allows same lead in different agents' do
    # WHY: A lead can be in multiple campaigns simultaneously
    lead = leads(:john_doe)
    new_agent = agents(:active_agent)

    # First ensure we don't have this combination already
    AgentLead.where(agent: new_agent, lead: lead).destroy_all

    agent_lead = AgentLead.new(agent: new_agent, lead: lead)
    assert agent_lead.valid?
  end

  # Tests cover same_organization validation (WHY: cross-org data access prevention)
  test 'requires agent and lead to be in same organization' do
    # beta_lead belongs to beta org, draft_agent belongs to acme
    agent_lead = AgentLead.new(agent: agents(:draft_agent), lead: leads(:beta_lead))

    assert_not agent_lead.valid?
    assert_includes agent_lead.errors[:base], 'Lead and Agent must belong to the same organization'
  end

  test 'allows agent and lead from same organization' do
    agent = agents(:draft_agent)
    lead = Lead.create!(organization: agent.organization, email: 'same-org@test.com')
    agent_lead = AgentLead.new(agent: agent, lead: lead)

    assert agent_lead.valid?
  end

  # Tests cover scopes (WHY: efficient filtering for queries)
  test 'for_agent scope filters by agent' do
    results = AgentLead.for_agent(agents(:draft_agent))
    assert_includes results, agent_leads(:john_in_draft)
    assert_not_includes results, agent_leads(:beta_lead_in_beta_agent)
  end

  test 'for_lead scope filters by lead' do
    results = AgentLead.for_lead(leads(:john_doe))
    assert_includes results, agent_leads(:john_in_draft)
    assert_includes results, agent_leads(:john_in_ready)
  end

  # Tests cover associations (WHY: ensure bidirectional relationships work)
  test 'belongs to agent' do
    agent_lead = agent_leads(:john_in_draft)
    assert_equal agents(:draft_agent), agent_lead.agent
  end

  test 'belongs to lead' do
    agent_lead = agent_leads(:john_in_draft)
    assert_equal leads(:john_doe), agent_lead.lead
  end

  # WHY: sequence_position must be a non-negative integer
  test 'sequence_position must be >= 0' do
    agent_lead = agent_leads(:john_in_draft)
    agent_lead.sequence_position = -1
    assert_not agent_lead.valid?
    assert_includes agent_lead.errors[:sequence_position], 'must be greater than or equal to 0'
  end

  # WHY: status must be a valid status value
  test 'status must be valid' do
    agent_lead = agent_leads(:john_in_draft)
    agent_lead.status = 'invalid'
    assert_not agent_lead.valid?
    assert_includes agent_lead.errors[:status], 'is not included in the list'
  end

  # WHY: all defined statuses should be valid
  test 'allows valid statuses' do
    AgentLead::STATUSES.each do |status|
      agent_lead = agent_leads(:john_in_draft)
      agent_lead.status = status
      assert agent_lead.valid?, "Expected status '#{status}' to be valid"
    end
  end

  # WHY: status predicates for cleaner conditional logic
  test 'status predicates work correctly' do
    agent_lead = agent_leads(:john_in_draft)

    agent_lead.status = 'pending'
    assert agent_lead.pending?

    agent_lead.status = 'generating'
    assert agent_lead.generating?

    agent_lead.status = 'generated'
    assert agent_lead.generated?

    agent_lead.status = 'paused'
    assert agent_lead.paused?

    agent_lead.status = 'error'
    assert agent_lead.error?
  end

  # WHY: status scopes for filtering leads by generation status
  test 'status scopes filter correctly' do
    # Set up different statuses
    john = agent_leads(:john_in_draft)
    jane = agent_leads(:jane_in_draft)
    john.update!(status: 'pending')
    jane.update!(status: 'error')

    assert_includes AgentLead.pending, john
    assert_not_includes AgentLead.pending, jane
    assert_includes AgentLead.with_errors, jane
    assert_includes AgentLead.ready_for_generation, john
    assert_includes AgentLead.ready_for_generation, jane
  end

  # WHY: sample_leads returns first N leads by created_at for sample generation
  test 'sample_leads scope returns first N by created_at' do
    agent = agents(:draft_agent)
    # John and Jane are in draft_agent
    samples = AgentLead.for_agent(agent).sample_leads(1)
    assert_equal 1, samples.count
  end

  # WHY: current_step returns the step at the lead's current position
  test 'current_step returns nil when position is 0' do
    agent_lead = agent_leads(:john_in_draft)
    agent_lead.sequence_position = 0
    assert_nil agent_lead.current_step
  end

  test 'current_step returns the step at current position' do
    agent_lead = agent_leads(:john_in_draft)
    agent_lead.sequence_position = 1
    assert_equal sequence_steps(:step_one_email), agent_lead.current_step
  end

  # WHY: next_step helps advance through sequence
  test 'next_step returns next step in sequence' do
    agent_lead = agent_leads(:john_in_draft)
    agent_lead.sequence_position = 0
    assert_equal sequence_steps(:step_one_email), agent_lead.next_step

    agent_lead.sequence_position = 1
    assert_equal sequence_steps(:step_two_email), agent_lead.next_step
  end

  # WHY: next_step should skip inactive steps to find the next active step
  test 'next_step skips inactive steps' do
    agent_lead = agent_leads(:john_in_draft)
    # Position 2 means we've completed step 2
    # step_three_inactive (position 3) is inactive, step_four_email (position 4) is active
    agent_lead.sequence_position = 2

    next_step = agent_lead.next_step
    assert_not_nil next_step, 'Should find an active step'
    assert_equal sequence_steps(:step_four_email), next_step, 'Should skip inactive step 3 and return step 4'
    assert_equal 4, next_step.position
  end

  # WHY: next_step should return nil when no active steps remain
  test 'next_step returns nil when all remaining steps are inactive' do
    agent_lead = agent_leads(:john_in_draft)
    # Make step 4 inactive for this test
    sequence_steps(:step_four_email).update!(active: false)

    # Position 2 means we've completed step 2
    # Both step 3 and step 4 are now inactive
    agent_lead.sequence_position = 2

    assert_nil agent_lead.next_step, 'Should return nil when all remaining steps are inactive'
  end

  # WHY: advance_position! moves lead through sequence
  test 'advance_position! increments position' do
    agent_lead = agent_leads(:john_in_draft)
    agent_lead.sequence_position = 0
    agent_lead.advance_position!
    assert_equal 1, agent_lead.sequence_position
  end

  test 'advance_position! does not exceed max position' do
    agent_lead = agent_leads(:john_in_draft)
    max_pos = agent_lead.agent.sequence_steps.maximum(:position)
    agent_lead.sequence_position = max_pos
    agent_lead.advance_position!
    assert_equal max_pos, agent_lead.sequence_position
  end

  test 'advance_position! skips inactive steps' do
    agent_lead = agent_leads(:john_in_draft)
    agent_lead.sequence_position = 2
    agent_lead.advance_position!
    assert_equal 4, agent_lead.sequence_position, 'Should skip inactive step 3 and advance to step 4'
  end

  test 'advance_position! handles all remaining steps inactive' do
    agent_lead = agent_leads(:john_in_draft)
    sequence_steps(:step_four_email).update!(active: false)
    agent_lead.sequence_position = 2
    max_pos = agent_lead.agent.sequence_steps.maximum(:position)
    agent_lead.advance_position!
    assert agent_lead.sequence_position > max_pos, 'Should advance beyond max position when no active steps remain'
  end

  test 'advance_after_send! schedules next_send_at for the next active step' do
    agent_lead = agent_leads(:john_in_draft)
    sent_at = Time.zone.parse('2026-04-09 15:30:00 UTC')

    agent_lead.update!(sequence_position: 0, next_send_at: nil)
    sequence_steps(:step_one_email).update!(delay_days: 3)

    agent_lead.advance_after_send!(sent_at: sent_at)

    agent_lead.reload
    assert_equal 1, agent_lead.sequence_position
    assert_equal sent_at + 3.days, agent_lead.next_send_at
  end

  test 'advance_after_send! keeps zero delay steps immediately eligible' do
    agent_lead = agent_leads(:john_in_draft)
    sent_at = Time.zone.parse('2026-04-09 15:30:00 UTC')

    agent_lead.update!(sequence_position: 1, next_send_at: nil)
    sequence_steps(:step_two_email).update!(delay_days: 0)

    agent_lead.advance_after_send!(sent_at: sent_at)

    agent_lead.reload
    assert_equal 2, agent_lead.sequence_position
    assert_equal sent_at, agent_lead.next_send_at
  end

  test 'advance_after_send! advances past end when no active steps remain' do
    agent_lead = agent_leads(:john_in_draft)
    sequence_steps(:step_four_email).update!(active: false)
    agent_lead.update!(sequence_position: 2, next_send_at: nil)

    max_pos = agent_lead.agent.sequence_steps.maximum(:position)

    agent_lead.advance_after_send!(sent_at: Time.zone.parse('2026-04-09 15:30:00 UTC'))

    agent_lead.reload
    assert_equal max_pos + 1, agent_lead.sequence_position
    assert_nil agent_lead.next_send_at
  end

  test 'reconcile_sent_message! updates stale first-touch progression from a sent message' do
    agent_lead = agent_leads(:john_in_draft)
    agent_lead.update!(delivery_status: 'not_contacted', sequence_position: 0, last_sent_at: nil, next_send_at: nil)

    message = generated_messages(:john_step_one_draft)
    message.update!(
      status: 'sent',
      sent_at: Time.zone.parse('2026-04-09 15:30:00 UTC')
    )

    changed = agent_lead.reconcile_sent_message!(message)

    agent_lead.reload
    assert changed
    assert_equal 'in_sequence', agent_lead.delivery_status
    assert_equal 1, agent_lead.sequence_position
    assert_equal Time.zone.parse('2026-04-09 15:30:00 UTC'), agent_lead.last_sent_at
    assert_equal Time.zone.parse('2026-04-09 15:30:00 UTC'), agent_lead.next_send_at
  end

  test 'reconcile_sent_message! catches up to the highest sent step' do
    agent_lead = agent_leads(:john_in_draft)
    agent_lead.update!(delivery_status: 'not_contacted', sequence_position: 0, last_sent_at: nil, next_send_at: nil)

    generated_messages(:john_step_one_draft).update!(
      status: 'sent',
      sent_at: Time.zone.parse('2026-04-09 15:30:00 UTC')
    )
    message = generated_messages(:john_step_two_draft)
    message.update!(
      status: 'sent',
      sent_at: Time.zone.parse('2026-04-12 09:00:00 UTC')
    )

    changed = agent_lead.reconcile_sent_message!(message)

    agent_lead.reload
    assert changed
    assert_equal 'in_sequence', agent_lead.delivery_status
    assert_equal 2, agent_lead.sequence_position
    assert_equal Time.zone.parse('2026-04-12 09:00:00 UTC'), agent_lead.last_sent_at
    assert_equal Time.zone.parse('2026-04-15 09:00:00 UTC'), agent_lead.next_send_at
  end

  test 'reconcile_sent_message! does not overshoot inactive authoritative steps' do
    agent_lead = agent_leads(:john_in_draft)
    sent_at = Time.zone.parse('2026-04-12 09:00:00 UTC')
    agent_lead.update!(delivery_status: 'in_sequence', sequence_position: 1, last_sent_at: nil, next_send_at: nil)

    generated_messages(:john_step_one_draft).update!(
      status: 'sent',
      sent_at: Time.zone.parse('2026-04-09 15:30:00 UTC')
    )

    message = agent_lead.generated_messages.create!(
      sequence_step: sequence_steps(:step_three_inactive),
      subject: 'Historical step',
      body: 'Sent before this step was archived.',
      status: 'sent',
      sent_at: sent_at
    )

    changed = agent_lead.reconcile_sent_message!(message)

    agent_lead.reload
    assert changed
    assert_equal 3, agent_lead.sequence_position
    assert_equal sent_at, agent_lead.last_sent_at
    assert_equal sent_at + 7.days, agent_lead.next_send_at
  end

  # WHY: A welcome-back email is detached from the sequence (AMP-264). Reconciling
  # it must NOT advance sequence_position, so the lead later resumes at the exact
  # next real step it was due. It reschedules the sequence 3 business days out.
  # WHY: Guard against a welcome-back message accidentally flowing through the
  # sequence reconciler, which dereferences sequence_step.position and would crash
  # on a null-step welcome-back (AMP-264).
  test 'reconcile_sent_message! is idempotent when progression is already aligned' do
    agent_lead = agent_leads(:john_in_draft)
    sent_at = Time.zone.parse('2026-04-09 15:30:00 UTC')
    agent_lead.update!(delivery_status: 'in_sequence', sequence_position: 1, last_sent_at: sent_at,
                       next_send_at: sent_at)

    message = generated_messages(:john_step_one_draft)
    message.update!(
      status: 'sent',
      sent_at: sent_at
    )

    assert_not agent_lead.reconcile_sent_message!(message)
  end

  test 'reconcile_sent_message! restores missing next_send_at when progression is already aligned' do
    agent_lead = agent_leads(:john_in_draft)
    sent_at = Time.zone.parse('2026-04-09 15:30:00 UTC')
    agent_lead.update!(delivery_status: 'in_sequence', sequence_position: 1, last_sent_at: sent_at,
                       next_send_at: nil)

    message = generated_messages(:john_step_one_draft)
    message.update!(
      status: 'sent',
      sent_at: sent_at
    )

    assert agent_lead.reconcile_sent_message!(message)

    agent_lead.reload
    assert_equal 1, agent_lead.sequence_position
    assert_equal sent_at, agent_lead.last_sent_at
    assert_equal sent_at, agent_lead.next_send_at
  end
  # WHY: mark methods update status and related fields atomically
  test 'mark_generating! updates status and clears error' do
    agent_lead = agent_leads(:john_in_draft)
    agent_lead.update!(status: 'error', generation_error: 'Previous error')

    agent_lead.mark_generating!

    assert agent_lead.generating?
    assert_nil agent_lead.generation_error
  end

  test 'mark_generated! updates status and timestamp' do
    agent_lead = agent_leads(:john_in_draft)

    freeze_time do
      agent_lead.mark_generated!

      assert agent_lead.generated?
      assert_equal Time.current, agent_lead.last_generated_at
      assert_nil agent_lead.generation_error
    end
  end

  test 'mark_error! updates status and sets error message' do
    agent_lead = agent_leads(:john_in_draft)

    agent_lead.mark_error!('API timeout')

    assert agent_lead.error?
    assert_equal 'API timeout', agent_lead.generation_error
  end

  # WHY: reset_for_regeneration! prepares lead for fresh generation
  test 'reset_for_regeneration! resets all tracking fields' do
    agent_lead = agent_leads(:john_in_draft)
    agent_lead.update!(
      status: 'generated',
      sequence_position: 3,
      generation_error: 'old error'
    )

    agent_lead.reset_for_regeneration!

    assert agent_lead.pending?
    assert_equal 0, agent_lead.sequence_position
    assert_nil agent_lead.generation_error
  end

  # WHY: has_many generated_messages association
  test 'has many generated_messages' do
    agent_lead = agent_leads(:john_in_draft)
    assert agent_lead.generated_messages.include?(generated_messages(:john_step_one_draft))
  end

  # Meeting tracking tests
  # Note: Meeting tracking now uses the Meeting model instead of simple flags.
  # mark_meeting! creates Meeting records, and meetings_count is computed from Meeting records.

  # WHY: meeting_booked? predicate for checking if a meeting was booked
  test 'meeting_booked? returns false when no meeting exists and no legacy flag' do
    # Use an agent_lead without fixtures that have meetings
    agent_lead = agent_leads(:beta_lead_in_beta_agent)
    # Clear any legacy data
    agent_lead.update!(meeting_booked_at: nil)
    # Ensure no meetings exist
    agent_lead.meetings.destroy_all

    assert_not agent_lead.meeting_booked?
  end

  test 'meeting_booked? returns true when meeting is booked via Meeting model' do
    agent_lead = agent_leads(:beta_lead_in_beta_agent)
    agent_lead.meetings.destroy_all
    agent_lead.update!(meeting_booked_at: nil)

    # Create a meeting
    Meeting.create!(
      agent_lead: agent_lead,
      lead: agent_lead.lead,
      agent: agent_lead.agent,
      status: 'scheduled'
    )

    assert agent_lead.meeting_booked?
  end

  test 'meeting_booked? returns true when legacy flag is set' do
    agent_lead = agent_leads(:beta_lead_in_beta_agent)
    agent_lead.meetings.destroy_all
    agent_lead.update!(meeting_booked_at: Time.current)
    assert agent_lead.meeting_booked?
  end

  # WHY: mark_meeting! creates a Meeting record and sets legacy flag
  test 'mark_meeting! creates meeting record and sets legacy flag' do
    agent_lead = agent_leads(:beta_lead_in_beta_agent)
    agent = agent_lead.agent
    agent_lead.meetings.destroy_all
    agent_lead.update!(meeting_booked_at: nil)
    initial_count = agent.meetings_count

    freeze_time do
      agent_lead.mark_meeting!

      agent_lead.reload
      agent.reload

      assert agent_lead.meeting_booked?
      assert_equal Time.current, agent_lead.meeting_booked_at
      # Now count from Meeting records, not counter column
      assert_equal initial_count + 1, agent.meetings_count
    end
  end

  test 'mark_meeting! accepts optional notes and saves to Meeting' do
    agent_lead = agent_leads(:beta_lead_in_beta_agent)
    agent_lead.meetings.destroy_all

    agent_lead.mark_meeting!(notes: 'Scheduled for next Tuesday')

    agent_lead.reload
    assert_equal 'Scheduled for next Tuesday', agent_lead.meeting_notes
    assert_equal 'Scheduled for next Tuesday', agent_lead.latest_meeting.notes
  end

  # WHY: unmark_meeting! cancels a modifiable meeting (scheduled or rescheduled)
  test 'unmark_meeting! cancels a scheduled meeting' do
    agent_lead = agent_leads(:beta_lead_in_beta_agent)
    agent_lead.meetings.destroy_all

    # Create a scheduled meeting (future date makes it modifiable)
    meeting = agent_lead.schedule_meeting!(
      notes: 'Test meeting',
      scheduled_at: 1.week.from_now # Future date = "scheduled" status
    )

    assert meeting.modifiable?, 'Meeting should be modifiable when scheduled'

    # Now unmark it - this cancels the meeting
    agent_lead.unmark_meeting!

    meeting.reload
    assert_equal 'cancelled', meeting.status
    assert_not_nil meeting.cancelled_at
  end

  test 'unmark_meeting! does nothing when no modifiable meeting exists' do
    agent_lead = agent_leads(:beta_lead_in_beta_agent)
    agent_lead.meetings.destroy_all
    agent_lead.update!(meeting_booked_at: nil)

    # Should not raise and no meetings should be created
    assert_no_difference 'Meeting.count' do
      agent_lead.unmark_meeting!
    end
  end

  # WHY: meeting scopes for filtering leads by meeting status
  test 'with_meeting scope returns leads with meetings' do
    booked = agent_leads(:john_in_draft)
    not_booked = agent_leads(:jane_in_draft)

    booked.update!(meeting_booked_at: Time.current)

    results = AgentLead.with_meeting
    assert_includes results, booked
    assert_not_includes results, not_booked
  end

  test 'without_meeting scope returns leads without meetings' do
    booked = agent_leads(:john_in_draft)
    not_booked = agent_leads(:jane_in_draft)

    booked.update!(meeting_booked_at: Time.current)

    results = AgentLead.without_meeting
    assert_includes results, not_booked
    assert_not_includes results, booked
  end

  test 'ready_to_send scope excludes blacklisted leads' do
    agent = agents(:draft_agent)
    non_blacklisted = agent_leads(:john_in_draft)
    blacklisted_lead = leads(:blacklisted_lead)

    blacklisted_agent_lead = AgentLead.create!(
      agent: agent,
      lead: blacklisted_lead,
      delivery_status: 'in_sequence',
      next_send_at: 1.hour.ago
    )

    non_blacklisted.update!(
      delivery_status: 'in_sequence',
      next_send_at: 1.hour.ago
    )

    results = AgentLead.ready_to_send

    assert_includes results, non_blacklisted
    assert_not_includes results, blacklisted_agent_lead
  end

  test 'ready_to_send scope includes non-blacklisted leads with valid send time' do
    agent_lead = agent_leads(:john_in_draft)
    agent_lead.update!(
      delivery_status: 'in_sequence',
      next_send_at: 1.hour.ago
    )

    results = AgentLead.ready_to_send

    assert_includes results, agent_lead
  end

  test 'ready_to_send scope excludes leads matched only by wildcard company website domains' do
    agent_lead = agent_leads(:john_in_draft)
    agent_lead.lead.update!(email: 'safe@allowed.ch', company_website: 'https://www.kienbaum.de/team')
    agent_lead.update!(
      delivery_status: 'in_sequence',
      next_send_at: 1.hour.ago
    )

    blacklist = Blacklist.create!(
      organization: agent_lead.lead.organization,
      created_by: accounts(:customer_admin),
      value: 'kienbaum.*',
      value_type: 'domain',
      source: 'manual',
      reason: 'Wildcard queued block'
    )
    BackfillBlacklistedLeadsJob.perform_now(blacklist.id)

    results = AgentLead.ready_to_send

    assert agent_lead.lead.reload.blacklisted?
    assert_not_includes results, agent_lead
  end

  test 'ready_to_send scope excludes leads with active send reservation' do
    agent_lead = agent_leads(:john_in_draft)
    agent_lead.update!(
      delivery_status: 'in_sequence',
      next_send_at: 1.hour.ago,
      send_in_progress_at: Time.current
    )

    results = AgentLead.ready_to_send

    assert_not_includes results, agent_lead
  end

  test 'ready_to_send scope includes leads with stale send reservation' do
    agent_lead = agent_leads(:john_in_draft)
    agent_lead.update!(
      delivery_status: 'in_sequence',
      next_send_at: 1.hour.ago,
      send_in_progress_at: Time.current - AgentLead::SEND_RESERVATION_TIMEOUT - 1.minute
    )

    results = AgentLead.ready_to_send

    assert_includes results, agent_lead
  end

end
