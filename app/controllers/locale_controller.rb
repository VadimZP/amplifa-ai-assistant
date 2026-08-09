class LocaleController < ApplicationController
  skip_after_action :verify_authorized
  skip_after_action :verify_policy_scoped
  skip_before_action :authenticate

  def update
    locale = params[:locale]

    unless SupportedLocale.include?(locale)
      return render json: { error: 'Invalid locale' }, status: :unprocessable_entity
    end

    session[:locale] = locale

    if current_account
      current_account.update!(locale: locale)

      if Current.organization_membership&.customer_admin? &&
         Current.organization.present? &&
         Current.organization.locale == 'en'
        Current.organization.update!(locale: locale)
      end
    end

    render json: { success: true, locale: locale }
  end
end
