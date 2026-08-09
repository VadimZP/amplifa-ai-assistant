require 'test_helper'

class SentReplyAttachmentTest < ActiveSupport::TestCase
  test 'requires an attached file' do
    attachment = SentReplyAttachment.new(
      sent_reply: sent_replies(:draft_reply),
      original_filename: 'sample.pdf',
      content_type: 'application/pdf',
      file_size_bytes: 128
    )

    assert_not attachment.valid?
    assert_includes attachment.errors[:file], 'must be attached'
  end

  test 'rejects files larger than 10 megabytes' do
    attachment = SentReplyAttachment.new(
      sent_reply: sent_replies(:draft_reply),
      original_filename: 'too-big.pdf',
      content_type: 'application/pdf',
      file_size_bytes: 10.megabytes + 1
    )
    attachment.file.attach(
      io: File.open(Rails.root.join('test/fixtures/files/sample.pdf')),
      filename: 'sample.pdf',
      content_type: 'application/pdf'
    )

    assert_not attachment.valid?
    assert_includes attachment.errors[:file_size_bytes], 'must be less than or equal to 10485760'
  end
end
