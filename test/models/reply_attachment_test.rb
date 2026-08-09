require 'test_helper'

class ReplyAttachmentTest < ActiveSupport::TestCase
  test 'requires reply' do
    attachment = build_attachment(reply: nil)

    assert_not attachment.valid?
    assert_includes attachment.errors[:reply], 'must exist'
  end

  test 'requires original_filename' do
    attachment = build_attachment(original_filename: nil)

    assert_not attachment.valid?
    assert_includes attachment.errors[:original_filename], "can't be blank"
  end

  test 'requires content_type' do
    attachment = build_attachment(content_type: nil)

    assert_not attachment.valid?
    assert_includes attachment.errors[:content_type], "can't be blank"
  end

  test 'requires file_size_bytes' do
    attachment = build_attachment(file_size_bytes: nil)

    assert_not attachment.valid?
    assert_includes attachment.errors[:file_size_bytes], "can't be blank"
  end

  test 'requires file to be attached' do
    attachment = ReplyAttachment.new(
      reply: replies(:john_doe_reply),
      original_filename: 'sample.pdf',
      content_type: 'application/pdf',
      file_size_bytes: 1.kilobyte
    )

    assert_not attachment.valid?
    assert_includes attachment.errors[:file], 'must be attached'
  end

  test 'reply destroys dependent attachments' do
    reply = Reply.create!(
      mailbox: mailboxes(:acme_mailbox_one),
      lead: leads(:john_doe),
      api_message_id: 'reply-attachment-destroy-001',
      from_address: 'john.doe@example.com',
      received_at: Time.current,
      requires_response: true
    )
    attachment = create_attachment(reply: reply)

    assert_difference('ReplyAttachment.count', -1) do
      attachment.reply.destroy
    end
  end

  private

  def build_attachment(reply: replies(:john_doe_reply), **attributes)
    attachment = ReplyAttachment.new(
      {
        reply: reply,
        original_filename: 'sample.pdf',
        content_type: 'application/pdf',
        file_size_bytes: 1.kilobyte
      }.merge(attributes)
    )

    attach_sample_file(attachment) unless attributes[:skip_file_attachment]
    attachment
  end

  def create_attachment(**attributes)
    attachment = build_attachment(**attributes)
    attachment.save!
    attachment
  end

  def attach_sample_file(attachment)
    attachment.file.attach(
      io: StringIO.new(File.binread(Rails.root.join('test/fixtures/files/sample.pdf'))),
      filename: attachment.original_filename || 'sample.pdf',
      content_type: attachment.content_type || 'application/pdf'
    )
  end
end
