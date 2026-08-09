# WHY: This controller handles commenting functionality for both customers
# and admins. Comments enable discussion and feedback during the playbook
# review process. This is used by both the customer and admin interfaces.
class PlaybookCommentsController < ApplicationController
  before_action :set_playbook

  # WHY: Placeholder index action to satisfy Rails 8.1 callback verification.
  # ApplicationController defines verify_policy_scoped only: :index, which would fail
  # if we don't have an index action. This stub returns 404 since comments are only
  # viewed within the playbook context, not as a separate list.
  def index
    skip_authorization
    skip_policy_scope
    head :not_found
  end

  def create
    # WHY: Build comment associated with current user and playbook
    @comment = @playbook.playbook_comments.build(comment_params)
    @comment.account = current_account

    # WHY: Authorize based on whether user can access this playbook
    # Authorization check ensures user can only comment on accessible playbooks
    authorize @comment, :create?

    if @comment.save
      # WHY: Send email notification to relevant parties
      # WHY: If commenter is admin, notify customers. If commenter is customer, notify admins.
      PlaybookMailer.new_comment(@playbook, @comment).deliver_later

      redirect_to playbook_path(@playbook), notice: 'Comment added successfully'
    else
      # WHY: Return to playbook page with error message if validation fails
      redirect_to playbook_path(@playbook), alert: @comment.errors.full_messages.join(', ')
    end
  end

  private

  def set_playbook
    # WHY: Find playbook first, then authorize via PlaybookCommentPolicy.create?
    # The authorization check in create action will ensure users can only comment
    # on playbooks they have access to (via their organization)
    @playbook = Playbook.find(params[:playbook_id])
  end

  def comment_params
    permitted = params.require(:playbook_comment).permit(:body)
    permitted[:feedback_context] = permitted_feedback_context(params.dig(:playbook_comment, :feedback_context))
    permitted
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
end
