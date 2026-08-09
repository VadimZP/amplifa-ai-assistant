require "test_helper"

class CsrfAuthenticationFlowTest < ActionDispatch::IntegrationTest
  test "user can log in again after logging out without CSRF errors" do
    initial_token = inertia_csrf_token
    post login_path, params: login_params(initial_token)
    assert_response :redirect

    follow_redirect! while response.redirect?
    assert_response :success

    logout_token = session[:_csrf_token]
    post logout_path, params: { authenticity_token: logout_token }
    assert_response :redirect

    new_token = inertia_csrf_token
    refute_equal initial_token, new_token

    post login_path, params: login_params(new_token)
    assert_response :redirect
  end

  private

  def login_params(token)
    {
      authenticity_token: token,
      email: accounts(:amplifa_admin).email,
      password: "password123"
    }
  end

  def inertia_csrf_token
    get login_path, headers: inertia_headers
    assert_response :success
    assert_equal "application/json", response.media_type

    # Get the raw body - it may be duplicated due to streaming in tests
    raw_body = response.body.to_s

    # Extract only the first complete JSON object if body is duplicated
    depth = 0
    raw_body.each_char.with_index do |char, i|
      depth += 1 if char == "{"
      depth -= 1 if char == "}"
      if depth == 0 && i > 0
        raw_body = raw_body[0..i]
        break
      end
    end

    body = JSON.parse(raw_body)
    body.fetch("props").fetch("csrf_token")
  end

  def inertia_headers
    {
      "HTTP_X_INERTIA" => "true",
      "HTTP_ACCEPT" => "text/html, application/xhtml+xml",
      "HTTP_X_REQUESTED_WITH" => "XMLHttpRequest"
    }
  end
end
