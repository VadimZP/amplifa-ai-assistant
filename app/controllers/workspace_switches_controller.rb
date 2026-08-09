class WorkspaceSwitchesController < ApplicationController
  skip_after_action :verify_authorized
  skip_after_action :verify_policy_scoped

  def create
    membership = current_account.switchable_organization_memberships.find_by(
      organization_id: params[:organization_id]
    )

    unless membership
      head :forbidden
      return
    end

    session[:current_organization_id] = membership.organization_id
    Current.organization_membership = membership
    Current.organization = membership.organization

    redirect_back fallback_location: dashboard_path
  end
end
