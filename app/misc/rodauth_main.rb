require 'sequel/core'

class RodauthMain < Rodauth::Rails::Auth
  configure do
    # List of authentication features that are loaded.
    enable :create_account, :verify_account, :verify_account_grace_period,
           :login, :logout, :remember,
           :reset_password, :change_password, :change_login, :verify_login_change,
           :close_account

    # See the Rodauth documentation for the list of available config options:
    # http://rodauth.jeremyevans.net/documentation.html

    # ==> General
    # Initialize Sequel and have it reuse Active Record's database connection.
    db Sequel.postgres(extensions: :activerecord_connection, keep_reference: false)
    # Avoid DB query that checks accounts table schema at boot time.
    convert_token_id_to_integer? { Account.columns_hash['id'].type == :integer }

    # Change prefix of table and foreign key column names from default "account"
    # accounts_table :users
    # verify_account_table :user_verification_keys
    # verify_login_change_table :user_login_change_keys
    # reset_password_table :user_password_reset_keys
    # remember_table :user_remember_keys

    # The secret key used for hashing public-facing tokens for various features.
    # Defaults to Rails `secret_key_base`, but you can use your own secret key.
    # hmac_secret "b8375d904b6526685b9a86f9723bf3bb49c4c4c1cd18fea1ad355edabcbe40b9ce7cf24a7facea5e030f7874253acbb46116cfecee5a3187d9e02ffbadd96f59"

    # Accept only JSON requests.
    # only_json? true

    # Handle login and password confirmation fields on the client side.
    # require_password_confirmation? false
    # require_login_confirmation? false

    # Use path prefix for all routes.
    # prefix "/auth"

    # Specify the controller used for view rendering, CSRF, and callbacks.
    rails_controller { RodauthController }

    # Use Rails routing to render views through controller actions
    login_view { rails_controller_eval { login } }
    create_account_view { rails_controller_eval { create_account } }
    reset_password_request_view do
      if request.post? && field_error(login_param) == no_matching_login_message
        set_notice_flash reset_password_email_sent_notice_flash
        redirect reset_password_email_sent_redirect
      end

      rails_controller_eval { reset_password_request }
    end
    reset_password_view { rails_controller_eval { reset_password } }
    verify_account_view { rails_controller_eval { verify_account } }

    # Make built-in page titles accessible in your views via an instance variable.
    title_instance_variable :@page_title

    # Store account status in an integer column without foreign key constraint.
    account_status_column :status

    # Store password hash in a column instead of a separate table.
    account_password_hash_column :password_hash

    # Set password when creating account instead of when verifying.
    verify_account_set_password? false

    # Change some default param keys.
    login_param 'email'
    login_confirm_param 'email-confirm'
    # password_confirm_param "confirm_password"

    # Redirect back to originally requested location after authentication.
    # login_return_to_requested_location? true
    # two_factor_auth_return_to_requested_location? true # if using MFA

    # Autologin the user after they have reset their password.
    # reset_password_autologin? true

    # Delete the account record when the user has closed their account.
    # delete_account_on_close? true

    # Redirect to the app from login and registration pages if already logged in.
    # already_logged_in { redirect login_redirect }

    # ==> Emails
    # WHY: Show "Amplifa" as sender name instead of bare email address
    email_from "Amplifa <#{ENV.fetch('MAILER_FROM', 'noreply@updates.amplifa.eu')}>"

    create_reset_password_email do
      RodauthMailer.reset_password(self.class.configuration_name, account_id, reset_password_key_value)
    end

    create_verify_account_email do
      RodauthMailer.verify_account(self.class.configuration_name, account_id, verify_account_key_value)
    end

    create_email do |subject, body|
      Rodauth::Rails::Mailer.create_email(
        to: String.new(email_to.to_s),
        from: String.new(email_from.to_s),
        subject: String.new("#{email_subject_prefix}#{subject}"),
        body: String.new(body.to_s)
      )
    end

    send_email do |email|
      # queue email delivery on the mailer after the transaction commits
      db.after_commit { email.deliver_later }
    end

    # ==> Flash
    # Override default flash messages.
    reset_password_autologin? false
    reset_password_email_last_sent_column nil
    reset_password_email_sent_notice_flash { I18n.t('auth.forgot_password.email_sent') }
    reset_password_email_sent_redirect '/reset-password-request'
    reset_password_notice_flash 'Password reset worked, login now'
    reset_password_response do
      set_notice_flash reset_password_notice_flash
      redirect login_path
    end
    # create_account_notice_flash "Your account has been created. Please verify your account by visiting the confirmation link sent to your email address."
    # require_login_error_flash "Login is required for accessing this page"
    # login_notice_flash nil

    # ==> Validation
    # Override default validation error messages.
    # no_matching_login_message "user with this email address doesn't exist"
    # already_an_account_with_this_login_message "user with this email address already exists"
    # password_too_short_message { "needs to have at least #{password_minimum_length} characters" }
    # login_does_not_meet_requirements_message { "invalid email#{", #{login_requirement_message}" if login_requirement_message}" }

    # Passwords shorter than 8 characters are considered weak according to OWASP.
    password_minimum_length 8
    # bcrypt has a maximum input length of 72 bytes, truncating any extra bytes.
    password_maximum_bytes 72

    # Custom password complexity requirements (alternative to password_complexity feature).
    # password_meets_requirements? do |password|
    #   super(password) && password_complex_enough?(password)
    # end
    # auth_class_eval do
    #   def password_complex_enough?(password)
    #     return true if password.match?(/\d/) && password.match?(/[^a-zA-Z\d]/)
    #     set_password_requirement_error_message(:password_simple, "requires one number and one special character")
    #     false
    #   end
    # end

    # ==> Login redirect based on role
    login_redirect do
      account = Account.find(account_id)
      if account.amplifa_admin?
        rails_controller_eval do
          saved_mcp_oauth_path = session[:mcp_oauth_authorize_path].presence ||
                                 Rails.application.message_verifier('mcp_oauth_authorize_path').verified(
                                   cookies[:mcp_oauth_authorize_path].to_s,
                                   purpose: :mcp_oauth_authorize_path
                                 )
          cookies.delete(:mcp_oauth_authorize_path, path: '/')
          saved_mcp_oauth_path.presence || admin_dashboard_path
        end
      elsif (membership = account.switchable_organization_memberships.includes(:organization).order(:created_at).first)
        rails_controller_eval do
        session[:current_organization_id] = membership.organization_id
        cookies.delete(:mcp_oauth_authorize_path, path: '/')
        dashboard_path
        end
      else
        rails_controller_eval { cookies.delete(:mcp_oauth_authorize_path, path: '/') }
        rails_controller_eval { no_workspace_path }
      end
    end

    login_response do
      if @email_two_factor_challenge_id
        clear_session
        set_session_value(:email_two_factor_challenge_id, @email_two_factor_challenge_id)
        redirect(rails_controller_eval { two_factor_email_path })
      else
        set_notice_flash login_notice_flash
        redirect(saved_login_redirect || login_redirect)
      end
    end

    # ==> Remember Feature
    # Remember all fully logged in users.
    after_login do
      account = Account.find(account_id)
      if account.requires_email_two_factor_authentication?
        challenge = account.email_two_factor_challenges.active.newest_first.first
        saved_mcp_oauth_path = rails_controller_eval do
          session[:mcp_oauth_authorize_path].presence ||
            Rails.application.message_verifier('mcp_oauth_authorize_path').verified(
              cookies[:mcp_oauth_authorize_path].to_s,
              purpose: :mcp_oauth_authorize_path
            )
        end

        if challenge&.resend_available? || challenge.nil?
          account.email_two_factor_challenges.active.update_all(used_at: Time.current, updated_at: Time.current)
          challenge, raw_token = EmailTwoFactorChallenge.create_for!(
            account: account,
            return_to: saved_mcp_oauth_path.presence || saved_login_redirect,
            remember_login: true
          )
          RodauthMailer.email_two_factor(self.class.configuration_name, account.id, raw_token).deliver_later
        end

        @email_two_factor_challenge_id = challenge.id
      else
        remember_login
      end
    end

    # Or only remember users that have ticked a "Remember Me" checkbox on login.
    # after_login { remember_login if param_or_nil("remember") }

    # Extend user's remember period when remembered via a cookie
    extend_remember_deadline? true

    # ==> Hooks
    # Validate custom fields in the create account form.
    # before_create_account do
    #   throw_error_status(422, "name", "must be present") if param("name").empty?
    # end

    # Perform additional actions after the account is created.
    # after_create_account do
    #   Profile.create!(account_id: account_id, name: param("name"))
    # end

    # Do additional cleanup after the account is closed.
    # after_close_account do
    #   Profile.find_by!(account_id: account_id).destroy
    # end

    # ==> Deadlines
    # Change default deadlines for some actions.
    # verify_account_grace_period 3.days.to_i
    # reset_password_deadline_interval Hash[hours: 6]
    # verify_login_change_deadline_interval Hash[days: 2]
    # remember_deadline_interval Hash[days: 30]
  end
end
