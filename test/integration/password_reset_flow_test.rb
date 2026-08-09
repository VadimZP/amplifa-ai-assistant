require 'test_helper'

class PasswordResetFlowTest < ActionDispatch::IntegrationTest
  test 'successful reset redirects to login with success flash' do
    account = accounts(:amplifa_admin)

    ActionMailer::Base.deliveries.clear

    perform_enqueued_jobs do
      post '/reset-password-request', params: { email: account.email }, headers: inertia_headers
    end
    assert_response :redirect

    reset_email = ActionMailer::Base.deliveries.last
    assert_not_nil reset_email
    reset_link = reset_email.body.encoded[%r{https?://[^"<\s]*/reset-password\?key=[^"<\s]+}]
    assert_not_nil reset_link

    reset_uri = URI.parse(reset_link)
    get "#{reset_uri.path}?#{reset_uri.query}", headers: inertia_headers
    assert_response :redirect
    assert_redirected_to '/reset-password'

    post '/reset-password',
         params: {
           password: 'VerySecure123!',
           'password-confirm': 'VerySecure123!'
         },
         headers: inertia_headers

    assert_response :redirect
    assert_redirected_to '/login'
    assert_equal 'Password reset worked, login now', flash[:notice]
  end
end
