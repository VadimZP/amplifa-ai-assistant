class Settings::TeamController < ApplicationController
  skip_after_action :verify_policy_scoped
  skip_after_action :verify_authorized

  before_action :load_organization
  before_action :redirect_amplifa_admin
  before_action :authorize_team_management!, only: %i[create_invitation cancel_invitation deactivate_member]
  before_action :set_member, only: [:deactivate_member]
  before_action :set_invitation, only: [:cancel_invitation]

  def index
    skip_policy_scope
    authorize @organization, :show?

    render_team
  end

  def create_invitation
    skip_policy_scope

    @invitation = Invitation.new(invitation_params)
    @invitation.organization = @organization
    @invitation.invited_by = current_account

    if @invitation.save
      InvitationMailer.invite(@invitation).deliver_later

      log_activity('invitation_created', {
                     invitation_id: @invitation.id,
                     email: @invitation.email,
                     role: @invitation.role
                   })

      redirect_to settings_team_path, notice: "Invitation sent to #{@invitation.email}."
    else
      render_team(
        status: :unprocessable_entity,
        errors: @invitation.errors.messages,
        invitation: @invitation.as_json(only: %i[email first_name last_name role])
      )
    end
  end

  def cancel_invitation
    skip_policy_scope

    if @invitation.cancel!
      log_activity('invitation_cancelled', {
                     invitation_id: @invitation.id,
                     email: @invitation.email
                   })

      redirect_to settings_team_path, notice: "Invitation cancelled for #{@invitation.email}."
    else
      redirect_to settings_team_path, alert: 'Failed to cancel invitation.'
    end
  end

  def deactivate_member
    skip_policy_scope

    if @member.id == current_account.id
      redirect_to settings_team_path, alert: 'You cannot deactivate your own account from Team settings.'
      return
    end

    membership = @member.organization_memberships.active.find_by(organization: @organization)

    unless membership
      redirect_to settings_team_path, alert: 'Team member not found.'
      return
    end

    if membership.customer_admin?
      redirect_to settings_team_path, alert: 'Customer admins cannot deactivate other customer admins.'
      return
    end

    if membership.update(status: 'inactive', deactivated_at: Time.current)
      replacement = @member.active_organization_memberships.where.not(id: membership.id).order(:created_at).first
      @member.update!(role: replacement.role, organization_id: replacement.organization_id) if replacement && @member.organization_id == membership.organization_id

      log_activity('team_member_deactivated', {
                      account_id: @member.id,
                      email: @member.email,
                      role: membership.role
                    })

      redirect_to settings_team_path, notice: "#{@member.full_name} has been deactivated."
    else
      redirect_to settings_team_path, alert: 'Failed to deactivate team member.'
    end
  end

  private

  def load_organization
    @organization = Current.organization
  end

  def redirect_amplifa_admin
    return unless current_account.amplifa_admin?

    skip_policy_scope
    redirect_to admin_dashboard_path and return
  end

  def authorize_team_management!
    authorize @organization, :update_company_settings?
  end

  def set_member
    @member = policy_scope(Account).where.not(role: 'amplifa_admin').find_by(id: params[:id])
    return if @member

    redirect_to settings_team_path, alert: 'Team member not found.'
    nil
  end

  def set_invitation
    @invitation = Invitation.where(organization: @organization, status: 'pending').find_by(id: params[:id])
    return if @invitation

    redirect_to settings_team_path, alert: 'Invitation not found.'
    nil
  end

  def invitation_params
    params.require(:invitation).permit(:email, :first_name, :last_name, :role)
  end

  def render_team(status: :ok, errors: nil, invitation: nil)
    team_members = @organization.organization_memberships.active.includes(:account).order(created_at: :desc)

    pending_invitations = Invitation
                          .where(organization: @organization, status: 'pending')
                          .where('expires_at > ?', Time.current)
                          .includes(:invited_by)
                          .order(created_at: :desc)

    render inertia: 'Customer/Settings/Team', props: {
      team_members: serialize_team_members(team_members),
      pending_invitations: pending_invitations.as_json(
        only: %i[id email first_name last_name role expires_at created_at],
        include: {
          invited_by: {
            only: %i[id first_name last_name email],
            methods: [:full_name]
          }
        }
      ),
      can_manage_team: Current.organization_membership&.customer_admin? || false,
      errors: errors,
      invitation: invitation
    }, status: status
  end

  def log_activity(action, details)
    AdminActivity.create!(
      account: current_account,
      organization: @organization,
      action: action,
      details: details,
      ip_address: request.remote_ip,
      user_agent: request.user_agent
    )
  end

  def serialize_team_members(memberships)
    memberships.map do |membership|
      account = membership.account
      account.as_json(
        only: %i[id first_name last_name email created_at deactivated_at],
        methods: %i[full_name active?]
      ).merge(
        'role' => membership.role,
        'customer_admin?' => membership.customer_admin?,
        'customer_user?' => membership.customer_user?
      )
    end
  end
end
