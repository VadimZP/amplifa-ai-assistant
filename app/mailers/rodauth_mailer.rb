class RodauthMailer < ApplicationMailer
  self.deliver_later_queue_name = :mailers
  default to: -> { @rodauth.email_to }, from: -> { @rodauth.email_from }

  def reset_password(name, account_id, key)
    @rodauth = rodauth(name, account_id) { @reset_password_key_value = key }
    @account = @rodauth.rails_account

    I18n.with_locale(@account.effective_locale) do
      mail(subject: I18n.t('mailers.password_reset.subject', default: 'Reset your Amplifa password'))
    end
  end

  def verify_account(name, account_id, key)
    @rodauth = rodauth(name, account_id) { @verify_account_key_value = key }
    @account = @rodauth.rails_account

    I18n.with_locale(@account.effective_locale) do
      mail(subject: I18n.t('mailers.verify_account.subject', default: 'Activate your Amplifa account'))
    end
  end

  def email_two_factor(name, account_id, token)
    @rodauth = rodauth(name, account_id)
    @account = @rodauth.rails_account
    @verification_url = Rails.application.routes.url_helpers.verify_two_factor_email_url(
      token: token,
      **mailer_url_options
    )

    I18n.with_locale(@account.effective_locale) do
      mail(subject: I18n.t('mailers.email_two_factor.subject'))
    end
  end

  private

  def rodauth(name, account_id, &block)
    instance = RodauthApp.rodauth(name).allocate
    instance.account_from_id(account_id)
    instance.instance_eval(&block) if block
    instance
  end

  def mailer_url_options
    options = Rails.application.config.action_mailer.default_url_options || {}
    return options if options[:host].present?

    options.merge(host: 'localhost', protocol: options[:protocol] || 'http')
  end
end
