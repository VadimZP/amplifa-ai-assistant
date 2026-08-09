# frozen_string_literal: true

# Uploads knowledge-base materials as playbook attachments with playbook assignment metadata.
# rubocop:disable Metrics/MethodLength
class PlaybookKnowledgeBaseUploader
  MAX_FILE_SIZE = 25.megabytes

  class ValidationError < StandardError; end

  def initialize(organization, uploaded_by)
    @organization = organization
    @uploaded_by = uploaded_by
  end

  def upload(file, playbooks: [], applies_to_all_playbooks: false)
    validate_file!(file)
    validate_assignment!(playbooks, applies_to_all_playbooks)

    attachment = build_file_attachment(file, applies_to_all_playbooks:)
    persist_attachment!(attachment, playbooks:, applies_to_all_playbooks:)
    enqueue_extraction(attachment)
    attachment
  end

  def upload_url(url, playbooks: [], applies_to_all_playbooks: false)
    validate_url!(url)
    validate_assignment!(playbooks, applies_to_all_playbooks)

    attachment = build_url_attachment(url, applies_to_all_playbooks:)
    persist_attachment!(attachment, playbooks:, applies_to_all_playbooks:)
    enqueue_extraction(attachment)
    attachment
  end

  private

  def build_file_attachment(file, applies_to_all_playbooks:)
    @organization.playbook_attachments.new(
      attachable_type: 'knowledge_base',
      attachable_id: SecureRandom.uuid,
      uploaded_by: @uploaded_by,
      original_filename: file.original_filename || 'unknown-file',
      display_name: file.original_filename || 'unknown-file',
      file_size_bytes: file.size,
      content_type: file.content_type,
      source_type: 'file',
      extraction_status: 'pending',
      applies_to_all_playbooks: applies_to_all_playbooks
    ).tap { |attachment| attachment.file.attach(file) }
  end

  def build_url_attachment(url, applies_to_all_playbooks:)
    @organization.playbook_attachments.new(
      attachable_type: 'knowledge_base',
      attachable_id: SecureRandom.uuid,
      uploaded_by: @uploaded_by,
      display_name: url,
      source_type: 'url',
      source_url: url,
      extraction_status: 'pending',
      applies_to_all_playbooks: applies_to_all_playbooks
    )
  end

  def persist_attachment!(attachment, playbooks:, applies_to_all_playbooks:)
    ActiveRecord::Base.transaction do
      attachment.assigned_playbooks = applies_to_all_playbooks ? [] : playbooks
      attachment.save!
    end
  end

  def validate_file!(file)
    raise ValidationError, 'File is required' if file.blank?
    raise ValidationError, "File too large (max #{MAX_FILE_SIZE / 1.megabyte}MB)" if file.size > MAX_FILE_SIZE
  end

  def validate_url!(url)
    raise ValidationError, 'URL is required' if url.blank?
  end

  def validate_assignment!(playbooks, applies_to_all_playbooks)
    return if applies_to_all_playbooks
    return if playbooks.present?

    raise ValidationError, 'Select at least one playbook'
  end

  def enqueue_extraction(attachment)
    ExtractFileTextJob.perform_later(attachment.id)
  end
end
# rubocop:enable Metrics/MethodLength
