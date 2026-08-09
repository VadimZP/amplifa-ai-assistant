# frozen_string_literal: true

# Uploads organization-scoped files and starts text extraction/summary generation.
# rubocop:disable Metrics/ClassLength
class OrganizationFileUploader
  MAX_FILE_SIZE = 25.megabytes
  CATEGORIES = OrganizationFile::CATEGORIES

  class ValidationError < StandardError; end

  def initialize(organization, uploaded_by)
    @organization = organization
    @uploaded_by = uploaded_by
  end

  def upload(file, category:, playbooks: [], applies_to_all_playbooks: false)
    ensure_assignment_schema_loaded!
    validate_file!(file)
    validate_category!(category)
    validate_assignment!(playbooks, applies_to_all_playbooks)

    organization_file = create_organization_file!(file, category:, playbooks:, applies_to_all_playbooks:)
    enqueue_extraction(organization_file)
    organization_file
  end

  def upload_url(url, category:, playbooks: [], applies_to_all_playbooks: false)
    ensure_assignment_schema_loaded!
    validate_url!(url)
    validate_category!(category)
    validate_assignment!(playbooks, applies_to_all_playbooks)

    organization_file = create_organization_url!(url, category:, playbooks:, applies_to_all_playbooks:)
    enqueue_extraction(organization_file)
    organization_file
  end

  private

  def ensure_assignment_schema_loaded!
    columns = OrganizationFile.column_names
    return if columns.include?('applies_to_all_playbooks') && columns.include?('source_type')

    OrganizationFile.reset_column_information
    OrganizationFilePlaybook.reset_column_information
  end

  def build_organization_file(file, category:, applies_to_all_playbooks:)
    attributes = file_attributes(file).merge(file_source_attributes(category, applies_to_all_playbooks))
    @organization.organization_files.new(attributes)
  end

  def file_source_attributes(category, applies_to_all_playbooks)
    {
      category: category,
      applies_to_all_playbooks: applies_to_all_playbooks,
      source_type: 'file',
      uploaded_by: @uploaded_by
    }
  end

  def file_attributes(file)
    filename = file.original_filename || 'unknown-file'
    {
      original_filename: filename,
      display_name: filename,
      file_size_bytes: file.size,
      content_type: file.content_type,
      extraction_status: 'pending'
    }
  end

  def build_organization_url(url, category:, applies_to_all_playbooks:)
    @organization.organization_files.new(
      category: category,
      applies_to_all_playbooks: applies_to_all_playbooks,
      source_type: 'url',
      source_url: url,
      display_name: url,
      uploaded_by: @uploaded_by,
      extraction_status: 'pending'
    )
  end

  def create_organization_file!(file, category:, playbooks:, applies_to_all_playbooks:)
    organization_file = build_organization_file(file, category:, applies_to_all_playbooks:)
    organization_file.file.attach(file)
    ActiveRecord::Base.transaction do
      organization_file.save!
      organization_file.playbooks = applies_to_all_playbooks ? [] : playbooks
    end
    organization_file
  end

  def create_organization_url!(url, category:, playbooks:, applies_to_all_playbooks:)
    organization_file = build_organization_url(url, category:, applies_to_all_playbooks:)
    ActiveRecord::Base.transaction do
      organization_file.save!
      organization_file.playbooks = applies_to_all_playbooks ? [] : playbooks
    end
    organization_file
  end

  def validate_file!(file)
    raise ValidationError, 'File is required' if file.blank?
    raise ValidationError, "File too large (max #{MAX_FILE_SIZE / 1.megabyte}MB)" if file.size > MAX_FILE_SIZE
  end

  def validate_category!(category)
    return if CATEGORIES.include?(category)

    raise ValidationError, 'Invalid file category'
  end

  def validate_url!(url)
    raise ValidationError, 'URL is required' if url.blank?
  end

  def validate_assignment!(playbooks, applies_to_all_playbooks)
    return if applies_to_all_playbooks
    return if playbooks.present?

    raise ValidationError, 'Select at least one playbook'
  end

  def enqueue_extraction(organization_file)
    ExtractOrganizationFileSummaryJob.perform_later(organization_file.id)
  end
end
# rubocop:enable Metrics/ClassLength
