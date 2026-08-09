# frozen_string_literal: true

require "test_helper"

class AgentMailboxTest < ActiveSupport::TestCase
  # Tests cover basic validation (WHY: ensure junction table integrity)
  test "requires agent" do
    assignment = AgentMailbox.new(mailbox: mailboxes(:acme_mailbox_one))
    assert_not assignment.valid?
    assert_includes assignment.errors[:agent], "must exist"
  end

  test "requires mailbox" do
    assignment = AgentMailbox.new(agent: agents(:draft_agent))
    assert_not assignment.valid?
    assert_includes assignment.errors[:mailbox], "must exist"
  end

  test "valid with agent and mailbox from same org" do
    # Create a new combination that doesn't already exist
    assignment = AgentMailbox.new(
      agent: agents(:draft_agent),
      mailbox: mailboxes(:acme_mailbox_one)
    )
    assert assignment.valid?
  end

  # Tests cover uniqueness (WHY: prevent duplicate assignments)
  test "prevents duplicate mailbox in same agent" do
    existing = agent_mailboxes(:active_agent_mailbox_one)
    duplicate = AgentMailbox.new(
      agent: existing.agent,
      mailbox: existing.mailbox
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:agent_id], "already has this mailbox assigned"
  end

  test "allows same mailbox in different agents" do
    # WHY: One mailbox can be shared across multiple campaigns
    mailbox = mailboxes(:acme_mailbox_one)
    new_assignment = AgentMailbox.new(
      agent: agents(:draft_agent),
      mailbox: mailbox
    )
    assert new_assignment.valid?
  end

  # Tests cover same_organization validation (WHY: cross-org data access prevention)
  test "requires agent and mailbox to be in same organization" do
    # beta_mailbox belongs to beta org, draft_agent belongs to acme
    assignment = AgentMailbox.new(
      agent: agents(:draft_agent),
      mailbox: mailboxes(:beta_mailbox)
    )
    assert_not assignment.valid?
    assert_includes assignment.errors[:base], "Agent and Mailbox must belong to the same organization"
  end

  test "allows agent and mailbox from same organization" do
    agent = agents(:draft_agent)
    mailbox = mailboxes(:acme_mailbox_one)
    assignment = AgentMailbox.new(agent: agent, mailbox: mailbox)

    assert assignment.valid?
  end

  # Tests cover associations (WHY: ensure bidirectional relationships work)
  test "belongs to agent" do
    assignment = agent_mailboxes(:active_agent_mailbox_one)
    assert_equal agents(:active_agent), assignment.agent
  end

  test "belongs to mailbox" do
    assignment = agent_mailboxes(:active_agent_mailbox_one)
    assert_equal mailboxes(:acme_mailbox_one), assignment.mailbox
  end
end
