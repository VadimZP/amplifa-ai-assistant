# Service for uploading files to playbook references and proof points
# Files are stored in S3 via ActiveStorage with organization-scoped paths
# Returns metadata for storing in Playbook JSONB fields
class PlaybookFileUploader
  MAX_FILE_SIZE = 10.megabytes
  ALLOWED_CONTENT_TYPES = [
    'application/pdf',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'image/png',
    'image/jpeg',
    'image/jpg',
    'image/gif'
  ].freeze

  ALLOWED_EXTENSIONS = %w[.pdf .doc .docx .png .jpg .jpeg .gif].freeze

  class ValidationError < StandardError; end

  def initialize(organization, file_type)
    @organization = organization
    @file_type = file_type # 'reference' or 'proof_point'
  end

  def upload(file, playbook: nil, attachable_id: nil)
    validate_file!(file)

    # Generate unique filename preserving original extension
    extension = File.extname(file.original_filename).downcase
    filename = "#{SecureRandom.uuid}#{extension}"

    # Build S3 key with organization and file type for logical grouping
    key = "organizations/#{@organization.id}/playbooks/#{@file_type.pluralize}/#{filename}"

    # Upload to S3 via ActiveStorage
    blob = ActiveStorage::Blob.create_and_upload!(
      io: file.tempfile,
      filename: filename,
      content_type: file.content_type,
      key: key,
      metadata: {
        organization_id: @organization.id.to_s,
        file_type: @file_type,
        original_filename: file.original_filename
      }
    )

    playbook_attachment = create_playbook_attachment(blob, file, playbook: playbook, attachable_id: attachable_id)

    # Return URL and metadata for storing in JSONB
    {
      file_url: rails_blob_path(blob),
      file_name: file.original_filename,
      file_size: file.size,
      blob_key: blob.key,
      playbook_attachment: playbook_attachment
    }
  end

  private

  def validate_file!(file)
    raise ValidationError, 'No file provided' if file.nil?
    raise ValidationError, "File too large (max #{MAX_FILE_SIZE / 1.megabyte}MB)" if file.size > MAX_FILE_SIZE

    unless ALLOWED_CONTENT_TYPES.include?(file.content_type)
      raise ValidationError, 'Invalid file type. Allowed: PDF, DOC, DOCX, PNG, JPG, GIF'
    end

    extension = File.extname(file.original_filename).downcase
    return if ALLOWED_EXTENSIONS.include?(extension)

    raise ValidationError, "Invalid file extension. Allowed: #{ALLOWED_EXTENSIONS.join(', ')}"
  end

  def rails_blob_path(blob)
    url_helpers = Rails.application.routes.url_helpers

    url_helpers.rails_blob_path(blob, only_path: true)
  end

  def create_playbook_attachment(blob, file, playbook:, attachable_id:)
    return if playbook.blank? || attachable_id.blank?

    attachment = PlaybookAttachment.find_or_initialize_by(
      playbook: playbook,
      attachable_type: @file_type,
      attachable_id: attachable_id
    )

    attachment.assign_attributes(
      original_filename: file.original_filename,
      content_type: file.content_type,
      file_size_bytes: file.size,
      extraction_status: 'pending',
      extraction_error: nil
    )
    attachment.file.attach(blob)
    attachment.save!

    enqueue_extraction(attachment)
    attachment
  end

  def enqueue_extraction(attachment)
    if attachment.content_type&.start_with?('image/')
      ExtractFileTextJob.perform_later(attachment.id)
    else
      ExtractFileTextJob.perform_now(attachment.id)
    end
  end
end
