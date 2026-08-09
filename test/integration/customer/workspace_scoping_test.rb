# frozen_string_literal: true

require 'test_helper'

# AMP-435 §1 (plan todo 17): data-scoping-after-switch.
#
# The account below is customer_admin in org_a (primary) and customer_user in
# org_b. After POST /workspace/switch to org_b, EVERY customer surface must be
# scoped to org_b and MUST NOT leak org_a's records — even though org_a is the
# account's legacy primary organization (Account#organization).
#
# Scoping is driven by Current.organization (resolved from the session in
# ApplicationController#resolve_current_customer_workspace), so this pins the
# whole request pipeline, not a single controller.
#
# Sibling coverage already asserts the current-workspace resolution/fallback
# rules (test/controllers/workspace_switches_controller_test.rb) and the
# role-gated flag flips (dashboard/integrations/webhooks/agents). This test adds
# the missing cross-surface *data* scoping proof.
class Customer::WorkspaceScopingTest < ActionDispatch::IntegrationTest
  OrgRecords = Struct.new(:blacklist, :agent, :email_domain, :lead, :conversation, :teammate, keyword_init: true)

  private

  # Creates one distinguishable record of each type inside +organization+ so the
  # per-surface assertions can prove B is present and A is excluded.
  def seed_org_records(organization, account, label)
    suffix = SecureRandom.hex(4)

    blacklist = Blacklist.create!(
      organization: organization, created_by: account, source: 'manual',
      value: "scope-#{label}-#{suffix}.example", value_type: 'domain'
    )

    agent = Agent.create!(
      organization: organization, created_by: account,
      name: "Scope Agent #{label} #{suffix}", status: 'draft',
      locale: 'en', default_timezone: 'Europe/Berlin'
    )

    email_domain = EmailDomain.create!(
      organization: organization, provider_type: 'google',
      domain: "scope-#{label}-#{suffix}.example.com", status: 'active'
    )

    mailbox = Mailbox.create!(
      organization: organization, email_domain: email_domain,
      email: "inbox-#{label}-#{suffix}@#{email_domain.domain}",
      status: 'active', daily_send_limit: 100
    )

    lead = Lead.create!(
      organization: organization, email: "lead-#{label}-#{suffix}@example.com",
      first_name: 'Scope', last_name: label.upcase, full_name: "Scope #{label.upcase}",
      company: "Company #{label.upcase}"
    )

    # inbound_backed requires last_reply_at present and replies_count > 0.
    conversation = Conversation.create!(
      organization: organization, lead: lead, mailbox: mailbox, status: 'open',
      replies_count: 1, unread_count: 0, last_reply_at: Time.current,
      last_reply_preview: "preview-#{label}-#{suffix}"
    )

    # A distinct teammate with an active membership ONLY in this organization so
    # the team roster is provably org-scoped (after_create seeds the membership).
    teammate = Account.create!(
      email: "teammate-#{label}-#{suffix}@example.com",
      first_name: 'Teammate', last_name: label.upcase, role: 'customer_user',
      organization: organization, status: :verified,
      password_hash: RodauthApp.rodauth.allocate.password_hash('password')
    )

    OrgRecords.new(
      blacklist: blacklist, agent: agent, email_domain: email_domain,
      lead: lead, conversation: conversation, teammate: teammate
    )
  end
end
