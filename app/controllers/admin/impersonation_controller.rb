class Admin::ImpersonationController < Admin::BaseController
  skip_before_action :require_amplifa_admin!, only: [:destroy]
  before_action :ensure_not_impersonating, only: [:create]
  before_action :ensure_impersonating, only: [:destroy]
  # NOTE: These are technically redundant since skip_authorization? returns true for admin controllers,
  # but keep them for explicit documentation of this controller's special behavior
  skip_after_action :verify_authorized, raise: false
  skip_after_action :verify_policy_scoped, raise: false

  def create
    target_account = Account.find(params[:id])

    # Verify target is a customer (not another admin)
    unless target_account.customer_admin? || target_account.customer_user?
      return render inertia: 'Error', props: {
        message: 'Can only impersonate customer users',
        status: 422
      }
    end

    # Store original admin ID in session
    session[:impersonating_admin_id] = session[rodauth.session_key]

    # Log the impersonation
    AdminActivity.create!(
      account_id: current_account.id,
      organization_id: target_account.organization_id,
      action: 'impersonate_user',
      details: {
        target_account_id: target_account.id,
        target_email: target_account.email,
        target_name: target_account.full_name
      },
      ip_address: request.remote_ip,
      user_agent: request.user_agent
    )

    # Switch session to target account by updating the account_id in session
    session[rodauth.session_key] = target_account.id
    # Clear the cached current_account
    @current_account = nil

    redirect_to dashboard_path, notice: "Now viewing as #{target_account.full_name}"
  end

  def destroy
    # Get the original admin account
    admin_id = session[:impersonating_admin_id]
    admin_account = Account.find(admin_id)
    impersonated_account = current_account

    # Log the exit
    AdminActivity.create!(
      account_id: admin_id,
      organization_id: impersonated_account.organization_id,
      action: 'exit_impersonation',
      details: {
        customer_account_id: impersonated_account.id,
        customer_email: impersonated_account.email
      },
      ip_address: request.remote_ip,
      user_agent: request.user_agent
    )

    # Switch back to admin session by restoring the original account_id
    session[rodauth.session_key] = admin_id
    # Clear impersonation flag
    session.delete(:impersonating_admin_id)
    # Clear the cached current_account
    @current_account = nil

    redirect_to admin_dashboard_path, notice: 'Exited impersonation mode'
  end

  private

  def ensure_not_impersonating
    if impersonating?
      render inertia: 'Error', props: {
        message: 'Cannot impersonate while already impersonating',
        status: 422
      }
    end
  end

  def ensure_impersonating
    unless impersonating?
      render inertia: 'Error', props: {
        message: 'Not currently impersonating',
        status: 422
      }
    end
  end

  def impersonating?
    session[:impersonating_admin_id].present?
  end
  helper_method :impersonating?
end
