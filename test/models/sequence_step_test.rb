# frozen_string_literal: true

require 'test_helper'

class SequenceStepTest < ActiveSupport::TestCase
  # WHY: Ensure sequence steps have exactly one owning sequence
  test 'requires one owner' do
    step = SequenceStep.new(position: 1, event_type: 'email')
    assert_not step.valid?
    assert_includes step.errors[:base], 'Sequence step must belong to exactly one owner'
  end

  # WHY: Position is essential for ordering steps in a sequence
  test 'requires position' do
    step = SequenceStep.new(agent: agents(:draft_agent), event_type: 'email')
    assert_not step.valid?
    assert_includes step.errors[:position], "can't be blank"
  end

  # WHY: Position must be a positive integer (1-15 range)
  # WHY: Each position must be unique within an agent to maintain ordering
  # WHY: Same position can exist in different agents (isolation)
  # WHY: Only valid event types should be accepted
  # WHY: All defined event types should be valid
  # WHY: Delay days must be within reasonable bounds (0-30 days)
  # WHY: Name has max length constraint for UI display
  # WHY: Limit sequences to prevent overly complex campaigns
  test 'sequence cannot have more than 15 steps' do
    agent = agents(:active_agent)
    # Create 15 steps
    15.times do |i|
      SequenceStep.create!(
        agent: agent,
        position: i + 1,
        event_type: 'linkedin_visit',
        delay_days: 0
      )
    end

    # 16th step should fail
    step = SequenceStep.new(
      agent: agent,
      position: 16,
      event_type: 'linkedin_visit',
      delay_days: 0
    )
    # Position validation will fail first (max 15), but sequence length also applies
    assert_not step.valid?
  end

  # WHY: Email steps must have prompts for generation (AI mode is default)
  # WHY: Email steps must have prompts for generation
  # WHY: Non-email steps don't need prompts
  test 'non-email steps do not require prompts' do
    step = SequenceStep.new(
      agent: agents(:active_agent),
      position: 1,
      event_type: 'linkedin_message',
      delay_days: 0
    )
    assert step.valid?
  end

  # WHY: Template mode allows subject line without AI prompt
  # WHY: Template mode requires subject_template to be present
  # WHY: Verify event type predicate methods work correctly
  test 'email? returns true for email event_type' do
    assert sequence_steps(:step_one_email).email?
    assert_not sequence_steps(:linkedin_step).email?
  end

  test 'linkedin_message? returns true for linkedin_message event_type' do
    assert sequence_steps(:linkedin_step).linkedin_message?
    assert_not sequence_steps(:step_one_email).linkedin_message?
  end

  # WHY: Display name provides human-readable label for UI
  test 'display_name returns custom name when present' do
    step = sequence_steps(:step_one_email)
    assert_equal 'Initial Outreach', step.display_name
  end

  test 'display_name generates name when not set' do
    step = SequenceStep.new(position: 3, event_type: 'linkedin_visit')
    assert_equal 'Step 3: Linkedin visit', step.display_name
  end

  # WHY: Previous/next step navigation for sequence traversal
  test 'previous_step returns nil for first step' do
    step = sequence_steps(:step_one_email)
    assert_nil step.previous_step
  end

  test 'previous_step returns the step before current' do
    step = sequence_steps(:step_two_email)
    assert_equal sequence_steps(:step_one_email), step.previous_step
  end

  test 'next_step returns nil for last step' do
    step = sequence_steps(:step_four_email)
    assert_nil step.next_step
  end

  test 'next_step returns the step after current' do
    step = sequence_steps(:step_one_email)
    assert_equal sequence_steps(:step_two_email), step.next_step
  end

  test 'next_step skips inactive steps' do
    step = sequence_steps(:step_two_email)
    next_step = step.next_step
    assert_equal sequence_steps(:step_four_email), next_step, 'Should skip inactive step 3 and return step 4'
  end

  # WHY: Cumulative delay helps calculate when to send messages
  test 'cumulative_delay_days sums delays up to current step' do
    # step_one has delay_days: 0, step_two has delay_days: 3, step_three has delay_days: 7
    assert_equal 0, sequence_steps(:step_one_email).cumulative_delay_days
    assert_equal 3, sequence_steps(:step_two_email).cumulative_delay_days
    assert_equal 10, sequence_steps(:step_three_inactive).cumulative_delay_days
  end

  # WHY: Scopes enable efficient filtering
  test 'active scope filters active steps' do
    results = SequenceStep.active
    assert_includes results, sequence_steps(:step_one_email)
    assert_includes results, sequence_steps(:step_two_email)
    assert_not_includes results, sequence_steps(:step_three_inactive)
  end

  test 'email_steps scope filters email event types' do
    results = SequenceStep.email_steps
    assert_includes results, sequence_steps(:step_one_email)
    assert_not_includes results, sequence_steps(:linkedin_step)
  end

  test 'ordered scope sorts by position' do
    steps = agents(:draft_agent).sequence_steps.ordered
    positions = steps.map(&:position)
    assert_equal positions, positions.sort
  end

  test 'for_agent scope filters by agent' do
    results = SequenceStep.for_agent(agents(:draft_agent))
    assert_includes results, sequence_steps(:step_one_email)
    assert_not_includes results, sequence_steps(:beta_step)
  end

  # WHY: Verify associations work correctly
  test 'belongs to agent' do
    step = sequence_steps(:step_one_email)
    assert_equal agents(:draft_agent), step.agent
  end

  test 'has many generated_messages' do
    step = sequence_steps(:step_one_email)
    assert step.generated_messages.include?(generated_messages(:john_step_one_draft))
  end

  private

  def build_email_step(overrides = {})
    defaults = {
      agent: agents(:active_agent),
      position: 1,
      event_type: 'email',
      delay_days: 0,
      subject_prompt: prompts(:generic_subject),
      body_prompt: prompts(:generic_body)
    }
    SequenceStep.new(defaults.merge(overrides))
  end

  def build_step(overrides = {})
    defaults = {
      agent: agents(:active_agent),
      position: 1,
      delay_days: 0
    }
    SequenceStep.new(defaults.merge(overrides))
  end
end
