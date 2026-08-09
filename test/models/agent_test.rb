# frozen_string_literal: true

require 'test_helper'

class AgentTest < ActiveSupport::TestCase
  # Tests cover basic validation (WHY: ensure agents have required fields)
  test 'requires name' do
    agent = Agent.new(organization: organizations(:acme), created_by: accounts(:customer_admin))
    assert_not agent.valid?
    assert_includes agent.errors[:name], "can't be blank"
  end

  test 'requires organization' do
    agent = Agent.new(name: 'Test Agent', created_by: accounts(:customer_admin))
    assert_not agent.valid?
    assert_includes agent.errors[:organization], "can't be blank"
  end

  test 'valid with required fields' do
    agent = Agent.new(name: 'Test Agent', organization: organizations(:acme), created_by: accounts(:customer_admin))
    assert agent.valid?
  end

  # Tests cover status validation (WHY: ensure valid status values)
  test 'validates status inclusion' do
    agent = Agent.new(name: 'Test', organization: organizations(:acme), created_by: accounts(:customer_admin),
                      status: 'invalid')
    assert_not agent.valid?
    assert_includes agent.errors[:status], 'is not included in the list'
  end

  test 'allows valid statuses' do
    %w[draft ready active paused completed].each do |status|
      agent = Agent.new(name: 'Test', organization: organizations(:acme), created_by: accounts(:customer_admin),
                        status: status)
      # Skip playbook validation for this test
      agent.playbook = nil
      assert agent.valid?, "Expected status '#{status}' to be valid"
    end
  end

  test 'defaults to draft status' do
    agent = Agent.new
    assert_equal 'draft', agent.status
  end

  test 'mark_deleted soft deletes agent and keeps record' do
    agent = Agent.create!(
      organization: organizations(:acme),
      playbook: playbooks(:approved_playbook),
      created_by: accounts(:customer_admin),
      name: "Soft Delete Model #{SecureRandom.hex(4)}",
      status: 'active',
      scheduled_launch_at: 1.hour.from_now
    )

    assert_no_difference 'Agent.count' do
      agent.mark_deleted!
    end

    agent.reload
    assert agent.deleted?
    assert_not_nil agent.deleted_at
    assert_not_nil agent.paused_at
    assert_nil agent.scheduled_launch_at
    assert_not agent.can_launch?
  end

  test 'mark_deleted preserves agent leads and clears in-progress sends' do
    agent = Agent.create!(
      organization: organizations(:acme),
      created_by: accounts(:customer_admin),
      name: "Soft Delete Lead Preservation #{SecureRandom.hex(4)}",
      status: 'active'
    )
    lead = Lead.create!(
      organization: agent.organization,
      email: "soft-delete-lead-preservation-#{SecureRandom.hex(4)}@example.com",
      first_name: 'Soft',
      last_name: 'Delete'
    )
    agent_lead = AgentLead.create!(agent: agent, lead: lead, send_in_progress_at: 5.minutes.ago)

    assert_no_difference 'AgentLead.count' do
      agent.mark_deleted!
    end

    assert_nil agent_lead.reload.send_in_progress_at
  end

  test 'not_deleted excludes soft deleted agents' do
    agent = Agent.create!(
      organization: organizations(:acme),
      created_by: accounts(:customer_admin),
      name: "Soft Delete Scope #{SecureRandom.hex(4)}",
      status: 'draft'
    )
    agent.mark_deleted!

    assert_not_includes Agent.not_deleted, agent
  end

  test 'defaults buying signals fields off' do
    agent = Agent.new

    assert_equal false, agent.buying_signals_enabled
    assert_equal 120, agent.buying_signals_lookback_days
  end

  test 'has paper trail enabled for updates' do
    agent = agents(:active_agent)

    assert_difference -> { agent.versions.count }, 1 do
      agent.update!(llm_model: 'openai/gpt-4.1-mini')
    end
  end

  # Tests cover playbook validation (WHY: playbook must belong to same org)
  test 'playbook must belong to same organization' do
    agent = Agent.new(
      name: 'Test',
      organization: organizations(:acme),
      created_by: accounts(:customer_admin),
      playbook: playbooks(:other_org_playbook) # Beta org's playbook
    )
    assert_not agent.valid?
    assert_includes agent.errors[:playbook], 'must belong to the same organization'
  end

  test 'accepts playbook from same organization' do
    agent = Agent.new(
      name: 'Test',
      organization: organizations(:acme),
      created_by: accounts(:customer_admin),
      playbook: playbooks(:draft_playbook)
    )
    assert agent.valid?
  end

  test 'allows nil playbook' do
    agent = Agent.new(name: 'Test', organization: organizations(:acme), created_by: accounts(:customer_admin))
    assert agent.valid?
  end

  # Tests cover approved playbook validation (WHY: only approved playbooks for ready/active agents)
  test 'playbook must be approved when changing to ready status' do
    agent = agents(:draft_agent)
    agent.playbook = playbooks(:draft_playbook)
    agent.status = 'ready'

    assert_not agent.valid?
    assert_includes agent.errors[:playbook], 'must be approved before the agent can be made ready or active'
  end

  test 'allows ready status with approved playbook' do
    agent = Agent.new(
      name: 'Test Ready',
      organization: organizations(:acme),
      created_by: accounts(:customer_admin),
      playbook: playbooks(:approved_playbook),
      status: 'ready'
    )
    assert agent.valid?
  end

  test 'allows draft status with unapproved playbook' do
    agent = Agent.new(
      name: 'Test Draft',
      organization: organizations(:acme),
      created_by: accounts(:customer_admin),
      playbook: playbooks(:draft_playbook),
      status: 'draft'
    )
    assert agent.valid?
  end

  # Tests cover can_launch? method (WHY: determine if agent is ready to run)
  test 'can_launch? returns false without leads' do
    agent = agents(:ready_agent)
    agent.agent_leads.destroy_all
    assert_not agent.can_launch?
  end

  test 'can_launch? returns false without mailboxes' do
    agent = agents(:ready_agent)
    agent.agent_mailboxes.destroy_all
    assert_not agent.can_launch?
  end

  test 'can_launch? returns false without approved playbook' do
    agent = agents(:draft_agent)
    agent.playbook = playbooks(:draft_playbook)
    assert_not agent.can_launch?
  end

  # WHY: Tests that can_launch? returns true when all requirements are met:
  # - Has leads
  # - Has active mailboxes
  # - Has approved playbook
  # - Has approved samples
  test 'can_launch? returns true with all requirements' do
    agent = agents(:ready_agent)
    # Ensure agent has leads
    Lead.create!(organization: agent.organization, email: 'launch-test@example.com').tap do |lead|
      AgentLead.create!(agent: agent, lead: lead) unless agent.leads.exists?
    end
    # Ensure agent has active mailboxes (new requirement)
    AgentMailbox.find_or_create_by!(agent: agent, mailbox: mailboxes(:acme_mailbox_one))
    # Ensure playbook is approved
    agent.playbook = playbooks(:approved_playbook)
    # Ensure samples are approved (new requirement)
    agent.update!(
      samples_generated_at: 1.day.ago,
      samples_approved_at: 1.hour.ago,
      samples_approved_by: accounts(:amplifa_admin)
    )

    assert agent.can_launch?
  end

  # Tests cover rate calculation methods (WHY: track campaign performance)
  test 'reply_rate returns 0 when contacted_count is zero' do
    agent = Agent.new(contacted_count: 0, replied_count: 0)
    assert_equal 0.0, agent.reply_rate
  end

  test 'reply_rate calculates correctly' do
    agent = agents(:active_agent)
    # contacted_count: 200, replied_count: 20
    assert_equal 10.0, agent.reply_rate
  end

  test 'meeting_rate returns 0 when contacted_count is zero' do
    agent = Agent.new(contacted_count: 0)
    assert_equal 0.0, agent.meeting_rate
  end

  test 'meeting_rate calculates correctly' do
    # meeting_rate now uses meetings_count (from Meeting model) instead of counter field
    agent = agents(:draft_agent)
    # Clear any existing meetings
    agent.meetings.destroy_all
    agent.update!(contacted_count: 100)

    # Create 5 meetings via the agent's agent_leads
    agent_lead = agent.agent_leads.first
    5.times do |_i|
      Meeting.create!(
        agent_lead: agent_lead,
        lead: agent_lead.lead,
        agent: agent,
        status: 'completed',
        meeting_type: 'demo'
      )
    end

    # 5 meetings / 100 contacted = 5%
    assert_equal 5.0, agent.meeting_rate
  end

  # Tests cover status predicate methods (WHY: convenient status checking)
  test 'draft? returns true for draft status' do
    assert agents(:draft_agent).draft?
  end

  test 'ready? returns true for ready status' do
    assert agents(:ready_agent).ready?
  end

  test 'active? returns true for active status' do
    assert agents(:active_agent).active?
  end

  test 'paused? returns true for paused status' do
    agent = Agent.new(status: 'paused')
    assert agent.paused?
  end

  test 'completed? returns true for completed status' do
    agent = Agent.new(status: 'completed')
    assert agent.completed?
  end

  # Tests cover scopes (WHY: efficient filtering for queries)
  test 'for_organization scope filters by org' do
    results = Agent.for_organization(organizations(:acme))
    assert_includes results, agents(:draft_agent)
    assert_not_includes results, agents(:other_org_agent)
  end

  test 'status scopes filter correctly' do
    assert_includes Agent.draft, agents(:draft_agent)
    assert_includes Agent.ready, agents(:ready_agent)
    assert_includes Agent.active, agents(:active_agent)
  end

  # Tests cover associations (WHY: verify model relationships)
  test 'belongs to organization' do
    assert_equal organizations(:acme), agents(:draft_agent).organization
  end

  test 'belongs to playbook optionally' do
    assert_not_nil agents(:draft_agent).playbook
    assert_nil agents(:growth_lab_agent).playbook
  end

  test 'belongs to created_by' do
    assert_equal accounts(:customer_admin), agents(:draft_agent).created_by
  end

  test 'has many agent_leads' do
    agent = agents(:draft_agent)
    assert agent.agent_leads.count >= 1
  end

  test 'has many leads through agent_leads' do
    agent = agents(:draft_agent)
    assert agent.leads.include?(leads(:john_doe))
  end

  test 'has many agent_mailboxes' do
    agent = agents(:draft_agent)
    # Mailboxes are assigned via agent_mailboxes join table
    assert agent.respond_to?(:agent_mailboxes)
  end

  test 'has many mailboxes through agent_mailboxes' do
    agent = agents(:draft_agent)
    # Mailboxes association exists
    assert agent.respond_to?(:mailboxes)
  end

  test 'has many lead_imports' do
    agent = agents(:draft_agent)
    assert agent.lead_imports.include?(lead_imports(:processing_import))
  end

  # WHY: has_many sequence_steps for building outreach sequences
  test 'has many sequence_steps' do
    agent = agents(:draft_agent)
    assert agent.sequence_steps.include?(sequence_steps(:step_one_email))
  end

  # WHY: has_many generated_messages through agent_leads
  test 'has many generated_messages through agent_leads' do
    agent = agents(:draft_agent)
    assert agent.generated_messages.include?(generated_messages(:john_step_one_draft))
  end

  # WHY: belongs_to samples_approved_by tracks who approved
  test 'belongs to samples_approved_by optionally' do
    agent = Agent.new(
      name: 'Test',
      organization: organizations(:acme),
      created_by: accounts(:customer_admin),
      samples_approved_by: accounts(:amplifa_admin)
    )
    assert agent.valid?
    assert_equal accounts(:amplifa_admin), agent.samples_approved_by
  end

  # WHY: sample_agent_leads returns first N leads for sample generation
  test 'sample_agent_leads returns limited leads' do
    agent = agents(:draft_agent)
    GeneratedMessage.where(agent_lead: agent.agent_leads).destroy_all
    agent.update!(sample_count: 1)
    samples = agent.sample_agent_leads
    assert_equal 1, samples.count
  end

  test 'sample_agent_leads breaks created_at ties by id' do
    agent = agents(:draft_agent)
    agent.agent_leads.destroy_all
    agent.update!(sample_count: 2)

    timestamp = Time.zone.parse('2026-06-12 18:22:08')
    agent_leads = 3.times.map do |index|
      lead = Lead.create!(
        organization: agent.organization,
        email: "sample-tie-#{index}-#{SecureRandom.hex(4)}@example.com",
        first_name: 'Tie',
        last_name: index.to_s
      )
      AgentLead.create!(agent: agent, lead: lead).tap do |agent_lead|
        agent_lead.update_columns(created_at: timestamp, updated_at: timestamp)
      end
    end

    assert_equal agent_leads.first(2).map(&:id), agent.sample_agent_leads.pluck(:id)
  end

  test 'sample_agent_leads excludes blacklisted leads' do
    agent = agents(:draft_agent)
    blacklisted_lead = Lead.create!(
      organization: agent.organization,
      email: "blacklisted-sample-#{SecureRandom.hex(4)}@example.com",
      first_name: 'Blocked',
      last_name: 'Lead',
      blacklisted: true,
      blacklist_reason: 'Do not contact',
      blacklisted_at: Time.current
    )
    blacklisted_agent_lead = AgentLead.create!(agent: agent, lead: blacklisted_lead)

    assert_not_includes agent.sample_agent_leads, blacklisted_agent_lead
  end

  test 'sample_agent_leads does not check live blacklist entries' do
    agent = agents(:draft_agent)
    lead = Lead.create!(
      organization: agent.organization,
      email: "live-blacklist-only-#{SecureRandom.hex(4)}@example.com",
      first_name: 'Live',
      last_name: 'Only',
      company_website: 'https://www.freshblocked.com/team'
    )
    agent_lead = AgentLead.create!(agent: agent, lead: lead)

    Blacklist.create!(
      organization: agent.organization,
      created_by: accounts(:amplifa_admin),
      value: 'freshblocked.com',
      value_type: 'domain',
      source: 'manual',
      reason: 'Blocked by company domain entry'
    )

    assert_not lead.reload.blacklisted?
    assert_includes agent.sample_generation_agent_leads, agent_lead
  end

  test 'sample_generation_agent_leads does not require precomputed buying signals summaries' do
    agent = agents(:ready_agent)

    lead_without_summary = Lead.create!(
      organization: agent.organization,
      email: "no-summary-#{SecureRandom.hex(4)}@example.com",
      first_name: 'No',
      last_name: 'Summary',
      company: 'No Summary Co',
      company_website: 'https://nosummary.example.com'
    )
    agent_lead_without_summary = AgentLead.create!(agent: agent, lead: lead_without_summary)

    assert_includes agent.sample_generation_agent_leads, agent_lead_without_summary
  end

  test 'sample_generation_agent_leads excludes leads with current-run non-sample messages' do
    agent = agents(:draft_agent)
    GeneratedMessage.where(agent_lead: agent.agent_leads).destroy_all
    agent.agent_leads.update_all(status: 'pending', generation_error: nil)
    existing_message_lead = agent.agent_leads.order(:created_at, :id).first
    step = agent.active_email_sequence_steps.first

    GeneratedMessage.create!(
      agent_lead: existing_message_lead,
      sequence_step: step,
      subject: 'Campaign subject',
      body: 'Campaign body',
      status: 'approved',
      sample: false,
      ai_model: 'gpt-5-mini'
    )

    assert_not_includes agent.sample_generation_agent_leads, existing_message_lead
  end

  test 'sample_agent_leads falls back to visible leads when tracked sample leads are blacklisted' do
    agent = agents(:draft_agent)
    GeneratedMessage.where(agent_lead: agent.agent_leads).destroy_all
    agent.update!(sample_count: 1)

    blacklisted_lead = Lead.create!(
      organization: agent.organization,
      email: "tracked-blacklisted-#{SecureRandom.hex(4)}@example.com",
      first_name: 'Blocked',
      last_name: 'Tracked',
      blacklisted: true,
      blacklist_reason: 'Do not contact',
      blacklisted_at: Time.current
    )
    blacklisted_agent_lead = AgentLead.create!(agent: agent, lead: blacklisted_lead)

    GeneratedMessage.create!(
      agent_lead: blacklisted_agent_lead,
      sequence_step: sequence_steps(:step_one_email),
      subject: 'Tracked blacklisted sample',
      body: 'Tracked blacklisted sample body',
      status: 'draft',
      sample: true,
      ai_model: 'gpt-5-mini'
    )

    samples = agent.sample_agent_leads.to_a

    assert_equal 1, samples.count
    assert_not_includes samples, blacklisted_agent_lead
  end

  test 'sample_agent_leads tops up from pending visible leads when tracked set is partial' do
    agent = agents(:draft_agent)
    GeneratedMessage.where(agent_lead: agent.agent_leads).destroy_all
    agent.update!(sample_count: 2)

    tracked_visible_lead = Lead.create!(
      organization: agent.organization,
      email: "tracked-visible-#{SecureRandom.hex(4)}@example.com",
      first_name: 'Tracked',
      last_name: 'Visible'
    )
    tracked_visible = AgentLead.create!(agent: agent, lead: tracked_visible_lead)

    blacklisted_lead = Lead.create!(
      organization: agent.organization,
      email: "partial-blacklisted-#{SecureRandom.hex(4)}@example.com",
      first_name: 'Partial',
      last_name: 'Blocked',
      blacklisted: true,
      blacklist_reason: 'Do not contact',
      blacklisted_at: Time.current
    )
    blacklisted_agent_lead = AgentLead.create!(agent: agent, lead: blacklisted_lead)

    GeneratedMessage.create!(
      agent_lead: tracked_visible,
      sequence_step: sequence_steps(:step_one_email),
      subject: 'Tracked visible sample',
      body: 'Tracked visible sample body',
      status: 'draft',
      sample: true,
      ai_model: 'gpt-5-mini'
    )

    GeneratedMessage.create!(
      agent_lead: blacklisted_agent_lead,
      sequence_step: sequence_steps(:step_one_email),
      subject: 'Tracked blacklisted sample',
      body: 'Tracked blacklisted sample body',
      status: 'draft',
      sample: true,
      ai_model: 'gpt-5-mini'
    )

    samples = agent.sample_agent_leads.to_a

    assert_equal 2, samples.count
    assert_includes samples, tracked_visible
    assert_not_includes samples, blacklisted_agent_lead
  end

  # WHY: sample_messages returns generated messages for sample leads only
  test 'sample_messages returns messages for sample leads' do
    agent = agents(:draft_agent)
    agent.update!(sample_count: 10)
    generated_messages(:john_step_one_draft).update!(sample: true)

    messages = agent.sample_messages
    assert messages.include?(generated_messages(:john_step_one_draft))
  end

  # WHY: samples_generated? checks if sample generation completed
  test 'samples_generated? returns false when samples_generated_at is nil' do
    agent = agents(:draft_agent)
    agent.samples_generated_at = nil
    assert_not agent.samples_generated?
  end

  test 'samples_generated? returns true when samples_generated_at is set' do
    agent = agents(:draft_agent)
    agent.samples_generated_at = Time.current
    assert agent.samples_generated?
  end

  # WHY: samples_approved? checks if customer approved samples
  test 'samples_approved? returns false when samples_approved_at is nil' do
    agent = agents(:draft_agent)
    agent.samples_approved_at = nil
    assert_not agent.samples_approved?
  end

  test 'samples_approved? returns true when samples_approved_at is set' do
    agent = agents(:draft_agent)
    agent.samples_approved_at = Time.current
    assert agent.samples_approved?
  end

  # WHY: ready_for_sample_generation? checks prerequisites
  test 'ready_for_sample_generation? returns false without leads' do
    agent = agents(:growth_lab_agent)
    assert_not agent.ready_for_sample_generation?
  end

  test 'ready_for_sample_generation? returns false without active email steps' do
    agent = agents(:draft_agent)
    agent.sequence_steps.destroy_all
    assert_not agent.ready_for_sample_generation?
  end

  test 'ready_for_sample_generation? returns true with leads and email steps' do
    agent = agents(:draft_agent)
    assert agent.ready_for_sample_generation?
  end

  # WHY: mark_samples_generated! records when samples were generated
  test 'mark_samples_generated! sets timestamp' do
    agent = agents(:draft_agent)
    freeze_time do
      agent.mark_samples_generated!
      assert_equal Time.current, agent.samples_generated_at
    end
  end

  # WHY: mark_samples_approved! records approval with account
  test 'mark_samples_approved! sets timestamp and approver' do
    agent = agents(:draft_agent)
    approver = accounts(:customer_admin)
    freeze_time do
      agent.mark_samples_approved!(approver)
      assert_equal Time.current, agent.samples_approved_at
      assert_equal approver, agent.samples_approved_by
    end
  end

  # WHY: mark_samples_approved! should also approve the actual sample messages
  # so that when full generation runs, the send jobs can send approved messages
  test 'mark_samples_approved! approves all draft sample messages' do
    agent = agents(:draft_agent)
    approver = accounts(:customer_admin)

    # Configure sample count
    agent.update!(sample_count: 3)

    # Clear existing sample messages and leads
    agent.agent_leads.destroy_all

    # Create sample leads and draft messages (sample_leads takes first N by created_at)
    3.times do |i|
      lead = Lead.create!(organization: agent.organization, email: "sample#{i}@test.com")
      agent_lead = AgentLead.create!(agent: agent, lead: lead)
      step = agent.sequence_steps.active.email_steps.first
      GeneratedMessage.create!(
        agent_lead: agent_lead,
        sequence_step: step,
        subject: "Test #{i}",
        body: "Body #{i}",
        status: 'draft',
        sample: true
      )
    end

    # Verify we have draft sample messages
    assert_equal 3, agent.sample_messages.where(status: 'draft').count

    # Approve samples
    agent.mark_samples_approved!(approver)

    # Verify all sample messages are now approved
    assert_equal 0, agent.sample_messages.where(status: 'draft').count
    assert_equal 3, agent.sample_messages.where(status: 'approved').count
  end

  # WHY: reset_sample_approval! clears approval state for regeneration
  test 'reset_sample_approval! clears all sample tracking fields' do
    agent = agents(:draft_agent)
    agent.update!(
      samples_generated_at: 1.day.ago,
      samples_approved_at: 12.hours.ago,
      samples_approved_by: accounts(:customer_admin)
    )

    agent.reset_sample_approval!

    assert_nil agent.samples_generated_at
    assert_nil agent.samples_approved_at
    assert_nil agent.samples_approved_by
  end

  # WHY: locale field enables language-specific message generation
  test 'locale defaults to en' do
    agent = Agent.new(name: 'Test', organization: organizations(:acme), created_by: accounts(:customer_admin))
    assert_equal 'en', agent.locale
  end

  test 'validates locale presence' do
    agent = Agent.new(name: 'Test', organization: organizations(:acme), created_by: accounts(:customer_admin),
                      locale: nil)
    assert_not agent.valid?
    assert_includes agent.errors[:locale], "can't be blank"
  end

  test 'validates locale inclusion in allowed values' do
    agent = Agent.new(name: 'Test', organization: organizations(:acme), created_by: accounts(:customer_admin),
                      locale: 'xx')
    assert_not agent.valid?
    assert_includes agent.errors[:locale], 'is not included in the list'
  end

  test 'allows valid locales' do
    SupportedLocale::ALL.each do |locale|
      agent = Agent.new(name: 'Test', organization: organizations(:acme), created_by: accounts(:customer_admin),
                        locale: locale)
      assert agent.valid?, "Expected locale '#{locale}' to be valid"
    end
  end

  # WHY: llm_model field allows per-agent AI model selection
  test 'llm_model defaults to deepseek v4 pro' do
    agent = Agent.new(name: 'Test', organization: organizations(:acme), created_by: accounts(:customer_admin))
    assert_equal 'deepseek/deepseek-v4-pro', agent.llm_model
  end

  test 'llm_model can be set to any model' do
    agent = Agent.new(
      name: 'Test',
      organization: organizations(:acme),
      created_by: accounts(:customer_admin),
      llm_model: 'gpt-4'
    )
    assert agent.valid?
    assert_equal 'gpt-4', agent.llm_model
  end

  test 'DEFAULT_LLM_MODEL constant is defined' do
    assert_equal 'deepseek/deepseek-v4-pro', Agent::DEFAULT_LLM_MODEL
  end

  # Tests cover sendable_mailbox_count method (WHY: count mailboxes eligible for sending)
  test 'sendable_mailbox_count returns correct count with qualifying mailboxes' do
    agent = agents(:draft_agent)
    agent.agent_mailboxes.destroy_all

    # Create mailboxes with different states
    ready_mailbox = mailboxes(:acme_mailbox_one)
    ready_mailbox.update!(warmup_started_at: 30.days.ago, sender_id: senders(:acme_john).id)
    agent.mailboxes << ready_mailbox

    warming_mailbox = mailboxes(:acme_mailbox_two)
    warming_mailbox.update!(warmup_started_at: 10.days.ago, sender_id: senders(:acme_john).id)
    agent.mailboxes << warming_mailbox

    # Should only count ready_mailbox (warmup_complete + has sender)
    assert_equal 1, agent.sendable_mailbox_count
  end

  test 'sendable_mailbox_count returns zero when no mailboxes qualify' do
    agent = agents(:draft_agent)
    agent.agent_mailboxes.destroy_all

    # Create mailbox without sender
    mailbox_no_sender = mailboxes(:acme_mailbox_one)
    mailbox_no_sender.update!(warmup_started_at: 30.days.ago, sender_id: nil)
    agent.mailboxes << mailbox_no_sender

    assert_equal 0, agent.sendable_mailbox_count
  end

  # Tests cover available_mailbox_capacity method (WHY: divide shared mailbox capacity by agent count)
  test 'available_mailbox_capacity divides capacity by number of active+launched agents' do
    agent1 = agents(:active_agent)
    agent2 = agents(:draft_agent)
    agent1.agent_mailboxes.destroy_all
    agent2.agent_mailboxes.destroy_all

    # Create a mailbox with 100 remaining capacity
    mailbox = mailboxes(:acme_mailbox_one)
    mailbox.update!(warmup_started_at: 30.days.ago, sender_id: senders(:acme_john).id, daily_send_limit: 100)
    agent1.mailboxes << mailbox
    agent2.mailboxes << mailbox

    # agent1 is active and launched, agent2 is draft (not launched)
    agent1.update!(status: 'active', launched_at: 5.days.ago)
    agent2.update!(status: 'draft', launched_at: nil)

    # Only agent1 counts (active + launched), so capacity = 100 / 1 = 100
    assert_equal 100, agent1.available_mailbox_capacity
  end

  test 'available_mailbox_capacity returns full capacity for exclusive mailbox' do
    agent = agents(:active_agent)
    agent.agent_mailboxes.destroy_all

    # Create a mailbox with 150 remaining capacity
    mailbox = mailboxes(:acme_mailbox_one)
    mailbox.update!(warmup_started_at: 30.days.ago, sender_id: senders(:acme_john).id, daily_send_limit: 150)
    agent.mailboxes << mailbox

    agent.update!(status: 'active', launched_at: 5.days.ago)

    # Only this agent uses the mailbox, so capacity = 150 / 1 = 150
    assert_equal 150, agent.available_mailbox_capacity
  end

  test 'available_mailbox_capacity ignores inactive agents when counting sharers' do
    agent1 = agents(:active_agent)
    agent2 = agents(:draft_agent)
    agent1.agent_mailboxes.destroy_all
    agent2.agent_mailboxes.destroy_all

    # Create a mailbox with 200 remaining capacity
    mailbox = mailboxes(:acme_mailbox_one)
    mailbox.update!(warmup_started_at: 30.days.ago, sender_id: senders(:acme_john).id, daily_send_limit: 200)
    agent1.mailboxes << mailbox
    agent2.mailboxes << mailbox

    # agent1 is active+launched, agent2 is paused (not active)
    agent1.update!(status: 'active', launched_at: 5.days.ago)
    agent2.update!(status: 'paused', launched_at: 5.days.ago)

    # Only agent1 counts (must be active), so capacity = 200 / 1 = 200
    assert_equal 200, agent1.available_mailbox_capacity
  end

  private

  def restart_test_agent
    Agent.create!(
      organization: organizations(:acme),
      playbook: playbooks(:approved_playbook),
      created_by: accounts(:customer_admin),
      name: "Restart Test Agent #{SecureRandom.hex(4)}",
      status: 'active'
    ).tap do |agent|
      SequenceStep.create!(
        agent: agent,
        position: 1,
        event_type: 'email',
        name: 'Initial restart step',
        delay_days: 0,
        subject_prompt: prompts(:generic_subject),
        body_prompt: prompts(:generic_body),
        active: true
      )
    end
  end

  def restart_test_agent_lead(agent, email:, delivery_status: 'in_sequence', blacklisted: false)
    lead = Lead.create!(
      organization: agent.organization,
      email: email,
      first_name: 'Restart',
      last_name: 'Lead',
      blacklisted: blacklisted,
      blacklist_reason: blacklisted ? 'Do not contact' : nil,
      blacklist_reason_category: blacklisted ? 'other' : nil,
      blacklisted_at: blacklisted ? Time.current : nil
    )

    AgentLead.create!(
      agent: agent,
      lead: lead,
      delivery_status: delivery_status,
      sequence_position: 2,
      next_send_at: 2.days.from_now,
      last_sent_at: 1.day.ago,
      assigned_mailbox: mailboxes(:acme_mailbox_one),
      send_in_progress_at: 5.minutes.ago,
      generation_error: 'previous error'
    )
  end

  def restart_test_generated_message(agent_lead)
    GeneratedMessage.create!(
      agent_lead: agent_lead,
      sequence_step: agent_lead.agent.sequence_steps.first,
      subject: 'Restart subject',
      body: 'Restart body',
      status: 'sent',
      sent_at: 1.day.ago,
      opened_at: 12.hours.ago,
      bounced_at: 6.hours.ago,
      bounce_reason: 'Mailbox unavailable',
      bounce_type: 'soft',
      message_id: 'message-before-restart',
      instantly_message_id: 'instantly-before-restart',
      last_send_error: 'Temporary failure',
      send_attempts: 2,
      ai_model: 'gpt-5-mini'
    )
  end
end
