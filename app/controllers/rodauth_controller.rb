class RodauthController < ApplicationController
  # Used by Rodauth for rendering views, CSRF protection, running any
  # registered action callbacks and rescue handlers, instrumentation etc.

  # Controller callbacks and rescue handlers will run around Rodauth endpoints.
  # before_action :verify_captcha, only: :login, if: -> { request.post? }
  # rescue_from("SomeError") { |exception| ... }

  # Layout can be changed for all Rodauth pages or only certain pages.
  # layout "authentication"
  # layout -> do
  #   case rodauth.current_route
  #   when :login, :create_account, :verify_account, :verify_account_resend,
  #        :reset_password, :reset_password_request
  #     "authentication"
  #   else
  #     "application"
  #   end
  # end

  skip_before_action :authenticate
  skip_before_action :set_current_attributes
  skip_after_action :verify_authorized
  skip_after_action :verify_policy_scoped

  # Render Rodauth views using Inertia
  def create_account
    render inertia: 'Auth/Register', props: rodauth_props
  end

  def login
    render inertia: 'Auth/Login', props: rodauth_props
  end

  def reset_password_request
    render inertia: 'Auth/ForgotPassword', props: rodauth_props
  end

  def reset_password
    render inertia: 'Auth/ResetPassword', props: rodauth_props.merge(
      field_error: rodauth.field_error(rodauth.password_param),
      password_confirm_param: rodauth.password_confirm_param
    )
  end

  def verify_account
    render inertia: 'Auth/VerifyAccount', props: rodauth_props
  end

  private

  def rodauth_props
    {
      notice: flash[:notice],
      error: flash[:error],
      locale: I18n.locale.to_s,
      field_error: rodauth.field_error(rodauth.login_param),
      login_param: rodauth.login_param,
      password_param: rodauth.password_param
    }
  end
end
