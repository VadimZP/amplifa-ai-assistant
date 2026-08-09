class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  include Pundit::Authorization

  around_action :switch_locale
  before_action :authenticate
  before_action :set_current_attributes
  after_action :verify_authorized, unless: :skip_authorization_verification?
  after_action :verify_policy_scoped, if: :verify_policy_scope?

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  inertia_share do
    account_data = current_account&.then do |account|
      account.as_json(
        only: %i[id email first_name last_name role status],
        methods: %i[full_name amplifa_admin? customer_admin? customer_user?]
      ).merge('created_at' => account.created_at.to_i)
    end

    shared_data = {
      auth: {
        account: account_data,
        current_organization: Current.organization&.as_json(
          only: %i[id name onboarded status website]
        ),
        organization: Current.organization&.as_json(
          only: %i[id name onboarded status website]
        ),
        organizations: switchable_organizations.as_json(
          only: %i[id name onboarded status website]
        )
      },
      flash: {
        notice: flash[:notice],
        alert: flash[:alert],
        error: flash[:error]
      },
      suppress_flash: params[:suppress_flash].present?,
      csrf_token: form_authenticity_token,
      locale: I18n.locale.to_s # WHY: Share current locale with frontend for i18n
    }

    # Add impersonation data if active
    if impersonating?
      admin_account = Account.find(session[:impersonating_admin_id])
      shared_data[:impersonating] = true
      shared_data[:impersonating_admin] = {
        id: admin_account.id,
        name: admin_account.full_name,
        email: admin_account.email
      }
    else
      shared_data[:impersonating] = false
    end

    if current_account && !current_account.amplifa_admin? && Current.organization
      base = Conversation.where(organization_id: Current.organization.id).visible_in_reply_center
      bounce_ids = base.joins(:replies).where(replies: { is_bounce: true }).select(:id)
      shared_data[:inbox_unread_count] = base.unread_for(current_account).where.not(id: bounce_ids).count
    end

    shared_data
  end

  private

  def authenticate
    rodauth.require_authentication unless skip_authentication?
  end

  def current_account
    @current_account ||= rodauth.rails_account
  end
  helper_method :current_account

  alias pundit_user current_account

  def impersonating?
    session[:impersonating_admin_id].present?
  end
  helper_method :impersonating?

  def original_admin
    return nil unless impersonating?

    @original_admin ||= Account.find(session[:impersonating_admin_id])
  end
  helper_method :original_admin

  def set_current_attributes
    Current.account = current_account
    Current.organization = nil
    Current.organization_membership = nil
    resolve_current_customer_workspace
  end

  def resolve_current_customer_workspace
    return unless current_account
    return if current_account.amplifa_admin?

    memberships = current_account.switchable_organization_memberships.includes(:organization)
    membership = memberships.find_by(organization_id: session[:current_organization_id]) if session[:current_organization_id]
    membership ||= memberships.find_by(organization_id: current_account.organization_id) if current_account.organization_id
    membership ||= memberships.order(:created_at).first

    if membership
      Current.organization_membership = membership
      Current.organization = membership.organization
      session[:current_organization_id] = membership.organization_id
    else
      session.delete(:current_organization_id)
    end
  end

  def switchable_organizations
    return Organization.none unless current_account && !current_account.amplifa_admin?

    current_account.switchable_organization_memberships
                   .includes(:organization)
                   .map(&:organization)
                   .uniq
                   .sort_by(&:name)
  end

  def skip_authentication?
    controller_path.start_with?('rodauth') ||
      controller_path == 'pages'
  end

  def skip_authorization?
    # WHY: Only skip authorization for:
    # - rodauth: authentication system handles its own authorization
    # - admin: admin controllers are protected by require_amplifa_admin! in BaseController
    #          and policies grant full access to admins via ApplicationPolicy
    # - pages: public pages with no sensitive data
    # - sessions: login/logout don't need Pundit (handled by Rodauth)
    controller_path.start_with?('rodauth') ||
      controller_path.start_with?('admin') ||
      controller_path == 'pages' ||
      controller_path == 'sessions'
  end

  def skip_authorization_verification?
    skip_authorization? || action_name == 'index'
  end

  def verify_policy_scope?
    !skip_authorization? && action_name == 'index'
  end

  def user_not_authorized
    flash[:alert] = 'You are not authorized to perform this action.'
    redirect_to(request.referrer || root_path)
  end

  # WHY: Locale management for internationalization (Week 2)
  # This wraps each request in the user's preferred locale, falling back through
  # multiple sources to find the best language choice
  def switch_locale(&action)
    locale = current_account&.effective_locale ||
             session[:locale]&.then { |l| l if SupportedLocale.include?(l) } ||
             extract_locale_from_accept_language_header ||
             I18n.default_locale

    I18n.with_locale(locale, &action)
  end

  # WHY: Extract the user's preferred language from their browser settings
  # This provides a good default for new users who haven't selected a language yet
  def extract_locale_from_accept_language_header
    header = request.env['HTTP_ACCEPT_LANGUAGE']
    return if header.blank?

    supported_locales = SupportedLocale::ALL
    requested_locales = header.split(',')
                              .map { |part| part.to_s.split(';').first.to_s.strip.tr('_', '-') }
                              .reject(&:blank?)

    requested_locales.each do |requested|
      return requested if supported_locales.include?(requested)

      language_code = requested.split('-').first
      return 'pt-BR' if language_code == 'pt' && supported_locales.include?('pt-BR')
      return language_code if supported_locales.include?(language_code)
    end

    nil
  end
end
