# frozen_string_literal: true

# Customer-facing profile settings tab.
# Allows users to view/edit personal information (name, timezone),
# and displays notification preferences and security settings.
class Settings::ProfileController < ApplicationController
  skip_after_action :verify_policy_scoped
  skip_after_action :verify_authorized

  before_action :load_organization
  before_action :redirect_amplifa_admin

  def index
    skip_policy_scope
    authorize @organization, :show?

    render_profile
  end

  def update
    skip_policy_scope
    authorize @organization, :show?

    if current_account.update(profile_params)
      redirect_to settings_profile_path, notice: 'Profile updated successfully'
    else
      render_profile(errors: current_account.errors.messages, status: :unprocessable_entity)
    end
  end

  def update_password
    skip_policy_scope
    authorize @organization, :show?

    errors = password_validation_errors

    if errors.any?
      render_profile(password_errors: errors, status: :unprocessable_entity)
      return
    end

    current_account.update_columns(
      password_hash: RodauthApp.rodauth.allocate.password_hash(password_params[:new_password])
    )
    redirect_to settings_profile_path, notice: 'Password updated successfully'
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

  def profile_params
    params.fetch(:account, params).permit(:first_name, :last_name, :timezone, :locale)
  end

  def password_params
    params.fetch(:account, params).permit(:current_password, :new_password, :new_password_confirmation)
  end

  def render_profile(errors: nil, password_errors: nil, status: :ok)
    render inertia: 'Customer/Settings/Profile', props: {
      account: current_account.as_json(
        only: %i[id email first_name last_name timezone locale],
        methods: [:full_name]
      ),
      organization: @organization.as_json(only: %i[id name]),
      locale_options: SupportedLocale::ALL,
      suppress_flash: true,
      errors: errors,
      password_errors: password_errors
    }, status: status
  end

  def password_validation_errors
    errors = {}

    if password_params[:current_password].blank?
      errors[:current_password] = ['Current password is required']
    elsif !valid_current_password?(password_params[:current_password])
      errors[:current_password] = ['Current password is incorrect']
    end

    if password_params[:new_password].blank?
      errors[:new_password] = ['New password is required']
    elsif password_params[:new_password].length < 8
      errors[:new_password] = ['New password must be at least 8 characters']
    end

    if password_params[:new_password_confirmation].blank?
      errors[:new_password_confirmation] = ['Password confirmation is required']
    elsif password_params[:new_password_confirmation] != password_params[:new_password]
      errors[:new_password_confirmation] = ['Password confirmation does not match']
    end

    errors
  end

  def valid_current_password?(password)
    return false if password.blank?

    account = rodauth.account_from_login(current_account.email)
    return false if account.blank?

    rodauth.password_match?(password)
  end
end
