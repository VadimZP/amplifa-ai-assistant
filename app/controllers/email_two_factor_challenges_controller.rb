class EmailTwoFactorChallengesController < ApplicationController
  skip_before_action :authenticate
  skip_before_action :set_current_attributes
  skip_after_action :verify_authorized
  skip_after_action :verify_policy_scoped

  def show
    challenge = current_challenge
    unless challenge
      redirect_to login_path, alert: I18n.t('auth.two_factor_email.expired')
      return
    end

    render inertia: 'Auth/TwoFactorEmail', props: props_for(challenge)
  end

  def create
    challenge = current_challenge
    unless challenge
      redirect_to login_path, alert: I18n.t('auth.two_factor_email.expired')
      return
    end

    unless challenge.resend_available?
      redirect_to two_factor_email_path, alert: I18n.t('auth.two_factor_email.resend_wait')
      return
    end

    raw_token = SecureRandom.urlsafe_base64(32)
    challenge.update!(
      token_digest: EmailTwoFactorChallenge.digest(raw_token),
      expires_at: EmailTwoFactorChallenge::EXPIRES_IN.from_now,
      last_sent_at: Time.current
    )
    RodauthMailer.email_two_factor(nil, challenge.account_id, raw_token).deliver_later

    redirect_to two_factor_email_path, notice: I18n.t('auth.two_factor_email.resent')
  end

  def verify
    challenge = EmailTwoFactorChallenge.find_active_by_token(params[:token])
    unless challenge&.use_once!
      redirect_to login_path, alert: I18n.t('auth.two_factor_email.invalid')
      return
    end

    complete_login(challenge)
  end

  private

  def current_challenge
    EmailTwoFactorChallenge.active.includes(:account).find_by(id: session[:email_two_factor_challenge_id])
  end

  def props_for(challenge)
    {
      notice: flash[:notice],
      error: flash[:alert] || flash[:error],
      email: challenge.account.email,
      resend_available_at: challenge.resend_available_at.iso8601,
      locale: I18n.locale.to_s
    }
  end

  def complete_login(challenge)
    account = challenge.account
    rodauth.account_from_id(account.id)
    rodauth.login_session('password')
    rodauth.remember_login if challenge.remember_login?
    session.delete(:email_two_factor_challenge_id)
    cookies.delete(:mcp_oauth_authorize_path, path: '/')

    redirect_to redirect_path_for(account, challenge)
  end

  def redirect_path_for(account, challenge)
    return challenge.return_to if account.amplifa_admin? && challenge.return_to.present?
    return admin_dashboard_path if account.amplifa_admin?
    membership = account.switchable_organization_memberships.includes(:organization).order(:created_at).first
    return no_workspace_path unless membership

    session[:current_organization_id] = membership.organization_id
    dashboard_path
  end
end
