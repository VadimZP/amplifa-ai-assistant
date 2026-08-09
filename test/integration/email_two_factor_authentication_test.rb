require 'test_helper'

class EmailTwoFactorAuthenticationTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    ActionMailer::Base.deliveries.clear
    @account = accounts(:customer_admin)
    @account.organization.update!(two_factor_authentication_required: true)
  end

  test 'organization user with required 2fa gets email challenge after valid password' do
    assert_difference 'EmailTwoFactorChallenge.count', 1 do
      perform_enqueued_jobs do
        post login_path, params: { email: @account.email, password: 'password' }
      end
    end

    assert_redirected_to two_factor_email_path
    get two_factor_email_path, headers: inertia_headers
    assert_response :success
    assert_inertia_component 'Auth/TwoFactorEmail'
    assert_equal @account.email, inertia_props['email']
    assert_equal [@account.email], ActionMailer::Base.deliveries.last.to
  end

  test 'password step alone does not authenticate protected pages' do
    perform_enqueued_jobs do
      post login_path, params: { email: @account.email, password: 'password' }
    end

    get dashboard_path

    assert_redirected_to login_path
  end

  test 'email verification link completes login in browser opening the link' do
    perform_enqueued_jobs do
      post login_path, params: { email: @account.email, password: 'password' }
    end

    verification_path = URI.parse(verification_url_from_last_email).request_uri
    reset!

    get verification_path

    assert_redirected_to dashboard_path
    follow_redirect!
    assert_response :success
    assert EmailTwoFactorChallenge.last.used_at.present?
  end

  test 'resend is blocked until countdown has elapsed' do
    perform_enqueued_jobs do
      post login_path, params: { email: @account.email, password: 'password' }
    end

    assert_no_difference 'ActionMailer::Base.deliveries.count' do
      post resend_two_factor_email_path
    end
    assert_redirected_to two_factor_email_path

    challenge = EmailTwoFactorChallenge.last
    challenge.update!(last_sent_at: 61.seconds.ago)

    assert_difference 'ActionMailer::Base.deliveries.count', 1 do
      perform_enqueued_jobs do
        post resend_two_factor_email_path
      end
    end
    assert_redirected_to two_factor_email_path
  end

  test 'repeated password login respects resend countdown' do
    perform_enqueued_jobs do
      post login_path, params: { email: @account.email, password: 'password' }
    end

    first_challenge = EmailTwoFactorChallenge.last

    assert_no_difference ['EmailTwoFactorChallenge.count', 'ActionMailer::Base.deliveries.count'] do
      perform_enqueued_jobs do
        post login_path, params: { email: @account.email, password: 'password' }
      end
    end

    assert_redirected_to two_factor_email_path
    assert_equal first_challenge.id, session[:email_two_factor_challenge_id]
  end

  test 'used verification link cannot be replayed' do
    perform_enqueued_jobs do
      post login_path, params: { email: @account.email, password: 'password' }
    end

    verification_path = URI.parse(verification_url_from_last_email).request_uri
    get verification_path
    assert_redirected_to dashboard_path

    reset!
    get verification_path

    assert_redirected_to login_path
    assert_equal I18n.t('auth.two_factor_email.invalid'), flash[:alert]
  end

  test 'expired verification link cannot authenticate' do
    perform_enqueued_jobs do
      post login_path, params: { email: @account.email, password: 'password' }
    end

    verification_path = URI.parse(verification_url_from_last_email).request_uri
    EmailTwoFactorChallenge.last.update!(expires_at: 1.minute.ago)
    reset!

    get verification_path

    assert_redirected_to login_path
    assert_equal I18n.t('auth.two_factor_email.invalid'), flash[:alert]
  end

  test 'invalid verification link cannot authenticate' do
    get verify_two_factor_email_path(token: 'not-a-real-token')

    assert_redirected_to login_path
    assert_equal I18n.t('auth.two_factor_email.invalid'), flash[:alert]
  end

  test 'amplifa admin does not require 2fa by default' do
    admin = accounts(:amplifa_admin)
    admin.update!(two_factor_authentication_required: false)

    assert_no_difference 'EmailTwoFactorChallenge.count' do
      perform_enqueued_jobs do
        post login_path, params: { email: admin.email, password: 'password123' }
      end
    end

    assert_redirected_to admin_dashboard_path
  end

  test 'amplifa admin requires 2fa when account flag is enabled' do
    admin = accounts(:amplifa_admin)
    admin.update!(two_factor_authentication_required: true)

    assert_difference 'EmailTwoFactorChallenge.count', 1 do
      perform_enqueued_jobs do
        post login_path, params: { email: admin.email, password: 'password123' }
      end
    end

    assert_redirected_to two_factor_email_path
    assert_equal [admin.email], ActionMailer::Base.deliveries.last.to
  end

  private

  def verification_url_from_last_email
    ActionMailer::Base.deliveries.last.text_part.body.to_s.match(%r{https?://\S+})[0]
  end
end
