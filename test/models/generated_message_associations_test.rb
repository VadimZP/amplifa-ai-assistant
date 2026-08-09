# frozen_string_literal: true

require 'test_helper'

class GeneratedMessageAssociationsTest < ActiveSupport::TestCase
  test 'destroy nullifies all linked replies' do
    msg = generated_messages(:john_step_one_draft)

    reply_one = Reply.create!(
      generated_message: msg,
      lead: msg.lead,
      mailbox: msg.mailbox || mailboxes(:acme_mailbox_one),
      api_message_id: "test-nullify-1-#{SecureRandom.hex(4)}",
      from_address: msg.lead.email,
      received_at: Time.current
    )

    reply_two = Reply.create!(
      generated_message: msg,
      lead: msg.lead,
      mailbox: msg.mailbox || mailboxes(:acme_mailbox_one),
      api_message_id: "test-nullify-2-#{SecureRandom.hex(4)}",
      from_address: msg.lead.email,
      received_at: Time.current
    )

    msg.destroy!

    assert_nil reply_one.reload.generated_message_id
    assert_nil reply_two.reload.generated_message_id
  end
end
