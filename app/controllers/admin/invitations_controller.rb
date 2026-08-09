class Admin::InvitationsController < Admin::BaseController
  before_action :set_invitation, only: [:resend, :cancel, :destroy]

  def index
    # WHY: Use Pundit to authorize that only admins can view invitations
    authorize Invitation

    # WHY: Use policy_scope to get invitations the current user is allowed to see
    @invitations = policy_scope(Invitation)
                    .includes(:organization, :invited_by)
                    .recent

    # WHY: Apply status filter to allow viewing specific invitation states
    if params[:status].present?
      @invitations = @invitations.where(status: params[:status])
    end

    # WHY: Apply organization filter to view invitations for a specific org
    if params[:organization_id].present?
      @invitations = @invitations.for_organization(params[:organization_id])
    end

    # WHY: Paginate results to handle large numbers of invitations efficiently
    page = params[:page]&.to_i || 1
    per_page = 25
    total = @invitations.count
    total_pages = (total.to_f / per_page).ceil

    @invitations = @invitations.limit(per_page).offset((page - 1) * per_page)

    # WHY: Serialize invitation data with related models for display
    invitations_json = @invitations.as_json(
      only: [:id, :email, :first_name, :last_name, :role, :status, :sent_at, :accepted_at, :expires_at, :created_at],
      include: {
        organization: { only: [:id, :name] },
        invited_by: { only: [:id, :first_name, :last_name, :email], methods: [:full_name] }
      }
    )

    render inertia: 'Admin/Invitations/Index', props: {
      invitations: invitations_json,
      organizations: Organization.active.pluck(:id, :name),
      filters: {
        status: params[:status],
        organization_id: params[:organization_id]
      },
      pagination: {
        current_page: page,
        total_pages: total_pages,
        total_count: total
      }
    }
  end

  def new
    # WHY: Authorize that only admins can create invitations
    authorize Invitation

    # WHY: Pre-populate organization_id if passed as query param (e.g., from organization edit page)
    preselected_org_id = params[:organization_id].present? ? params[:organization_id].to_i : nil

    render inertia: 'Admin/Invitations/New', props: {
      organizations: Organization.active.order(:name).as_json(only: [:id, :name]),
      roles: ['customer_admin', 'customer_user'],
      preselected_organization_id: preselected_org_id
    }
  end

  def create
    # WHY: Authorize that only admins can create invitations
    authorize Invitation

    # WHY: Create invitation record with current admin as the inviter
    @invitation = Invitation.new(invitation_params)
    @invitation.invited_by = current_account

    if @invitation.save
      # WHY: Send invitation email asynchronously to avoid blocking the request
      InvitationMailer.invite(@invitation).deliver_later

      # WHY: Log admin activity for audit trail
      AdminActivity.create!(
        account: current_account,
        organization_id: @invitation.organization_id,
        action: 'invitation_created',
        details: {
          invitation_id: @invitation.id,
          email: @invitation.email,
          role: @invitation.role
        },
        ip_address: request.remote_ip,
        user_agent: request.user_agent
      )

      redirect_to admin_invitations_path, notice: "Invitation sent to #{@invitation.email}. Link expires on #{@invitation.expires_at.strftime('%B %d, %Y')}."
    else
      # WHY: Return to form with errors if validation fails
      render inertia: 'Admin/Invitations/New', props: {
        organizations: Organization.active.order(:name).as_json(only: [:id, :name]),
        roles: ['customer_admin', 'customer_user'],
        errors: @invitation.errors.messages,
        invitation: @invitation.as_json(only: [:email, :first_name, :last_name, :role, :organization_id])
      }
    end
  end

  def resend
    # WHY: Authorize that only admins can resend invitations
    authorize @invitation

    # WHY: Use the model's resend! method which handles token regeneration,
    # email sending, and activity logging
    if @invitation.resend!
      redirect_to admin_invitations_path, notice: "Invitation resent to #{@invitation.email}."
    else
      redirect_to admin_invitations_path, alert: "Failed to resend invitation. #{@invitation.errors.full_messages.join(', ')}"
    end
  end

  def cancel
    # WHY: Authorize that only admins can cancel invitations
    authorize @invitation

    # WHY: Use the model's cancel! method which handles status update and logging
    if @invitation.cancel!
      # WHY: Log admin activity for audit trail
      AdminActivity.create!(
        account: current_account,
        organization_id: @invitation.organization_id,
        action: 'invitation_cancelled',
        details: {
          invitation_id: @invitation.id,
          email: @invitation.email
        },
        ip_address: request.remote_ip,
        user_agent: request.user_agent
      )

      redirect_to admin_invitations_path, notice: "Invitation cancelled for #{@invitation.email}."
    else
      redirect_to admin_invitations_path, alert: "Failed to cancel invitation."
    end
  end

  def destroy
    # WHY: Authorize that only admins can delete invitations
    authorize @invitation

    # WHY: Store invitation details before deletion for logging
    email = @invitation.email
    organization_id = @invitation.organization_id

    if @invitation.destroy
      # WHY: Log admin activity for audit trail
      AdminActivity.create!(
        account: current_account,
        organization_id: organization_id,
        action: 'invitation_deleted',
        details: {
          email: email
        },
        ip_address: request.remote_ip,
        user_agent: request.user_agent
      )

      redirect_to admin_invitations_path, notice: "Invitation deleted for #{email}."
    else
      redirect_to admin_invitations_path, alert: "Failed to delete invitation."
    end
  end

  private

  def set_invitation
    # WHY: Find invitation by ID for member actions
    @invitation = Invitation.find(params[:id])
  end

  def invitation_params
    # WHY: Permit only the required fields for invitation creation
    params.require(:invitation).permit(:email, :first_name, :last_name, :role, :organization_id)
  end
end
