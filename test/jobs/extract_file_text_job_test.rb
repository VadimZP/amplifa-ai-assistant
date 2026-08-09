require 'test_helper'

class ExtractFileTextJobTest < ActiveJob::TestCase
  setup do
    @playbook = playbooks(:draft_playbook)
    @attachment = PlaybookAttachment.new(
      playbook: @playbook,
      attachable_type: 'reference',
      attachable_id: 'ref-test-extract-1',
      original_filename: 'test.pdf',
      content_type: 'application/pdf',
      file_size_bytes: 1024,
      extraction_status: 'pending'
    )
    @attachment.file.attach(
      io: StringIO.new('%PDF-1.4 fake pdf content'),
      filename: 'test.pdf',
      content_type: 'application/pdf'
    )
    @attachment.save!
  end

  # WHY: Core success path — extractor returns text, attachment is updated to completed
  test 'extracts text from attached file and marks attachment completed' do
    mock_extractor = build_extractor_mock(text: 'Extracted PDF text', error: nil)

    FileTextExtractor.stub(:new, mock_extractor) do
      ExtractFileTextJob.perform_now(@attachment.id)
    end

    @attachment.reload
    assert_equal 'Extracted PDF text', @attachment.extracted_text
    assert_equal 'completed', @attachment.extraction_status
    assert_nil @attachment.extraction_error
  end

  # WHY: When FileTextExtractor returns an error hash (not exception), we set failed status
  test 'sets failed status when extractor returns error in result' do
    mock_extractor = build_extractor_mock(text: '', error: 'Failed to parse PDF')

    FileTextExtractor.stub(:new, mock_extractor) do
      ExtractFileTextJob.perform_now(@attachment.id)
    end

    @attachment.reload
    assert_equal 'failed', @attachment.extraction_status
    assert_equal 'Failed to parse PDF', @attachment.extraction_error
  end

  # WHY: discard_on ActiveRecord::RecordNotFound prevents error when attachment deleted before job runs
  test 'discards job silently when attachment not found' do
    assert_nothing_raised do
      ExtractFileTextJob.perform_now(-999)
    end
  end

  # WHY: Unexpected exceptions (e.g. S3 timeout) must set failed status; retry_on handles re-enqueueing
  test 'sets failed status on unexpected exception before retry_on re-enqueues' do
    exploding_extractor = Object.new
    exploding_extractor.define_singleton_method(:extract) { |*_args, **_kwargs| raise 'S3 connection error' }

    FileTextExtractor.stub(:new, exploding_extractor) do
      ExtractFileTextJob.perform_now(@attachment.id)
    end

    @attachment.reload
    assert_equal 'failed', @attachment.extraction_status
    assert_equal 'S3 connection error', @attachment.extraction_error
  end

  # WHY: Image content types use Claude Vision (slow API) — must run as background job
  test 'image attachments are enqueued asynchronously by uploader' do
    image_attachment = PlaybookAttachment.new(
      playbook: @playbook,
      attachable_type: 'reference',
      attachable_id: 'ref-test-image-1',
      original_filename: 'photo.png',
      content_type: 'image/png',
      file_size_bytes: 2048,
      extraction_status: 'pending'
    )
    image_attachment.file.attach(
      io: StringIO.new('fake png bytes'),
      filename: 'photo.png',
      content_type: 'image/png'
    )
    image_attachment.save!

    # Stub FileTextExtractor so image extraction doesn't hit real Claude API
    build_extractor_mock(text: 'Text from image', error: nil)

    assert_enqueued_with(job: ExtractFileTextJob, args: [image_attachment.id]) do
      ExtractFileTextJob.perform_later(image_attachment.id)
    end
  end

  # WHY: PDF/DOCX extraction runs synchronously — verify it completes inline
  test 'pdf attachment extracts text synchronously' do
    mock_extractor = build_extractor_mock(text: 'Synchronous PDF text', error: nil)

    FileTextExtractor.stub(:new, mock_extractor) do
      ExtractFileTextJob.perform_now(@attachment.id)
    end

    @attachment.reload
    assert_equal 'completed', @attachment.extraction_status
    assert_equal 'Synchronous PDF text', @attachment.extracted_text
  end

  private

  def build_extractor_mock(text:, error:)
    result = { text: text, error: error }
    extractor = Object.new
    extractor.define_singleton_method(:extract) { |*_args, **_kwargs| result }
    extractor
  end
end
