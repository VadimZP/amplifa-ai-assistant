# frozen_string_literal: true

require "test_helper"

class GeneratedMessageTest < ActiveSupport::TestCase
  # WHY: Messages must be associated with a specific agent-lead relationship
  test "requires agent_lead" do
    msg = GeneratedMessage.new(
      sequence_step: sequence_steps(:step_one_email),
      subject: "Test",
      body: "Test body"
    )
    assert_not msg.valid?
    assert_includes msg.errors[:agent_lead], "can't be blank"
  end

  # WHY: Messages must be associated with a specific sequence step
  test "requires sequence_step" do
    msg = GeneratedMessage.new(
      agent_lead: agent_leads(:john_in_draft),
      subject: "Test",
      body: "Test body"
    )
    assert_not msg.valid?
    assert_includes msg.errors[:sequence_step], "can't be blank"
  end

  # WHY: A welcome-back email is detached from the sequence, so it must be
  # allowed to exist WITHOUT a sequence_step (AMP-264).
  test "welcome_back message is valid without a sequence_step" do
    msg = GeneratedMessage.new(
      agent_lead: agent_leads(:john_in_draft),
      message_kind: "welcome_back",
      sequence_step: nil,
      subject: "Welcome back",
      body: "Great to have you back",
      scheduled_for: Time.current
    )
    assert msg.valid?, "Expected welcome_back message to be valid without sequence_step, got: #{msg.errors.full_messages}"
  end

  # WHY: A welcome-back email is still an email, so a subject is required even
  # though it has no sequence_step (AMP-264).
  test "welcome_back message still requires a subject" do
    msg = GeneratedMessage.new(
      agent_lead: agent_leads(:john_in_draft),
      message_kind: "welcome_back",
      sequence_step: nil,
      body: "Great to have you back",
      scheduled_for: Time.current
    )
    assert_not msg.valid?
    assert_includes msg.errors[:subject], "can't be blank"
  end

  # WHY: A normal (sequence) message must still require a sequence_step (AMP-264).
  test "sequence message still requires a sequence_step" do
    msg = GeneratedMessage.new(
      agent_lead: agent_leads(:john_in_draft),
      message_kind: "sequence",
      sequence_step: nil,
      subject: "Test",
      body: "Test body"
    )
    assert_not msg.valid?
    assert_includes msg.errors[:sequence_step], "can't be blank"
  end

  # WHY: message_kind must be one of the known kinds (AMP-264).
  test "validates message_kind inclusion" do
    msg = build_message(message_kind: "bogus_kind")
    assert_not msg.valid?
    assert_includes msg.errors[:message_kind], "is not included in the list"
  end

  # WHY: welcome-back idempotency is keyed on scheduled_for, so a welcome_back
  # message without it would silently escape the unique index (AMP-264).
  test "welcome_back message requires scheduled_for" do
    msg = GeneratedMessage.new(
      agent_lead: agent_leads(:john_in_draft),
      message_kind: "welcome_back",
      sequence_step: nil,
      subject: "Welcome back",
      body: "Great to have you back",
      scheduled_for: nil
    )
    assert_not msg.valid?
    assert_includes msg.errors[:scheduled_for], "can't be blank"
  end

  # WHY: welcome-back identity/idempotency is keyed on out_of_office_period_id
  # (one welcome-back per away episode). A second welcome_back row for the same
  # period must be blocked at the DB level even when scheduled_for differs.
  # WHY: Body content is essential for any message
  test "requires body" do
    msg = GeneratedMessage.new(
      agent_lead: agent_leads(:john_in_draft),
      sequence_step: sequence_steps(:step_one_email),
      subject: "Test"
    )
    assert_not msg.valid?
    assert_includes msg.errors[:body], "can't be blank"
  end

  # WHY: Email messages must have a subject line
  test "requires subject for email steps" do
    msg = GeneratedMessage.new(
      agent_lead: agent_leads(:john_in_draft),
      sequence_step: sequence_steps(:step_one_email),
      body: "Test body"
    )
    assert_not msg.valid?
    assert_includes msg.errors[:subject], "can't be blank"
  end

  # WHY: Non-email steps (LinkedIn, etc.) don't need subjects
  test "does not require subject for non-email steps" do
    msg = GeneratedMessage.new(
      agent_lead: agent_leads(:john_in_ready),
      sequence_step: sequence_steps(:linkedin_step),
      body: "LinkedIn message body"
    )
    assert msg.valid?
  end

  # WHY: Only valid status values should be accepted
  test "validates status inclusion" do
    msg = build_message(status: "invalid_status")
    assert_not msg.valid?
    assert_includes msg.errors[:status], "is not included in the list"
  end

  # WHY: All defined statuses should be valid
  test "allows valid statuses" do
    GeneratedMessage::STATUSES.each do |status|
      msg = build_message(status: status)
      assert msg.valid?, "Expected status '#{status}' to be valid, got: #{msg.errors.full_messages}"
    end
  end

  # WHY: Prevent duplicate messages for the same lead-step combination
  test "sequence_step must be unique per agent_lead" do
    existing = generated_messages(:john_step_one_draft)
    duplicate = GeneratedMessage.new(
      agent_lead: existing.agent_lead,
      sequence_step: existing.sequence_step,
      subject: "Duplicate",
      body: "Duplicate body"
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:sequence_step_id], "already has a message for this step"
  end

  # WHY: Same step can have messages for different leads (normal operation)
  test "allows same step for different agent_leads" do
    msg = GeneratedMessage.new(
      agent_lead: agent_leads(:jane_in_draft),
      sequence_step: sequence_steps(:step_two_email),
      subject: "Test",
      body: "Test body"
    )
    assert msg.valid?
  end

  # WHY: AgentLead and SequenceStep must belong to the same agent (data integrity)
  test "agent_lead and sequence_step must belong to same agent" do
    msg = GeneratedMessage.new(
      agent_lead: agent_leads(:john_in_draft),
      sequence_step: sequence_steps(:beta_step),
      subject: "Test",
      body: "Test body"
    )
    assert_not msg.valid?
    assert_includes msg.errors[:base], "AgentLead and SequenceStep must belong to the same Agent"
  end

  # WHY: Status predicate methods for clean conditional logic
  test "draft? returns true for draft status" do
    assert generated_messages(:john_step_one_draft).draft?
    assert_not generated_messages(:jane_step_one_approved).draft?
  end

  test "approved? returns true for approved status" do
    assert generated_messages(:jane_step_one_approved).approved?
    assert_not generated_messages(:john_step_one_draft).approved?
  end

  # WHY: approve! transitions message to approved status
  test "approve! changes status to approved" do
    msg = generated_messages(:john_step_one_draft)
    assert msg.draft?
    msg.approve!
    assert msg.approved?
  end

  # WHY: mark_edited! preserves original content before edits
  test "mark_edited! stores original content and marks as edited" do
    msg = generated_messages(:john_step_one_draft)
    original_subject = msg.subject
    original_body = msg.body

    msg.mark_edited!("New subject", "New body")

    assert msg.manually_edited?
    assert_equal "New subject", msg.subject
    assert_equal "New body", msg.body
    assert_equal original_subject, msg.original_subject
    assert_equal original_body, msg.original_body
  end

  # WHY: Multiple edits should preserve only the first original
  test "mark_edited! does not overwrite original if already edited" do
    msg = generated_messages(:john_step_one_edited)
    first_original_subject = msg.original_subject

    msg.mark_edited!("Another new subject", "Another new body")

    assert_equal first_original_subject, msg.original_subject
  end

  # WHY: Revert allows undoing manual edits
  test "revert_to_original! restores original content" do
    msg = generated_messages(:john_step_one_edited)

    msg.revert_to_original!

    assert_not msg.manually_edited?
    assert_equal "Original AI subject", msg.subject
    assert_equal "Original AI generated body content...", msg.body
    assert_nil msg.original_subject
    assert_nil msg.original_body
  end

  # WHY: Revert does nothing if message wasn't edited
  test "revert_to_original! does nothing if not manually edited" do
    msg = generated_messages(:john_step_one_draft)
    original_body = msg.body

    msg.revert_to_original!

    assert_equal original_body, msg.body
    assert_not msg.manually_edited?
  end

  # WHY: Test email tracking for auditing
  test "record_test_send! records timestamp and recipient" do
    msg = generated_messages(:john_step_one_draft)
    assert_nil msg.test_sent_at

    freeze_time do
      msg.record_test_send!("test@example.com")

      assert_equal Time.current, msg.test_sent_at
      assert_equal "test@example.com", msg.test_sent_to
    end
  end

  # WHY: Cost estimation helps track AI usage
  test "generation_cost_estimate returns nil without token data" do
    msg = GeneratedMessage.new
    assert_nil msg.generation_cost_estimate
  end

  test "generation_cost_estimate calculates based on tokens" do
    msg = generated_messages(:john_step_one_draft)
    # 500 input tokens, 150 output tokens
    # Cost = (500/1M * 0.075) + (150/1M * 0.30)
    cost = msg.generation_cost_estimate
    assert_not_nil cost
    assert cost > 0
    assert cost < 0.001 # Should be very small for these token counts
  end

  # WHY: Scopes enable efficient filtering
  test "drafts scope filters draft status" do
    results = GeneratedMessage.drafts
    assert_includes results, generated_messages(:john_step_one_draft)
    assert_not_includes results, generated_messages(:jane_step_one_approved)
  end

  test "approved scope filters approved status" do
    results = GeneratedMessage.approved
    assert_includes results, generated_messages(:jane_step_one_approved)
    assert_not_includes results, generated_messages(:john_step_one_draft)
  end

  test "for_agent scope filters by agent" do
    results = GeneratedMessage.for_agent(agents(:draft_agent))
    assert_includes results, generated_messages(:john_step_one_draft)
    # john_step_one_edited is for ready_agent
    assert_not_includes results, generated_messages(:john_step_one_edited)
  end

  test "for_step scope filters by sequence step" do
    results = GeneratedMessage.for_step(sequence_steps(:step_one_email))
    assert_includes results, generated_messages(:john_step_one_draft)
    assert_not_includes results, generated_messages(:john_step_two_draft)
  end

  test "test_sent scope filters messages with test_sent_at" do
    results = GeneratedMessage.test_sent
    assert_includes results, generated_messages(:jane_step_one_approved)
    assert_not_includes results, generated_messages(:john_step_one_draft)
  end

  test "not_test_sent scope filters messages without test_sent_at" do
    results = GeneratedMessage.not_test_sent
    assert_includes results, generated_messages(:john_step_one_draft)
    assert_not_includes results, generated_messages(:jane_step_one_approved)
  end

  # WHY: body_with_signature appends sender signature for preview
  test "body_with_signature returns body with signature when assigned mailbox has sender with signature" do
    msg = generated_messages(:john_step_one_draft)
    mailbox = mailboxes(:acme_mailbox_one)
    sender = senders(:acme_john)

    mailbox.update!(sender: sender)
    msg.agent_lead.update!(assigned_mailbox: mailbox)

    result = msg.body_with_signature

    assert_includes result, msg.body
    assert_includes result, "Best regards"
    assert_includes result, sender.full_name
  end

  test "body_with_signature falls back to agent mailbox sender when no assigned mailbox" do
    msg = generated_messages(:john_step_one_draft)
    msg.agent_lead.update!(assigned_mailbox: nil)
    mailbox = mailboxes(:acme_mailbox_one)
    sender = senders(:acme_john)

    mailbox.update!(sender: sender)
    msg.agent.agent_mailboxes.create!(mailbox: mailbox)

    result = msg.body_with_signature

    assert_includes result, msg.body
    assert_includes result, "Best regards"
    assert_includes result, sender.full_name
  end

  test "body_with_signature returns just body when no assigned mailbox and no agent mailbox sender" do
    msg = generated_messages(:john_step_one_draft)
    msg.agent_lead.update!(assigned_mailbox: nil)
    msg.agent.mailboxes.each { |m| m.update!(sender: nil) }
    msg.agent.agent_mailboxes.destroy_all

    assert_equal msg.body, msg.body_with_signature
  end

  test "body_with_signature returns just body when mailbox has no sender" do
    msg = generated_messages(:john_step_one_draft)
    mailbox = mailboxes(:acme_mailbox_one)
    mailbox.update!(sender: nil)
    msg.agent_lead.update!(assigned_mailbox: mailbox)

    assert_equal msg.body, msg.body_with_signature
  end

  test "body_with_signature returns just body when sender has no signature template" do
    msg = generated_messages(:john_step_one_draft)
    mailbox = mailboxes(:acme_mailbox_one)
    sender = senders(:acme_jane)
    sender.update!(signature_template: nil)
    mailbox.update!(sender: sender)
    msg.agent_lead.update!(assigned_mailbox: mailbox)

    assert_equal msg.body, msg.body_with_signature
  end

  # WHY: Verify associations and delegates work correctly
  test "belongs to agent_lead" do
    msg = generated_messages(:john_step_one_draft)
    assert_equal agent_leads(:john_in_draft), msg.agent_lead
  end

  test "belongs to sequence_step" do
    msg = generated_messages(:john_step_one_draft)
    assert_equal sequence_steps(:step_one_email), msg.sequence_step
  end

  test "delegates lead to agent_lead" do
    msg = generated_messages(:john_step_one_draft)
    assert_equal leads(:john_doe), msg.lead
  end

  test "delegates agent to agent_lead" do
    msg = generated_messages(:john_step_one_draft)
    assert_equal agents(:draft_agent), msg.agent
  end


  # WHY: Verify sample scopes filter correctly
  test "samples scope returns only sample messages" do
    sample_msg = build_message(sample: true)
    sample_msg.save!
    non_sample_msg = generated_messages(:john_step_one_draft)

    results = GeneratedMessage.samples
    assert_includes results, sample_msg
    assert_not_includes results, non_sample_msg
  end

  test "non_samples scope returns only non-sample messages" do
    sample_msg = build_message(sample: true)
    sample_msg.save!
    non_sample_msg = generated_messages(:john_step_one_draft)

    results = GeneratedMessage.non_samples
    assert_includes results, non_sample_msg
    assert_not_includes results, sample_msg
  end

  # WHY: Verify Rails auto-generated boolean predicate
  test "sample? returns true for sample messages" do
    msg = GeneratedMessage.new(sample: true)
    assert msg.sample?

    msg2 = GeneratedMessage.new(sample: false)
    assert_not msg2.sample?
  end

  private

  def build_message(overrides = {})
    defaults = {
      agent_lead: agent_leads(:jane_in_draft),
      sequence_step: sequence_steps(:step_two_email),
      subject: "Test subject",
      body: "Test body content",
      status: "draft"
    }
    GeneratedMessage.new(defaults.merge(overrides))
  end

  def welcome_back_agent_lead_without_run
    agent_lead = run_scoped_agent_lead
    agent_lead.update_column(:current_agent_lead_run_id, nil)
    agent_lead
  end

  def run_scoped_agent_lead
    agent = Agent.create!(
      organization: organizations(:acme),
      playbook: playbooks(:approved_playbook),
      created_by: accounts(:customer_admin),
      name: "Generated Message Run Agent #{SecureRandom.hex(4)}",
      status: 'active'
    )
    SequenceStep.create!(
      agent: agent,
      position: 1,
      event_type: 'email',
      name: 'Run scoped step',
      delay_days: 0,
      subject_prompt: prompts(:generic_subject),
      body_prompt: prompts(:generic_body),
      active: true
    )
    lead = Lead.create!(
      organization: organizations(:acme),
      email: "generated-message-run-#{SecureRandom.hex(4)}@example.com"
    )

    AgentLead.create!(agent: agent, lead: lead)
  end
end
