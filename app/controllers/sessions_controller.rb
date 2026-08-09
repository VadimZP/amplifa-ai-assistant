class SessionsController < ApplicationController
  skip_before_action :authenticate
  skip_before_action :set_current_attributes
  skip_after_action :verify_authorized
  skip_after_action :verify_policy_scoped

  def new
    render inertia: 'Auth/Login', props: {
      error: nil,
      locale: I18n.locale.to_s,
      login_param: rodauth.login_param,
      password_param: rodauth.password_param
    }
  end

  def create
    saved_mcp_oauth_path = session[:mcp_oauth_authorize_path].presence ||
                           verified_mcp_oauth_authorize_path

    # Attempt login with Rodauth
    account_id = rodauth.account_from_login(params[rodauth.login_param])

    if account_id && rodauth.password_match?(params[rodauth.password_param])
      account = Account.find(account_id)
      if account.requires_email_two_factor_authentication?
        start_email_two_factor_challenge(account, saved_mcp_oauth_path)
        return
      end

      # Login successful
      rodauth.account_from_id(account_id)
      rodauth.login_session('password')
      rodauth.remember_login if params['remember']
      cookies.delete(:mcp_oauth_authorize_path, path: '/')

      # Redirect based on role
      if account.amplifa_admin? && saved_mcp_oauth_path.present?
        redirect_to saved_mcp_oauth_path
      elsif account.amplifa_admin?
        redirect_to admin_dashboard_path
      elsif (membership = account.switchable_organization_memberships.includes(:organization).order(:created_at).first)
        session[:current_organization_id] = membership.organization_id
        redirect_to dashboard_path
      else
        redirect_to no_workspace_path
      end
    else
      # Login failed
      render inertia: 'Auth/Login', props: {
        error: I18n.t('auth.login.invalid_credentials'),
        locale: I18n.locale.to_s,
        login_param: rodauth.login_param,
        password_param: rodauth.password_param
      }
    end
  end

  def destroy
    current_account&.email_two_factor_challenges&.active&.update_all(used_at: Time.current, updated_at: Time.current)

    # Clear impersonation if active
    session.delete(:impersonating_admin_id) if session[:impersonating_admin_id].present?
    session.delete(:email_two_factor_challenge_id)
    session.delete(:current_organization_id)

    rodauth.logout
    redirect_to root_path, notice: 'You have been logged out'
  end

  private

  def verified_mcp_oauth_authorize_path
    Rails.application.message_verifier('mcp_oauth_authorize_path').verified(
      cookies[:mcp_oauth_authorize_path].to_s,
      purpose: :mcp_oauth_authorize_path
    )
  end

  def start_email_two_factor_challenge(account, saved_mcp_oauth_path)
    challenge = account.email_two_factor_challenges.active.newest_first.first

    if challenge&.resend_available? || challenge.nil?
      account.email_two_factor_challenges.active.update_all(used_at: Time.current, updated_at: Time.current)
      challenge, raw_token = EmailTwoFactorChallenge.create_for!(
        account: account,
        return_to: saved_mcp_oauth_path,
        remember_login: params['remember'].present?
      )
      RodauthMailer.email_two_factor(nil, account.id, raw_token).deliver_later
    end

    session[:email_two_factor_challenge_id] = challenge.id
    redirect_to two_factor_email_path
  end
end
