# frozen_string_literal: true

# Serializes organization file rows for admin Files UI and ActionCable updates.
# rubocop:disable Metrics/MethodLength, Metrics/AbcSize
class OrganizationFileSerializer
  include Rails.application.routes.url_helpers

  def initialize(organization)
    @organization = organization
  end

  def serialize(file)
    if file.is_a?(PlaybookAttachment)
      serialize_playbook_attachment(file)
    else
      serialize_organization_file(file)
    end
  end

  def serialize_many(files)
    files.map { |file| serialize(file) }
  end

  private

  attr_reader :organization

  def serialize_organization_file(file)
    {
      id: "organization_file_#{file.id}",
      record_id: file.id,
      original_filename: file.original_filename,
      display_name: file.display_name,
      file_size_bytes: file.file_size_bytes,
      content_type: file.content_type,
      source_type: file.source_type,
      source_url: file.source_url,
      source_final_url: file.source_final_url,
      source_title: file.source_title,
      source_http_status: file.source_http_status,
      category: file.category,
      summary: file.summary,
      extraction_status: file.extraction_status,
      extraction_error: file.extraction_error,
      created_at: file.created_at,
      uploaded_by: serialize_uploaded_by(file.uploaded_by),
      applies_to_all_playbooks: file.applies_to_all_playbooks?,
      playbooks: serialize_playbooks(file.playbooks.order(:id)),
      download_url: organization_file_download_url(file)
    }
  end

  def serialize_playbook_attachment(file)
    {
      id: "playbook_attachment_#{file.id}",
      record_id: file.id,
      original_filename: file.original_filename,
      display_name: file.display_name || file.original_filename,
      file_size_bytes: file.file_size_bytes,
      content_type: file.content_type,
      source_type: file.source_type,
      source_url: file.source_url,
      source_final_url: file.source_final_url,
      source_title: file.source_title,
      source_http_status: file.source_http_status,
      category: file.attachable_type,
      summary: file.summary,
      extraction_status: file.extraction_status,
      extraction_error: file.extraction_error,
      created_at: file.created_at,
      uploaded_by: serialize_uploaded_by(file.uploaded_by),
      applies_to_all_playbooks: file.applies_to_all_playbooks?,
      playbooks: serialize_playbook_attachment_playbooks(file),
      download_url: playbook_attachment_download_url(file)
    }
  end

  def serialize_uploaded_by(account)
    return nil unless account

    {
      id: account.id,
      first_name: account.first_name,
      last_name: account.last_name,
      full_name: account.full_name
    }
  end

  def serialize_playbook(playbook)
    playbook ? { id: playbook.id, product_name: playbook.product_name } : nil
  end

  def serialize_playbooks(playbooks)
    playbooks.map { |playbook| serialize_playbook(playbook) }
  end

  def serialize_playbook_attachment_playbooks(file)
    return [] if file.applies_to_all_playbooks?
    return [serialize_playbook(file.playbook)].compact unless file.knowledge_base?

    serialize_playbooks(file.assigned_playbooks.order(:id))
  end

  def organization_file_download_url(file)
    return file.source_final_url.presence || file.source_url if file.url_source?

    download_admin_organization_file_path(organization, "organization_file_#{file.id}")
  end

  def playbook_attachment_download_url(file)
    return file.source_final_url.presence || file.source_url if file.url_source?

    download_admin_organization_file_path(organization, "playbook_attachment_#{file.id}")
  end
end
# rubocop:enable Metrics/MethodLength, Metrics/AbcSize
