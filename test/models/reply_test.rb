# frozen_string_literal: true

require 'test_helper'

class ReplyTest < ActiveSupport::TestCase
  # Tests cover basic validation (WHY: ensure reply data integrity)
  test 'requires api_message_id' do
    reply = Reply.new(
      lead: leads(:john_doe),
      mailbox: mailboxes(:acme_mailbox_one),
      from_address: 'test@example.com',
      received_at: Time.current
    )
    assert_not reply.valid?
    assert_includes reply.errors[:api_message_id], "can't be blank"
  end

  test 'requires from_address' do
    reply = Reply.new(
      lead: leads(:john_doe),
      mailbox: mailboxes(:acme_mailbox_one),
      api_message_id: 'unique-id-123',
      received_at: Time.current
    )
    assert_not reply.valid?
    assert_includes reply.errors[:from_address], "can't be blank"
  end

  test 'requires received_at' do
    reply = Reply.new(
      lead: leads(:john_doe),
      mailbox: mailboxes(:acme_mailbox_one),
      api_message_id: 'unique-id-123',
      from_address: 'test@example.com'
    )
    assert_not reply.valid?
    assert_includes reply.errors[:received_at], "can't be blank"
  end

  # WHY: Lead is now optional for unassigned replies needing manual assignment
  test 'lead is optional' do
    reply = Reply.new(
      mailbox: mailboxes(:acme_mailbox_one),
      api_message_id: 'unique-id-123',
      from_address: 'test@example.com',
      received_at: Time.current
    )
    assert reply.valid?
  end

  test 'requires mailbox' do
    reply = Reply.new(
      lead: leads(:john_doe),
      api_message_id: 'unique-id-123',
      from_address: 'test@example.com',
      received_at: Time.current
    )
    assert_not reply.valid?
    assert_includes reply.errors[:mailbox], 'must exist'
  end

  # Tests cover uniqueness (WHY: prevent duplicate message imports)
  test 'prevents duplicate api_message_id' do
    existing = replies(:john_doe_reply)
    duplicate = Reply.new(
      api_message_id: existing.api_message_id,
      lead: existing.lead,
      mailbox: existing.mailbox,
      from_address: existing.from_address,
      received_at: Time.current
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:api_message_id], 'has already been taken'
  end

  # Tests cover bounce_type validation (WHY: only allow valid bounce types)
  test 'validates bounce_type inclusion' do
    reply = replies(:hard_bounce_reply)
    reply.bounce_type = 'invalid'
    assert_not reply.valid?
    assert_includes reply.errors[:bounce_type], 'is not included in the list'
  end

  test 'allows nil bounce_type' do
    reply = replies(:john_doe_reply)
    reply.bounce_type = nil
    assert reply.valid?
  end

  # Tests cover type predicates (WHY: convenient type checking)
  test 'bounce? returns true for bounces' do
    assert replies(:hard_bounce_reply).bounce?
    assert_not replies(:john_doe_reply).bounce?
  end

  test 'hard_bounce? returns true for hard bounces' do
    assert replies(:hard_bounce_reply).hard_bounce?
  end

  test 'out_of_office? returns true for OOO messages' do
    assert replies(:jane_ooo_reply).out_of_office?
    assert_not replies(:john_doe_reply).out_of_office?
  end

  # Tests cover response tracking (WHY: track follow-up status)
  test 'responded? returns true when responded' do
    assert replies(:responded_reply).responded?
    assert_not replies(:john_doe_reply).responded?
  end

  test 'needs_response? returns true when requires_response and not responded' do
    assert replies(:john_doe_reply).needs_response?
    assert_not replies(:responded_reply).needs_response?
    assert_not replies(:jane_ooo_reply).needs_response? # OOO doesn't require response
  end

  test 'mark_responded! updates status and timestamp' do
    reply = replies(:john_doe_reply)
    reply.mark_responded!

    assert reply.responded?
    assert_not_nil reply.responded_at
  end

  test 'mark_no_response_needed! clears requires_response' do
    reply = replies(:john_doe_reply)
    reply.mark_no_response_needed!

    assert_not reply.requires_response
    assert_not reply.needs_response?
  end

  # Tests cover body_preview (WHY: show truncated preview in UI)
  test 'body_preview returns truncated plain text' do
    reply = replies(:john_doe_reply)
    assert reply.body_preview.present?
    assert reply.body_preview.length <= 200
  end

  test 'body_preview strips HTML tags' do
    reply = Reply.new(body_html: '<p>Hello <strong>world</strong></p>')
    assert_equal 'Hello world', reply.body_preview
  end

  test 'body_preview returns nil when no body' do
    reply = Reply.new
    assert_nil reply.body_preview
  end

  test 'body_plain_for_classification prefers stripped plain text' do
    reply = Reply.new(
      body_plain: "Please remove me.\n\n> quoted outbound",
      body_html: '<p>HTML fallback</p>'
    )

    assert_equal 'Please remove me.', reply.body_plain_for_classification
  end

  test 'body_plain_for_classification converts html-only replies to plain text' do
    reply = Reply.new(
      body_html: <<~HTML
        <html>
          <head><style>@font-face { font-family: Aptos; }</style></head>
          <body>
            <!-- ignored -->
            <p>Guten Morgen Herr Filipiak,</p>
            <p>aktuell sehe ich bei uns dafür keinen Bedarf.</p>
            <p>Von: Sender &lt;sender@example.com&gt;</p>
            <p>Quoted outbound text</p>
          </body>
        </html>
      HTML
    )

    assert_equal "Guten Morgen Herr Filipiak,\naktuell sehe ich bei uns dafür keinen Bedarf.",
                 reply.body_plain_for_classification
  end

  # Tests cover scopes (WHY: efficient filtering for queries)
  test 'unresponded scope returns unresponded replies needing response' do
    results = Reply.unresponded
    assert(results.all? { |r| !r.responded && r.requires_response })
  end

  test 'requires_attention scope excludes bounces and OOO' do
    results = Reply.requires_attention
    assert results.none?(&:bounce?)
    assert results.none?(&:out_of_office?)
  end

  test 'bounces scope returns only bounces' do
    results = Reply.bounces
    assert results.all?(&:bounce?)
  end

  test 'hard_bounces scope returns only hard bounces' do
    results = Reply.hard_bounces
    assert results.all?(&:hard_bounce?)
  end

  test 'out_of_office scope returns only OOO messages' do
    results = Reply.out_of_office
    assert results.all?(&:out_of_office?)
  end

  test 'for_mailbox scope filters by mailbox' do
    results = Reply.for_mailbox(mailboxes(:acme_mailbox_one))
    assert(results.all? { |r| r.mailbox_id == mailboxes(:acme_mailbox_one).id })
  end

  test 'for_lead scope filters by lead' do
    results = Reply.for_lead(leads(:john_doe))
    assert(results.all? { |r| r.lead_id == leads(:john_doe).id })
  end

  # Tests cover associations (WHY: ensure relationships work)
  test 'belongs to lead' do
    reply = replies(:john_doe_reply)
    assert_equal leads(:john_doe), reply.lead
  end

  test 'belongs to mailbox' do
    reply = replies(:john_doe_reply)
    assert_equal mailboxes(:acme_mailbox_one), reply.mailbox
  end

  test 'optionally belongs to generated_message' do
    reply_with_msg = replies(:john_doe_reply)
    assert reply_with_msg.generated_message.present?

    reply_without_msg = replies(:hard_bounce_reply)
    assert_nil reply_without_msg.generated_message
  end

  # WHY: Conversation association enables threaded view grouping
  test 'optionally belongs to conversation' do
    reply_with_conv = replies(:john_doe_reply)
    assert reply_with_conv.conversation.present?

    reply_without_conv = replies(:hard_bounce_reply)
    assert_nil reply_without_conv.conversation
  end

  # WHY: Warmup detection helps filter out deliverability test emails
  test 'warmup? returns true for warmup emails' do
    assert replies(:warmup_reply).warmup?
    assert_not replies(:john_doe_reply).warmup?
  end

  test 'warmup scope returns only warmup emails' do
    results = Reply.warmup
    assert results.all?(&:warmup?)
  end

  test 'not_warmup scope excludes warmup emails' do
    results = Reply.not_warmup
    assert results.none?(&:warmup?)
  end

  # WHY: Human scope filters out automated replies (bounces, OOO, warmup)
  test 'human scope returns only human replies' do
    results = Reply.human
    assert results.none?(&:bounce?)
    assert results.none?(&:out_of_office?)
    assert results.none?(&:warmup?)
  end

  test 'human scope includes normal replies' do
    results = Reply.human
    assert_includes results, replies(:john_doe_reply)
  end

  test 'human scope excludes bounces' do
    results = Reply.human
    assert_not_includes results, replies(:hard_bounce_reply)
    assert_not_includes results, replies(:bounce_conversation_reply)
  end

  test 'human scope excludes out of office' do
    results = Reply.human
    assert_not_includes results, replies(:jane_ooo_reply)
  end

  test 'human scope excludes warmup' do
    results = Reply.human
    assert_not_includes results, replies(:warmup_reply)
  end

  # WHY: Read status tracking enables unread count for conversations
  test 'read? returns true when read_at is set' do
    assert replies(:jane_ooo_reply).read?
    assert_not replies(:john_doe_reply).read?
  end

  test 'unread? returns true when read_at is nil' do
    assert replies(:john_doe_reply).unread?
    assert_not replies(:jane_ooo_reply).unread?
  end

  test 'unread scope returns only unread replies' do
    results = Reply.unread
    assert results.all?(&:unread?)
  end

  test 'read scope returns only read replies' do
    results = Reply.read
    assert results.all?(&:read?)
  end

  test 'mark_read! sets read_at and refreshes conversation counters' do
    reply = replies(:john_doe_reply)
    conversation = reply.conversation

    assert reply.unread?
    initial_unread = conversation.unread_count

    reply.mark_read!

    assert reply.read?
    assert_not_nil reply.read_at
    conversation.reload
    assert conversation.unread_count < initial_unread
  end

  test 'mark_read! is idempotent for already read replies' do
    reply = replies(:jane_ooo_reply)
    original_read_at = reply.read_at

    reply.mark_read!

    assert_equal original_read_at, reply.read_at
  end

  # WHY: Lead is optional to support unassigned replies from plus-addressed emails
  test 'allows nil lead for unassigned replies' do
    reply = Reply.new(
      mailbox: mailboxes(:acme_mailbox_one),
      api_message_id: 'unassigned-id-123',
      from_address: 'test@example.com',
      received_at: Time.current,
      needs_lead_assignment: true
    )
    assert reply.valid?
  end

  test 'needs_assignment scope returns replies needing lead assignment' do
    unassigned = Reply.create!(
      mailbox: mailboxes(:acme_mailbox_one),
      api_message_id: 'needs-assign-001',
      from_address: 'unknown@example.com',
      received_at: Time.current,
      needs_lead_assignment: true
    )

    results = Reply.needs_assignment
    assert_includes results, unassigned
    assert(results.none? { |r| !r.needs_lead_assignment? })
  end

  test 'needs_human_assignment excludes non-human replies' do
    mailbox = mailboxes(:acme_mailbox_one)
    human = Reply.create!(
      mailbox: mailbox,
      api_message_id: 'human-assign-001',
      from_address: 'human@example.com',
      received_at: Time.current,
      needs_lead_assignment: true
    )
    Reply.create!(
      mailbox: mailbox,
      api_message_id: 'ooo-assign-001',
      from_address: 'ooo@example.com',
      received_at: Time.current,
      needs_lead_assignment: true,
      is_out_of_office: true,
      requires_response: false
    )
    Reply.create!(
      mailbox: mailbox,
      api_message_id: 'bounce-assign-001',
      from_address: 'bounce@example.com',
      received_at: Time.current,
      needs_lead_assignment: true,
      is_bounce: true,
      requires_response: false
    )
    Reply.create!(
      mailbox: mailbox,
      api_message_id: 'warmup-assign-001',
      from_address: 'warmup@example.com',
      received_at: Time.current,
      needs_lead_assignment: true,
      is_warmup: true,
      requires_response: false
    )

    results = Reply.needs_human_assignment

    assert_includes results, human
    assert_equal [human.id], results.pluck(:id)
  end

  test 'assign_lead! assigns lead and creates conversation' do
    mailbox = mailboxes(:acme_mailbox_one)
    unassigned = Reply.create!(
      mailbox: mailbox,
      api_message_id: 'to-assign-001',
      from_address: 'pending@example.com',
      received_at: Time.current,
      needs_lead_assignment: true
    )

    new_lead = Lead.create!(
      email: 'newassigned@example.com',
      organization: mailbox.organization
    )

    assert_difference 'Conversation.count', 1 do
      unassigned.assign_lead!(new_lead)
    end

    unassigned.reload
    assert_equal new_lead, unassigned.lead
    assert_not unassigned.needs_lead_assignment?
    assert_not_nil unassigned.conversation
    assert_equal new_lead, unassigned.conversation.lead
  end

  test 'assign_lead! raises error when lead is nil' do
    unassigned = Reply.create!(
      mailbox: mailboxes(:acme_mailbox_one),
      api_message_id: 'fail-assign-001',
      from_address: 'pending@example.com',
      received_at: Time.current,
      needs_lead_assignment: true
    )

    assert_raises ArgumentError do
      unassigned.assign_lead!(nil)
    end
  end

  test 'assign_lead! raises error when reply already has a lead' do
    reply = replies(:john_doe_reply)

    assert_raises ArgumentError do
      reply.assign_lead!(leads(:jane_smith))
    end
  end
end
