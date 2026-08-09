class InvitationsController < ApplicationController
  # WHY: Invitation acceptance is a public flow, no authentication required
  skip_before_action :authenticate
  skip_before_action :set_current_attributes
  skip_after_action :verify_authorized
  skip_after_action :verify_policy_scoped

  def show
    # WHY: Find invitation by token from URL parameter
    @invitation = Invitation.find_by(token: params[:token])

    # WHY: Validate invitation exists and is in valid state
    unless @invitation
      return render inertia: 'Public/Invitations/Invalid', props: {
        message: I18n.t('invitations.flash.invalid')
      }
    end

    # WHY: Check if invitation has expired
    if @invitation.expired?
      return render inertia: 'Public/Invitations/Expired', props: {
        invitation: @invitation.as_json(only: %i[email first_name expires_at]),
        message: I18n.t('invitations.flash.expired')
      }
    end

    # WHY: Check if invitation has already been accepted
    if @invitation.status == 'accepted'
      return redirect_to login_path, notice: I18n.t('invitations.flash.already_used')
    end

    # WHY: Check if invitation has been cancelled
    if @invitation.status == 'cancelled'
      return render inertia: 'Public/Invitations/Invalid', props: {
        message: I18n.t('invitations.flash.cancelled')
      }
    end

    # WHY: Set locale based on organization's language so the accept page
    # renders in the correct language by default (e.g. German for German orgs)
    I18n.locale = @invitation.organization.locale if @invitation.organization.locale.present?

    # WHY: Render acceptance form with invitation details and timezone options
    render inertia: 'Public/Invitations/Accept', props: {
      invitation: @invitation.as_json(
        only: %i[token email first_name last_name role],
        include: { organization: { only: %i[id name locale] } }
      ),
      locale_options: SupportedLocale::ALL,
      timezones: timezone_options
    }
  end

  def accept
    # WHY: Find invitation by token
    @invitation = Invitation.find_by(token: params[:token])

    # WHY: Validate invitation exists and can be accepted
    unless @invitation&.can_be_accepted?
      return redirect_to accept_invitation_path(params[:token]), alert: I18n.t('invitations.flash.no_longer_valid')
    end

    existing_account = Account.find_by(email: @invitation.email)
    return accept_for_existing_account(existing_account) if existing_account

    # WHY: Validate required parameters are present for new accounts.
    unless params[:password].present? && params[:password_confirmation].present?
      return render_accept_form_with_error(I18n.t('invitations.flash.password_required'))
    end

    # WHY: Validate passwords match
    if params[:password] != params[:password_confirmation]
      return render_accept_form_with_error(I18n.t('invitations.flash.passwords_mismatch'))
    end

    # WHY: Validate password meets minimum requirements (Rodauth default is 8 chars)
    return render_accept_form_with_error(I18n.t('invitations.flash.password_too_short')) if params[:password].length < 8

    # WHY: Create account in a transaction to ensure all-or-nothing
    begin
      ActiveRecord::Base.transaction do
        # WHY: Create the account with invitation details
        account = Account.new(
          email: @invitation.email,
          first_name: @invitation.first_name,
          last_name: @invitation.last_name,
          role: @invitation.role,
          organization_id: @invitation.organization_id,
          locale: params[:locale] || @invitation.organization.locale,
          timezone: params[:timezone],
          status: :verified # WHY: Auto-verify invited accounts
        )

        # WHY: Set password using BCrypt (Rodauth's password hasher)
        require 'bcrypt'
        account.password_hash = BCrypt::Password.create(params[:password])

        # WHY: Save the account and validate all fields
        return render_accept_form_with_error(account.errors.full_messages.join(', ')) unless account.save

        OrganizationMembership.find_or_create_by!(
          account: account,
          organization: @invitation.organization
        ) do |membership|
          membership.role = @invitation.role
          membership.status = 'active'
        end

        # WHY: Update invitation record with accepted status
        @invitation.update!(
          account_id: account.id,
          status: 'accepted',
          accepted_at: Time.current
        )

        # WHY: Log activity for audit trail
        AdminActivity.create!(
          account_id: @invitation.invited_by_id,
          organization_id: @invitation.organization_id,
          action: 'invitation_accepted',
          details: {
            invitation_id: @invitation.id,
            account_id: account.id,
            email: account.email
          },
          ip_address: request.remote_ip,
          user_agent: request.user_agent
        )

        rodauth.account_from_id(account.id)

        # WHY: Automatically log in the new account
        rodauth.login_session(account.id)

        # WHY: Set Current attributes for the new user session
        Current.account = account
        Current.organization = @invitation.organization
        Current.organization_membership = account.organization_memberships.find_by(organization: @invitation.organization)
        session[:current_organization_id] = @invitation.organization_id

        redirect_to dashboard_path, notice: I18n.t('invitations.flash.welcome', name: account.first_name)
      end
    rescue ActiveRecord::RecordInvalid => e
      render_accept_form_with_error(I18n.t('invitations.flash.create_failed', message: e.message))
    rescue StandardError => e
      # WHY: Log unexpected errors for debugging
      Rails.logger.error("Invitation acceptance failed: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      render_accept_form_with_error(I18n.t('invitations.flash.unexpected_error'))
    end
  end

  private

  def accept_for_existing_account(account)
    unless current_account&.id == account.id
      redirect_to accept_invitation_path(@invitation.token), alert: I18n.t('invitations.flash.login_with_invited_email')
      return
    end

    ActiveRecord::Base.transaction do
      membership = OrganizationMembership.find_or_initialize_by(
        account: account,
        organization: @invitation.organization
      )
      membership.assign_attributes(
        role: @invitation.role,
        status: 'active',
        deactivated_at: nil
      )
      membership.save!

      @invitation.update!(
        account: account,
        status: 'accepted',
        accepted_at: Time.current
      )

      AdminActivity.create!(
        account_id: @invitation.invited_by_id,
        organization_id: @invitation.organization_id,
        action: 'invitation_accepted',
        details: {
          invitation_id: @invitation.id,
          account_id: account.id,
          email: account.email
        },
        ip_address: request.remote_ip,
        user_agent: request.user_agent
      )

      Current.account = account
      Current.organization = @invitation.organization
      Current.organization_membership = membership
      session[:current_organization_id] = @invitation.organization_id

      redirect_to dashboard_path, notice: I18n.t('invitations.flash.welcome', name: account.first_name)
    end
  rescue ActiveRecord::RecordInvalid => e
    render_accept_form_with_error(I18n.t('invitations.flash.accept_failed', message: e.message))
  end

  def timezone_options
    # WHY: Provide common timezones grouped by region for better UX
    ActiveSupport::TimeZone.all.map { |tz| { value: tz.name, label: tz.to_s } }
  end

  def render_accept_form_with_error(error_message)
    # WHY: Re-render the acceptance form with error message
    render inertia: 'Public/Invitations/Accept', props: {
      invitation: @invitation.as_json(
        only: %i[token email first_name last_name role],
        include: { organization: { only: %i[id name locale] } }
      ),
      locale_options: SupportedLocale::ALL,
      timezones: timezone_options,
      error: error_message
    }
  end
end
