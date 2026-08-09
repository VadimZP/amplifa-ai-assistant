# frozen_string_literal: true

require 'csv'

# rubocop:disable Style/Documentation, Metrics/ClassLength, Metrics/AbcSize, Metrics/MethodLength, Metrics/BlockLength
class PlaybookLeadImportsController < ApplicationController
  before_action :set_playbook
  before_action :authorize_playbook_access

  def index
    lead_imports = playbook_import_scope.includes(:agent).order(created_at: :desc)
    lead_list_files = lead_list_file_scope.order(created_at: :desc)

    render inertia: 'Playbooks/ImportLeads', props: {
      playbook: serialize_playbook_for_customer(@playbook),
      lead_imports: serialize_lead_imports(lead_imports),
      lead_list_files: serialize_lead_list_files(lead_list_files),
      canApprove: policy(@playbook).approve?,
      canRequestChanges: policy(@playbook).request_changes?,
      canArchive: policy(@playbook).archive?
    }
  end

  def template
    csv_data = CSV.generate do |csv|
      csv << ColumnMappingService::MAPPABLE_FIELDS
      csv << ['john.smith@example.com', 'John', 'Smith', '', 'VP of Engineering', 'Acme Corp', 'acme.com',
              'https://linkedin.com/in/johnsmith', 'San Francisco, CA']
      csv << ['jane.doe@example.com', 'Jane', 'Doe', '', 'Head of Product', 'TechStartup Inc', 'techstartup.io',
              'https://linkedin.com/in/janedoe', 'New York, NY']
    end

    send_data csv_data,
              type: 'text/csv; charset=utf-8',
              disposition: 'attachment',
              filename: 'lead_import_template.csv'
  end

  def create
    lead_import_params = params.require(:lead_import).permit(:csv_file)

    unless lead_import_params[:csv_file].present?
      render json: { errors: { csv_file: ['is required'] } }, status: :unprocessable_entity
      return
    end

    column_mapping = parse_column_mapping(params[:lead_import][:column_mapping])
    import_agent = ensure_playbook_agent!

    lead_import = @playbook.organization.lead_imports.new(
      agent: import_agent,
      imported_by: current_account,
      original_filename: lead_import_params[:csv_file].original_filename || 'unknown.csv',
      file_size_bytes: lead_import_params[:csv_file].size,
      column_mapping: column_mapping,
      status: 'pending'
    )
    lead_import.csv_file.attach(lead_import_params[:csv_file])

    if lead_import.save
      ProcessLeadImportJob.perform_later(lead_import.id)

      render json: {
        lead_import: serialize_lead_import(lead_import),
        imported_agent: { id: import_agent.id, name: import_agent.name }
      }, status: :created
    else
      render json: { errors: lead_import.errors.messages }, status: :unprocessable_entity
    end
  end

  def download
    lead_import = playbook_import_scope.find(params[:lead_import_id])

    unless lead_import.csv_file.attached?
      redirect_to import_leads_playbook_path(@playbook), alert: t('admin.lead_imports.download.not_available')
      return
    end

    redirect_to rails_blob_path(lead_import.csv_file, disposition: 'attachment'), allow_other_host: true
  end

  def upload_lead_list_file
    uploaded_file = params[:lead_list_file]
    unless uploaded_file.present?
      render json: { error: 'File is required' }, status: :unprocessable_entity
      return
    end

    lead_list_file = OrganizationFileUploader.new(@playbook.organization, current_account).upload(
      uploaded_file,
      category: 'lead_list',
      playbooks: [@playbook]
    )
    AdminNotificationMailer.lead_list_file_uploaded(lead_list_file).deliver_later
    render json: { lead_list_file: serialize_lead_list_file(lead_list_file) }, status: :created
  rescue OrganizationFileUploader::ValidationError, ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def download_lead_list_file
    lead_list_file = lead_list_file_scope.find(params[:file_id])
    unless lead_list_file.file.attached?
      redirect_to import_leads_playbook_path(@playbook), alert: 'File is not available'
      return
    end

    redirect_to rails_blob_path(lead_list_file.file, disposition: 'attachment'), allow_other_host: true
  end

  private

  def set_playbook
    @playbook = policy_scope(Playbook).find(params[:id])
  end

  def authorize_playbook_access
    authorize @playbook, :show?
  end

  def parse_column_mapping(raw_column_mapping)
    return {} if raw_column_mapping.blank?

    parsed = JSON.parse(raw_column_mapping)
    sanitize_column_mapping(parsed)
  rescue JSON::ParserError
    {}
  end

  def sanitize_column_mapping(column_mapping)
    return {} unless column_mapping.is_a?(Hash)

    column_mapping.each_with_object({}) do |(csv_column, lead_field), sanitized|
      next if csv_column.blank?

      normalized_field = lead_field.to_s.strip
      next if normalized_field.blank?

      sanitized[csv_column] = normalized_field
    end
  end

  def playbook_import_scope
    policy_scope(LeadImport)
      .where(imported_by_id: current_account.id)
                               .where(agent_id: @playbook.agents.not_deleted.select(:id))
  end

  def lead_list_file_scope
    base_scope = policy_scope(OrganizationFile)
                 .lead_lists
                 .for_playbook_or_all(@playbook)
                 .where(organization_id: @playbook.organization_id)

    base_scope.where(uploaded_by_id: current_account.id)
              .or(base_scope.where(uploaded_by_id: Account.amplifa_admins.select(:id)))
  end

  def ensure_playbook_agent!
    @playbook.with_lock do
    existing_agent = @playbook.agents.not_deleted.order(:id).first
      return existing_agent if existing_agent

      created_agent = @playbook.organization.agents.create!(
        name: @playbook.product_name,
        playbook: @playbook,
        status: 'draft',
        locale: @playbook.language || @playbook.organization.locale || 'en',
        llm_model: Agent::DEFAULT_LLM_MODEL,
        created_by: current_account
      )

      AdminActivity.create!(
        account: current_account,
        organization: @playbook.organization,
        action: 'agent_created_from_playbook',
        details: {
          agent_id: created_agent.id,
          agent_name: created_agent.name,
          playbook_id: @playbook.id,
          playbook_name: @playbook.product_name,
          initiated_by_customer: true,
          source: 'playbook_import_leads'
        },
        ip_address: request.remote_ip,
        user_agent: request.user_agent
      )

      created_agent
    end
  end

  def serialize_playbook_for_customer(playbook)
    playbook.as_json(
      only: %i[id product value_proposition status language created_at updated_at approved_at],
      include: {
        approved_by: { only: %i[id first_name last_name], methods: [:full_name] }
      },
      methods: %i[personae use_cases references proof_points knowledge_base_available?]
    )
  end

  def serialize_lead_imports(lead_imports)
    lead_imports.map { |lead_import| serialize_lead_import(lead_import) }
  end

  def serialize_lead_import(lead_import)
    lead_import.as_json(
      only: %i[id original_filename status total_rows processed_rows
               created_count updated_count skipped_count blacklisted_count
               error_count created_at completed_at],
      include: {
        agent: { only: %i[id name] }
      },
      methods: [:progress_percentage]
    )
  end

  def serialize_lead_list_files(lead_list_files)
    lead_list_files.map { |lead_list_file| serialize_lead_list_file(lead_list_file) }
  end

  def serialize_lead_list_file(lead_list_file)
    lead_list_file.as_json(
      only: %i[id original_filename file_size_bytes content_type created_at]
    )
  end
end
# rubocop:enable Style/Documentation, Metrics/ClassLength, Metrics/AbcSize, Metrics/MethodLength, Metrics/BlockLength
