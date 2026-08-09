# Customers can view, approve, request changes, and archive playbooks
# for their organization. This is separate from Admin::PlaybooksController
# which has full CRUD capabilities.
class PlaybooksController < ApplicationController
  before_action :set_playbook,
                only: %i[show update approve request_changes archive upload_file knowledge_base
                          knowledge_base_files knowledge_base_file_extract download_knowledge_base_file]

  def index
    authorize :playbook, :index?

    # from their own organization
    playbooks = policy_scope(Playbook).includes(:approved_by)
                                      .order(created_at: :desc)

    playbooks = playbooks.where(status: params[:status]) if params[:status].present?
    playbooks = playbooks.for_product_name(params[:product_name]) if params[:product_name].present?

    render inertia: 'Playbooks/Index', props: {
      playbooks: playbooks.as_json(
        only: %i[id product status language created_at updated_at approved_at],
        include: {
          approved_by: { only: %i[id first_name last_name], methods: [:full_name] }
        },
        methods: %i[persona_count use_case_count reference_count proof_point_count]
      ),
      product_names: policy_scope(Playbook).pluck(Arel.sql("DISTINCT product->>'name'")).compact.sort,
      organization_website: current_organization.website,
      canCreatePlaybook: policy(:playbook).create_from_generation?,
      filters: {
        status: params[:status],
        product_name: params[:product_name]
      }
    }
  end

  def show
    authorize @playbook, :show?
    skip_policy_scope

    comments = @playbook.playbook_comments.includes(:account).chronological

    render inertia: 'Playbooks/Show', props: {
      playbook: serialize_playbook_for_customer(@playbook),
      comments: comments.as_json(
        only: %i[id body comment_type created_at feedback_context],
        include: {
          account: {
            only: %i[id first_name last_name],
            methods: %i[full_name amplifa_admin?]
          }
        }
      ),
      canApprove: policy(@playbook).approve?,
      canRequestChanges: policy(@playbook).request_changes?,
      canArchive: policy(@playbook).archive?,
      canUploadFiles: policy(@playbook).upload_file?
    }
  end

  def update
    authorize @playbook, :update?
    skip_policy_scope

    if update_playbook_with_attachment_cleanup(playbook_params)
      redirect_to playbook_path(@playbook), notice: t('admin.playbooks.updated')
    else
      redirect_to playbook_path(@playbook), alert: @playbook.errors.full_messages.to_sentence
    end
  end

  def knowledge_base
    authorize @playbook, :show?
    skip_policy_scope

    unless @playbook.knowledge_base_available?
      redirect_to playbook_path(@playbook)
      return
    end

    render inertia: 'Playbooks/KnowledgeBase', props: {
      playbook: serialize_playbook_for_customer(@playbook),
      files: serialize_knowledge_base_files(knowledge_base_file_scope.order(created_at: :desc)),
      canApprove: policy(@playbook).approve?,
      canRequestChanges: policy(@playbook).request_changes?,
      canArchive: policy(@playbook).archive?
    }
  end

  def knowledge_base_files
    authorize @playbook, :show?
    skip_policy_scope

    unless @playbook.knowledge_base_available?
      render json: { error: 'Knowledge Base is not available for this playbook' }, status: :not_found
      return
    end

    uploader = PlaybookKnowledgeBaseUploader.new(@playbook.organization, current_account)
    knowledge_base_file = if knowledge_base_url_source?
                             uploader.upload_url(
                               knowledge_base_source_url,
                               playbooks: [@playbook]
                             )
                          else
                             uploader.upload(
                               params[:file],
                               playbooks: [@playbook]
                             )
                          end

    render json: { file: serialize_knowledge_base_file(knowledge_base_file) }, status: :created
  rescue PlaybookKnowledgeBaseUploader::ValidationError, ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def knowledge_base_file_extract
    authorize @playbook, :show?
    skip_policy_scope

    knowledge_base_file = knowledge_base_file_scope.find(params[:file_id])

    render json: { extracted_text: knowledge_base_file.extracted_text }
  end

  def download_knowledge_base_file
    authorize @playbook, :show?
    skip_policy_scope

    knowledge_base_file = knowledge_base_file_scope.find(params[:file_id])
    if knowledge_base_file.url_source?
      redirect_to knowledge_base_file.source_final_url.presence || knowledge_base_file.source_url, allow_other_host: true
      return
    end

    unless knowledge_base_file.file.attached?
      redirect_to knowledge_base_playbook_path(@playbook), alert: 'File is not available'
      return
    end

    redirect_to rails_blob_path(knowledge_base_file.file, disposition: 'attachment'), allow_other_host: true
  end

  def approve
    authorize @playbook, :approve?
    skip_policy_scope

    comment_body = params[:comment] || 'Playbook approved'

    Playbook.transaction do
      @playbook.playbook_comments.create!(
        account: current_account,
        body: comment_body,
        comment_type: 'approval'
      )

      @playbook.approve!(current_account)
      approve_generated_samples_for_linked_agents!
    end

    AdminActivity.create!(
      account: current_account,
      organization_id: @playbook.organization_id,
      action: 'playbook_approved',
      details: {
        playbook_id: @playbook.id,
        product_name: @playbook.product_name,
        approved_by: current_account.full_name
      },
      ip_address: request.remote_ip,
      user_agent: request.user_agent
    )

    PlaybookMailer.playbook_approved(@playbook, current_account).deliver_later

    redirect_to playbook_path(@playbook), notice: 'Playbook approved successfully'
  end

  def request_changes
    authorize @playbook, :request_changes?
    skip_policy_scope

    comment_body = params[:comment].to_s

    if comment_body.blank?
      redirect_to playbook_path(@playbook), alert: 'Please provide a comment describing the changes needed'
      return
    end

    truncated_comment_body = comment_body.truncate(PlaybookComment::BODY_MAX_LENGTH, omission: '')

    comment = @playbook.playbook_comments.build(
      account: current_account,
      body: truncated_comment_body,
      comment_type: 'request_changes',
      feedback_context: permitted_feedback_context(params[:feedback_context])
    )

    if comment.save
      # WHY: Update playbook status to signal to admins that changes are needed
      @playbook.request_changes!

      # WHY: Log this action for audit trail
      AdminActivity.create!(
        account: current_account,
        organization_id: @playbook.organization_id,
        action: 'playbook_changes_requested',
        details: {
          playbook_id: @playbook.id,
          product_name: @playbook.product_name,
          requested_by: current_account.full_name,
          comment: truncated_comment_body
        },
        ip_address: request.remote_ip,
        user_agent: request.user_agent
      )

      # WHY: Send email to admins so they know to take action
      PlaybookMailer.changes_requested(@playbook, current_account, comment).deliver_later

      redirect_to playbook_path(@playbook), notice: 'Changes requested successfully'
    else
      redirect_to playbook_path(@playbook), alert: comment.errors.full_messages.join(', ')
    end
  end

  def archive
    authorize @playbook, :archive?
    skip_policy_scope

    @playbook.archive!

    AdminActivity.create!(
      account: current_account,
      organization_id: @playbook.organization_id,
      action: 'playbook_archived',
      details: {
        playbook_id: @playbook.id,
        product_name: @playbook.product_name,
        archived_by: current_account.full_name
      },
      ip_address: request.remote_ip,
      user_agent: request.user_agent
    )

    PlaybookMailer.playbook_archived(@playbook, current_account).deliver_later

    redirect_to playbooks_path, notice: 'Playbook archived'
  end

  def upload_file
    authorize @playbook, :upload_file?
    skip_policy_scope

    file = params[:file]
    file_type = params[:file_type] # 'reference' or 'proof_point'
    item_id = params[:item_id] # UUID of the reference or proof_point item
    collection_key = attachable_collection_key(file_type)
    items = @playbook.public_send(collection_key).dup
    item = items.find { |entry| entry['id'] == item_id }

    unless item
      render json: { error: 'Playbook attachment target not found' }, status: :not_found
      return
    end

    # Upload file using shared uploader service
    uploader = PlaybookFileUploader.new(@playbook.organization, file_type)
    result = uploader.upload(file, playbook: @playbook, attachable_id: item_id)

    # Update the JSONB field with file metadata
    item['file_url'] = result[:file_url]
    item['file_name'] = result[:file_name]
    item['file_size'] = result[:file_size]
    @playbook.update!(collection_key => items)

    render json: result.except(:playbook_attachment)
  rescue PlaybookFileUploader::ValidationError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue Pundit::NotAuthorizedError
    # Re-raise so ApplicationController's rescue_from handles it
    raise
  rescue StandardError => e
    Rails.logger.error("File upload error: #{e.message}")
    render json: { error: 'An unexpected error occurred during upload' }, status: :internal_server_error
  end

  private

  def current_organization
    Current.organization
  end

  def set_playbook
    @playbook = policy_scope(Playbook).find(params[:id])
  end

  def permitted_feedback_context(raw_context)
    return {} if raw_context.blank?

    permitted = if raw_context.is_a?(ActionController::Parameters)
                  raw_context.permit(:tab, :lead_id, :lead_name, :message_id, :step_label, :step_position, :agent_id,
                                     :agent_name).to_h
                else
                  raw_context.slice('tab', 'lead_id', 'lead_name', 'message_id', 'step_label', 'step_position',
                                    'agent_id', 'agent_name')
                end

    permitted['lead_id'] = permitted['lead_id'].to_i if permitted['lead_id'].present?
    permitted['message_id'] = permitted['message_id'].to_i if permitted['message_id'].present?
    permitted['step_position'] = permitted['step_position'].to_i if permitted['step_position'].present?
    permitted['agent_id'] = permitted['agent_id'].to_i if permitted['agent_id'].present?

    permitted.compact_blank
  end

  def attachable_collection_key(file_type)
    case file_type
    when 'reference' then :references
    when 'proof_point' then :proof_points
    else
      raise PlaybookFileUploader::ValidationError, 'Invalid file type. Allowed: reference, proof_point'
    end
  end

  def playbook_params
    permitted = params.require(:playbook).permit(
      :value_proposition,
      product: [:name, :description, { metadata: {} }],
      personae: [:id, :name, :title, :order, { pain_points: [] }],
      use_cases: %i[id title description order],
      references: %i[id customer_name name url description order file_url file_name file_size],
      proof_points: %i[id claim title description order file_url file_name file_size]
    )

    normalize_array_params(permitted)
  end

  def normalize_array_params(permitted)
    result = permitted.to_h

    %i[personae use_cases references proof_points].each do |key|
      next unless result[key.to_s].is_a?(Hash)

      result[key.to_s] = result[key.to_s]
                         .sort_by { |index, _| index.to_i }
                         .map { |_, value| value }
    end

    if result['personae'].is_a?(Array)
      result['personae'] = result['personae'].map do |persona|
        if persona['pain_points'].is_a?(Hash)
          persona['pain_points'] = persona['pain_points']
                                    .sort_by { |index, _| index.to_i }
                                    .map { |_, value| value }
        end
        persona
      end
    end

    result
  end

  def update_playbook_with_attachment_cleanup(permitted_params)
    Playbook.transaction do
      @playbook.update!(permitted_params)
      destroy_removed_playbook_attachments!(permitted_params)
    end

    true
  rescue ActiveRecord::RecordInvalid
    false
  end

  def approve_generated_samples_for_linked_agents!
    @playbook.agents.not_deleted.where.not(samples_generated_at: nil).where(samples_approved_at: nil).find_each do |agent|
      agent.mark_samples_approved!(current_account)
    end
  end

  def destroy_removed_playbook_attachments!(permitted_params)
    %w[reference proof_point].each do |attachable_type|
      collection_key = attachable_collection_key(attachable_type).to_s
      next unless permitted_params.key?(collection_key)

      kept_ids = Array(permitted_params[collection_key]).filter_map do |item|
        item['id'] if item['file_url'].present?
      end

      @playbook.playbook_attachments
               .where(attachable_type: attachable_type)
               .where.not(attachable_id: kept_ids)
               .destroy_all
    end
  end

  # WHY: Serialize playbook with all content for customer view, but exclude
  # sensitive admin-only fields like ai_generation_notes
  def serialize_playbook_for_customer(playbook)
    playbook.as_json(
      only: %i[id organization_id product value_proposition status language created_at updated_at approved_at],
      include: {
        approved_by: { only: %i[id first_name last_name], methods: [:full_name] }
      },
      methods: %i[personae use_cases references proof_points knowledge_base_available?]
    )
  end

  def knowledge_base_file_scope
    @playbook.organization.playbook_attachments
      .knowledge_base
      .for_playbook_or_all(@playbook)
  end

  def serialize_knowledge_base_files(files)
    files.map { |file| serialize_knowledge_base_file(file) }
  end

  def serialize_knowledge_base_file(file)
    {
      id: "playbook_attachment_#{file.id}",
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
      category: file.attachable_type,
      summary: file.summary,
      extraction_status: file.extraction_status,
      extraction_error: file.extraction_error,
      created_at: file.created_at,
      uploaded_by: file.uploaded_by ? {
        id: file.uploaded_by.id,
        full_name: file.uploaded_by.full_name
      } : nil,
      applies_to_all_playbooks: file.applies_to_all_playbooks?,
      playbooks: file.assigned_playbooks.order(:id).map { |playbook| { id: playbook.id, product_name: playbook.product_name } }
    }
  end

  def knowledge_base_url_source?
    params[:source_type] == 'url'
  end

  def knowledge_base_source_url
    params[:url].presence || params[:source_url]
  end
end
