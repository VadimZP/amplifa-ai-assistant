require 'test_helper'

class PlaybookFileUploaderTest < ActiveSupport::TestCase
  setup do
    @organization = organizations(:acme)
  end

  # Test validation - no file provided
  test 'raises error when no file provided' do
    uploader = PlaybookFileUploader.new(@organization, 'reference')

    error = assert_raises(PlaybookFileUploader::ValidationError) do
      uploader.upload(nil)
    end

    assert_equal 'No file provided', error.message
  end

  # Test validation - file too large
  test 'raises error when file exceeds size limit' do
    uploader = PlaybookFileUploader.new(@organization, 'reference')

    # Create a mock file that reports being too large
    large_file = Minitest::Mock.new
    large_file.expect :nil?, false
    large_file.expect :size, 11.megabytes

    error = assert_raises(PlaybookFileUploader::ValidationError) do
      uploader.upload(large_file)
    end

    assert_match(/File too large/, error.message)
  end

  # Test validation - invalid content type
  test 'raises error for invalid content type' do
    uploader = PlaybookFileUploader.new(@organization, 'reference')

    file = mock_uploaded_file(
      filename: 'malicious.exe',
      content_type: 'application/x-msdownload',
      size: 1.kilobyte
    )

    error = assert_raises(PlaybookFileUploader::ValidationError) do
      uploader.upload(file)
    end

    assert_match(/Invalid file type/, error.message)
  end

  # Test validation - invalid extension
  test 'raises error for invalid file extension' do
    uploader = PlaybookFileUploader.new(@organization, 'reference')

    file = mock_uploaded_file(
      filename: 'script.js',
      content_type: 'application/pdf', # Tries to bypass with valid content-type
      size: 1.kilobyte
    )

    error = assert_raises(PlaybookFileUploader::ValidationError) do
      uploader.upload(file)
    end

    assert_match(/Invalid file extension/, error.message)
  end

  # Test successful upload - PDF
  test 'successfully uploads valid PDF file' do
    uploader = PlaybookFileUploader.new(@organization, 'reference')

    file = mock_uploaded_file(
      filename: 'case_study.pdf',
      content_type: 'application/pdf',
      size: 500.kilobytes,
      content: 'PDF content here'
    )

    result = uploader.upload(file)

    assert result[:file_url].present?
    assert_equal 'case_study.pdf', result[:file_name]
    assert_equal 500.kilobytes, result[:file_size]
    assert result[:blob_key].present?
    assert result[:blob_key].include?("organizations/#{@organization.id}/playbooks/references/")
  end

  test 'creates playbook attachment for reference uploads when playbook context is provided' do
    uploader = PlaybookFileUploader.new(@organization, 'reference')
    playbook = playbooks(:draft_playbook)

    file = mock_uploaded_file(
      filename: 'case_study.pdf',
      content_type: 'application/pdf',
      size: 500.kilobytes,
      content: 'PDF content here'
    )

    result = nil

    assert_difference('PlaybookAttachment.count', 1) do
      result = uploader.upload(file, playbook: playbook, attachable_id: 'ref-upload-test')
    end

    attachment = result[:playbook_attachment]

    assert_instance_of PlaybookAttachment, attachment
    assert_equal playbook, attachment.playbook
    assert_equal 'reference', attachment.attachable_type
    assert_equal 'ref-upload-test', attachment.attachable_id
    assert_equal 'case_study.pdf', attachment.original_filename
    assert_equal 'application/pdf', attachment.content_type
    assert_equal 500.kilobytes, attachment.file_size_bytes
    assert_equal 'pending', attachment.extraction_status
    assert attachment.file.attached?
    assert_equal result[:blob_key], attachment.file.blob.key
  end

  test 'creates playbook attachment for proof point uploads when playbook context is provided' do
    uploader = PlaybookFileUploader.new(@organization, 'proof_point')
    playbook = playbooks(:draft_playbook)

    file = mock_uploaded_file(
      filename: 'chart.png',
      content_type: 'image/png',
      size: 200.kilobytes,
      content: 'PNG content'
    )

    result = nil

    assert_difference('PlaybookAttachment.count', 1) do
      result = uploader.upload(file, playbook: playbook, attachable_id: 'proof-upload-test')
    end

    attachment = result[:playbook_attachment]

    assert_equal 'proof_point', attachment.attachable_type
    assert_equal 'proof-upload-test', attachment.attachable_id
    assert_equal 'chart.png', attachment.original_filename
    assert_equal 'image/png', attachment.content_type
    assert_equal 200.kilobytes, attachment.file_size_bytes
    assert attachment.file.attached?
  end

  # Test successful upload - image
  test 'successfully uploads valid image file' do
    uploader = PlaybookFileUploader.new(@organization, 'proof_point')

    file = mock_uploaded_file(
      filename: 'chart.png',
      content_type: 'image/png',
      size: 200.kilobytes,
      content: 'PNG content'
    )

    result = uploader.upload(file)

    assert result[:file_url].present?
    assert_equal 'chart.png', result[:file_name]
    assert result[:blob_key].include?("organizations/#{@organization.id}/playbooks/proof_points/")
  end

  # Test successful upload - Word document
  test 'successfully uploads valid DOCX file' do
    uploader = PlaybookFileUploader.new(@organization, 'reference')

    file = mock_uploaded_file(
      filename: 'testimonial.docx',
      content_type: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      size: 100.kilobytes,
      content: 'DOCX content'
    )

    result = uploader.upload(file)

    assert result[:file_url].present?
    assert_equal 'testimonial.docx', result[:file_name]
  end

  # Test that file type is included in path
  test 'uses correct path for reference files' do
    uploader = PlaybookFileUploader.new(@organization, 'reference')

    file = mock_uploaded_file(
      filename: 'doc.pdf',
      content_type: 'application/pdf',
      size: 1.kilobyte,
      content: 'test'
    )

    result = uploader.upload(file)

    assert result[:blob_key].include?('/references/')
  end

  test 'uses correct path for proof_point files' do
    uploader = PlaybookFileUploader.new(@organization, 'proof_point')

    file = mock_uploaded_file(
      filename: 'doc.pdf',
      content_type: 'application/pdf',
      size: 1.kilobyte,
      content: 'test'
    )

    result = uploader.upload(file)

    assert result[:blob_key].include?('/proof_points/')
  end

  test 'file_url uses a same-origin blob path' do
    uploader = PlaybookFileUploader.new(@organization, 'reference')

    file = mock_uploaded_file(
      filename: 'doc.pdf',
      content_type: 'application/pdf',
      size: 1.kilobyte,
      content: 'test'
    )

    result = uploader.upload(file)

    assert result[:file_url].present?
    assert_match %r{^/rails/active_storage/blobs/redirect/}, result[:file_url]
  end

  private

  # Helper to create a mock uploaded file with tempfile
  # Uses a real Rack::Test::UploadedFile or struct to avoid mock expectation issues
  def mock_uploaded_file(filename:, content_type:, size:, content: 'test content')
    tempfile = Tempfile.new([filename, File.extname(filename)])
    tempfile.write(content)
    # Pad to requested size if content is shorter
    remaining = size - content.length
    tempfile.write('x' * remaining) if remaining > 0
    tempfile.rewind

    # Use a simple struct instead of mock to avoid call-count issues
    MockUploadedFile.new(
      original_filename: filename,
      content_type: content_type,
      size: size,
      tempfile: tempfile
    )
  end

  # Simple class that behaves like an uploaded file
  class MockUploadedFile
    attr_reader :original_filename, :content_type, :size, :tempfile

    def initialize(original_filename:, content_type:, size:, tempfile:)
      @original_filename = original_filename
      @content_type = content_type
      @size = size
      @tempfile = tempfile
    end

    def nil?
      false
    end
  end
end
