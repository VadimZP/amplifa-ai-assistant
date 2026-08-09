# frozen_string_literal: true

module Mcp
  # OAuth metadata, registration, authorization, and token endpoints for MCP clients.
  class OauthController < ApplicationController
    skip_before_action :authenticate
    skip_after_action :verify_authorized
    skip_after_action :verify_policy_scoped
    skip_forgery_protection only: %i[register token]

    def protected_resource
      render json: OauthServer.protected_resource_metadata
    end

    def authorization_server
      render json: OauthServer.authorization_server_metadata
    end

    def register
      render json: OauthServer.register_client(json_request_body), status: :created
    rescue OauthServer::Error => e
      render_oauth_error(e)
    end

    def client_registration
      render json: OauthServer.client_registration(
        client_id: params[:client_id].presence,
        registration_access_token: bearer_token.presence
      )
    rescue OauthServer::Error => e
      render_oauth_error(e)
    end

    def authorize
      authorization_params = OauthServer.validate_authorization_request!(params)
      return redirect_to_login_for_mcp_authorize unless current_account

      organization = mcp_authorized_organization
      return render plain: 'MCP access is available to customer accounts only.', status: :forbidden unless organization

      render html: authorization_form_html(authorization_params).html_safe
    rescue OauthServer::Error => e
      render plain: e.message, status: e.status
    end

    def approve
      authorization_params = OauthServer.validate_authorization_request!(params)
      return redirect_to_login_for_mcp_authorize unless current_account

      organization = mcp_authorized_organization
      return render plain: 'MCP access is available to customer accounts only.', status: :forbidden unless organization

      code = OauthServer.issue_authorization_code!(
        account: current_account,
        organization: organization,
        authorization_params: authorization_params
      )
      redirect_to authorization_redirect_uri(authorization_params, code), allow_other_host: true
    rescue OauthServer::Error => e
      render plain: e.message, status: e.status
    end

    def token
      token_response = case params[:grant_type]
                       when 'authorization_code'
                         OauthServer.exchange_authorization_code!(params)
                       when 'refresh_token'
                         OauthServer.refresh_access_token!(params)
                       else
                         raise OauthServer::Error, 'unsupported grant_type'
                       end

      response.headers['Cache-Control'] = 'no-store'
      response.headers['Pragma'] = 'no-cache'
      render json: token_response
    rescue OauthServer::Error => e
      render_oauth_error(e)
    end

    private

    def current_account
      @current_account ||= rodauth.rails_account
    end

    # WHY: Org is resolved server-side and embedded in the token, never selectable by the client (prevents cross-org access).
    def mcp_authorized_organization
      memberships = current_account.active_organization_memberships.includes(:organization)
      membership = memberships.find_by(organization_id: session[:current_organization_id]) if session[:current_organization_id]
      membership ||= memberships.first
      membership&.organization
    end

    def bearer_token
      request.authorization.to_s[/\ABearer (.+)\z/, 1]
    end

    def redirect_to_login_for_mcp_authorize
      session[:mcp_oauth_authorize_path] = request.fullpath
      cookies[:mcp_oauth_authorize_path] = {
        value: Rails.application.message_verifier('mcp_oauth_authorize_path').generate(
          request.fullpath,
          expires_in: 10.minutes,
          purpose: :mcp_oauth_authorize_path
        ),
        httponly: true,
        same_site: :lax,
        path: '/',
        expires: 10.minutes.from_now
      }
      redirect_to login_path
    end

    def authorization_redirect_uri(authorization_params, code)
      uri = URI.parse(authorization_params.fetch('redirect_uri'))
      query = Rack::Utils.parse_nested_query(uri.query).merge('code' => code)
      query['state'] = authorization_params['state'] if authorization_params['state'].present?
      uri.query = query.to_query
      uri.to_s
    end

    def authorization_form_html(authorization_params)
      hidden_fields = authorization_params.slice(
        'response_type', 'client_id', 'redirect_uri', 'scope', 'state', 'code_challenge', 'code_challenge_method', 'resource'
      ).map do |key, value|
        next if value.blank?

        %(<input type="hidden" name="#{ERB::Util.html_escape(key)}" value="#{ERB::Util.html_escape(value)}">)
      end.compact.join("\n")

      <<~HTML
        <!doctype html>
        <html>
          <head><title>Authorize Amplifa MCP</title></head>
          <body>
            <h1>Authorize Amplifa MCP</h1>
            <p>Allow this MCP client to access your Amplifa workspace on your behalf.</p>
            <form method="post" action="/oauth/authorize">
              #{hidden_fields}
              <input type="hidden" name="authenticity_token" value="#{ERB::Util.html_escape(form_authenticity_token)}">
              <button type="submit">Authorize MCP access</button>
            </form>
          </body>
        </html>
      HTML
    end

    def json_request_body
      return params.to_unsafe_h if request.request_parameters.present?

      JSON.parse(request.raw_post.presence || '{}')
    rescue JSON::ParserError
      raise OauthServer::Error, 'invalid JSON body'
    end

    def render_oauth_error(error)
      render json: { error: error.code, error_description: error.message }, status: error.status
    end
  end
end
