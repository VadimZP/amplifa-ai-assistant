# frozen_string_literal: true

require 'test_helper'

class PasswordResetRequestTest < ActionDispatch::IntegrationTest
  RESET_REQUEST_NOTICE = 'If an account exists for that email, we sent password reset instructions.'

  test 'requesting password reset enqueues mailer job with JSON-safe arguments' do
    account = accounts(:amplifa_admin)

    assert_enqueued_jobs 1, only: ActionMailer::MailDeliveryJob do
      post '/reset-password-request',
           params: { email: account.email },
           headers: inertia_headers
    end

    assert_response :redirect
    assert_equal RESET_REQUEST_NOTICE, flash[:notice]

    mail_job = enqueued_jobs.find { |job| job[:job] == ActionMailer::MailDeliveryJob }
    refute_nil mail_job
    refute safe_buffer?(mail_job[:args])
  end

  test 'requesting password reset for unknown email shows generic success without email' do
    assert_no_enqueued_jobs only: ActionMailer::MailDeliveryJob do
      post '/reset-password-request',
           params: { email: 'unknown@example.com' },
           headers: inertia_headers
    end

    assert_response :redirect
    assert_redirected_to '/reset-password-request'
    assert_equal RESET_REQUEST_NOTICE, flash[:notice]
    assert_nil flash[:error]
  end

  private

  def safe_buffer?(value)
    return true if value.is_a?(ActiveSupport::SafeBuffer)

    case value
    when Array
      value.any? { |item| safe_buffer?(item) }
    when Hash
      value.any? { |key, item| safe_buffer?(key) || safe_buffer?(item) }
    else
      false
    end
  end
end
