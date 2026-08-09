# frozen_string_literal: true

require 'base64'
require 'cgi'
require 'digest'
require 'uri'

module Mcp
  # Minimal OAuth 2.1 server helpers for Claude remote MCP connectors.
  class OauthServer
    AccessToken = Struct.new(:account, :scope, :organization_id, keyword_init: true)

    SCOPE = 'mcp:workspace'
    PROTOCOL_VERSION = '2025-11-25'
    ACCESS_TOKEN_TTL = 1.hour
    AUTHORIZATION_CODE_TTL = 5.minutes
    REFRESH_TOKEN_TTL = 30.days
    MAX_REDIRECT_URIS = 10
    MAX_URI_LENGTH = 2_048

    class Error < StandardError
      attr_reader :code, :status

      def initialize(message, code: 'invalid_request', status: :bad_request)
        super(message)
        @code = code
        @status = status
      end
    end

    class << self
      def issuer
        configured_issuer.presence || default_issuer
      end

      def resource
        "#{issuer}/mcp"
      end

      def protected_resource_metadata
        {
          resource: resource,
          authorization_servers: [issuer],
          scopes_supported: [SCOPE],
          bearer_methods_supported: ['header'],
          resource_documentation: issuer
        }
      end

      def protected_resource_metadata_url
        "#{issuer}/.well-known/oauth-protected-resource/mcp"
      end

      def authorization_server_metadata
        {
          issuer: issuer,
          authorization_endpoint: "#{issuer}/oauth/authorize",
          token_endpoint: "#{issuer}/oauth/token",
          registration_endpoint: "#{issuer}/oauth/register",
          response_types_supported: ['code'],
          response_modes_supported: ['query'],
          grant_types_supported: %w[authorization_code refresh_token],
          code_challenge_methods_supported: ['S256'],
          token_endpoint_auth_methods_supported: ['none'],
          registration_endpoint_auth_methods_supported: ['none'],
          scopes_supported: [SCOPE]
        }
      end

      def register_client(params)
        attributes = normalize_params(params)
        validate_client_registration!(attributes)

        issued_at = Time.current.to_i
        payload = {
          'client_name' => attributes['client_name'].presence || 'Claude MCP Client',
          'redirect_uris' => attributes.fetch('redirect_uris'),
          'issued_at' => issued_at,
          'jti' => SecureRandom.uuid
        }

        client_id = client_verifier.generate(payload, purpose: :client)
        registration_access_token = registration_verifier.generate(payload, purpose: :client_registration)
        client_registration_response(client_id, payload, registration_access_token)
      end

      def client_registration(client_id:, registration_access_token: nil)
        payload = registration_payload(client_id, registration_access_token)
        client_id ||= client_verifier.generate(payload, purpose: :client)
        registration_access_token ||= registration_verifier.generate(payload, purpose: :client_registration)

        client_registration_response(client_id, payload, registration_access_token)
      end

      def validate_authorization_request!(params)
        attributes = normalize_params(params)
        client = verify_client!(attributes['client_id'])
        redirect_uri = attributes['redirect_uri'].to_s

        raise Error, 'response_type must be code' unless attributes['response_type'] == 'code'
        raise Error, 'redirect_uri is invalid' unless client.fetch('redirect_uris').include?(redirect_uri)
        raise Error, 'code_challenge is required' if attributes['code_challenge'].blank?
        raise Error, 'code_challenge_method must be S256' unless attributes['code_challenge_method'] == 'S256'
        validate_resource!(attributes['resource'])
        scope = normalize_scope(attributes['scope'])

        attributes.merge('scope' => scope)
      end

      def issue_authorization_code!(account:, organization:, authorization_params:)
        unless authorized_mcp_account?(account)
          raise Error.new('MCP access requires an active account', code: 'access_denied', status: :forbidden)
        end
        unless organization
          raise Error.new('MCP access is available to customer accounts only', code: 'access_denied', status: :forbidden)
        end

        jti = SecureRandom.uuid
        code_payload = authorization_params.slice(
          'client_id', 'redirect_uri', 'scope', 'code_challenge', 'code_challenge_method'
        ).merge(
          'account_id' => account.id,
          'organization_id' => organization.id,
          'aud' => resource,
          'jti' => jti
        )

        Rails.cache.write(issued_code_cache_key(jti), true, expires_in: AUTHORIZATION_CODE_TTL)
        code_verifier.generate(code_payload, expires_in: AUTHORIZATION_CODE_TTL, purpose: :authorization_code)
      end

      def exchange_authorization_code!(params)
        attributes = normalize_params(params)
        raise Error, 'grant_type must be authorization_code' unless attributes['grant_type'] == 'authorization_code'

        payload = verify_authorization_code!(attributes['code'])
        validate_code_exchange!(payload, attributes)
        consume_authorization_code!(payload.fetch('jti'))
        issue_token_pair!(payload.fetch('account_id'), payload.fetch('scope'), payload.fetch('client_id'), payload.fetch('organization_id'))
      end

      def refresh_access_token!(params)
        attributes = normalize_params(params)
        raise Error, 'grant_type must be refresh_token' unless attributes['grant_type'] == 'refresh_token'

        payload = verify_refresh_token!(attributes['refresh_token'])
        raise Error, 'client_id does not match refresh_token' unless attributes['client_id'] == payload.fetch('client_id')

        consume_refresh_token!(payload.fetch('jti'))
        issue_token_pair!(payload.fetch('account_id'), payload.fetch('scope'), payload.fetch('client_id'), payload.fetch('organization_id'))
      end

      def verify_access_token(token)
        payload = access_token_verifier.verified(token.to_s, purpose: :access_token)
        return unless payload.is_a?(Hash)
        return unless payload['aud'] == resource
        return unless scope_includes?(payload['scope'], SCOPE)

        account = Account.find_by(id: payload['account_id'])
        return unless authorized_mcp_account?(account)

        AccessToken.new(account: account, scope: payload['scope'], organization_id: payload['organization_id'])
      end

      def www_authenticate_header
        %(Bearer realm="mcp", resource_metadata="#{protected_resource_metadata_url}", scope="#{SCOPE}")
      end

      private

      def normalize_params(params)
        if params.respond_to?(:to_unsafe_h)
          params.to_unsafe_h.deep_stringify_keys
        else
          params.to_h.deep_stringify_keys
        end
      end

      def validate_client_registration!(attributes)
        supported_auth_methods = %w[none client_secret_post client_secret_basic]
        unless attributes['token_endpoint_auth_method'].blank? || attributes['token_endpoint_auth_method'].in?(supported_auth_methods)
          raise Error, 'token_endpoint_auth_method is unsupported'
        end
        unless Array(attributes['grant_types'].presence || ['authorization_code']).all? { |entry| entry.in?(%w[authorization_code refresh_token]) }
          raise Error, 'grant_types contains unsupported values'
        end
        unless Array(attributes['response_types'].presence || ['code']).all? { |entry| entry == 'code' }
          raise Error, 'response_types contains unsupported values'
        end

        redirect_uris = attributes['redirect_uris']
        raise Error, 'redirect_uris must be an array' unless redirect_uris.is_a?(Array)
        raise Error, 'redirect_uris is empty' if redirect_uris.empty?
        raise Error, 'too many redirect_uris' if redirect_uris.length > MAX_REDIRECT_URIS

        redirect_uris.each { |uri| validate_redirect_uri!(uri) }
      end

      def registration_payload(client_id, registration_access_token)
        payload = if registration_access_token.present?
                    registration_verifier.verified(registration_access_token.to_s, purpose: :client_registration)
                  else
                    client_verifier.verified(client_id.to_s, purpose: :client)
                  end
        raise Error, 'client registration is invalid' unless payload.is_a?(Hash)

        payload
      end

      def client_registration_response(client_id, payload, registration_access_token)
        {
          client_id: client_id,
          client_id_issued_at: payload.fetch('issued_at'),
          client_name: payload.fetch('client_name'),
          redirect_uris: payload.fetch('redirect_uris'),
          grant_types: %w[authorization_code refresh_token],
          response_types: ['code'],
          token_endpoint_auth_method: 'none',
          registration_client_uri: registration_client_uri(client_id),
          registration_access_token: registration_access_token,
          scope: SCOPE,
          public: true
        }
      end

      def registration_client_uri(client_id)
        "#{issuer}/oauth/register/#{CGI.escape(client_id)}"
      end

      def validate_redirect_uri!(uri)
        raise Error, 'redirect_uri must be a string' unless uri.is_a?(String)
        raise Error, 'redirect_uri is too long' if uri.length > MAX_URI_LENGTH

        parsed = URI.parse(uri)
        raise Error, 'redirect_uri must not include a fragment' if parsed.fragment.present?

        return if parsed.scheme == 'https' && parsed.host.present?
        return if parsed.scheme == 'http' && loopback_host?(parsed.host)

        raise Error, 'redirect_uri must be HTTPS or loopback HTTP'
      rescue URI::InvalidURIError
        raise Error, 'redirect_uri is invalid'
      end

      def validate_resource!(candidate)
        return if candidate.blank? || candidate == resource

        raise Error, 'resource is invalid'
      end

      def normalize_scope(scope)
        requested_scopes = scope.to_s.split.presence || [SCOPE]
        return requested_scopes.join(' ') if requested_scopes.all? { |entry| entry == SCOPE }

        raise Error.new('scope is invalid', code: 'invalid_scope')
      end

      def verify_client!(client_id)
        payload = client_verifier.verified(client_id.to_s, purpose: :client)
        raise Error, 'client_id is invalid' unless payload.is_a?(Hash)

        payload
      end

      def verify_authorization_code!(code)
        payload = code_verifier.verified(code.to_s, purpose: :authorization_code)
        raise Error, 'code is invalid' unless payload.is_a?(Hash)

        payload
      end

      def verify_refresh_token!(refresh_token)
        payload = refresh_token_verifier.verified(refresh_token.to_s, purpose: :refresh_token)
        raise Error, 'refresh_token is invalid' unless payload.is_a?(Hash)

        payload
      end

      def validate_code_exchange!(payload, attributes)
        raise Error, 'client_id does not match code' unless attributes['client_id'] == payload.fetch('client_id')
        raise Error, 'redirect_uri does not match code' unless attributes['redirect_uri'] == payload.fetch('redirect_uri')
        validate_resource!(attributes['resource'])
        validate_pkce!(payload.fetch('code_challenge'), attributes['code_verifier'])
      end

      def validate_pkce!(expected_challenge, verifier)
        raise Error, 'code_verifier is required' if verifier.blank?

        digest = Digest::SHA256.digest(verifier)
        actual_challenge = Base64.urlsafe_encode64(digest, padding: false)
        return if ActiveSupport::SecurityUtils.secure_compare(expected_challenge, actual_challenge)

        raise Error, 'code_verifier is invalid'
      end

      def consume_authorization_code!(jti)
        raise Error, 'code is invalid' unless Rails.cache.exist?(issued_code_cache_key(jti))

        consumed = Rails.cache.write(consumed_code_cache_key(jti), true, expires_in: AUTHORIZATION_CODE_TTL, unless_exist: true)
        raise Error, 'code has already been used' unless consumed
      end

      def consume_refresh_token!(jti)
        McpOauthRefreshToken.transaction do
          token = McpOauthRefreshToken.lock.find_by(jti: jti)
          raise Error, 'refresh_token is invalid' unless token
          raise Error, 'refresh_token has expired' if token.expired?
          raise Error, 'refresh_token has already been used' if token.consumed?

          token.update!(consumed_at: Time.current)
        end
      end

      def issue_token_pair!(account_id, scope, client_id, organization_id)
        account = Account.find_by(id: account_id)
        raise Error.new('account is not authorized', code: 'access_denied', status: :forbidden) unless authorized_mcp_account?(account)

        refresh_jti = SecureRandom.uuid
        refresh_payload = token_payload(account.id, scope, client_id, organization_id).merge('jti' => refresh_jti)
        McpOauthRefreshToken.create!(
          jti: refresh_jti,
          account: account,
          client_id: client_id,
          scope: scope,
          aud: resource,
          organization_id: organization_id,
          expires_at: REFRESH_TOKEN_TTL.from_now
        )

        {
          access_token: access_token_verifier.generate(
            token_payload(account.id, scope, client_id, organization_id),
            expires_in: ACCESS_TOKEN_TTL,
            purpose: :access_token
          ),
          token_type: 'Bearer',
          expires_in: ACCESS_TOKEN_TTL.to_i,
          refresh_token: refresh_token_verifier.generate(
            refresh_payload,
            expires_in: REFRESH_TOKEN_TTL,
            purpose: :refresh_token
          ),
          scope: scope
        }
      end

      def token_payload(account_id, scope, client_id, organization_id)
        {
          'account_id' => account_id,
          'client_id' => client_id,
          'scope' => scope,
          'organization_id' => organization_id,
          'aud' => resource,
          'iat' => Time.current.to_i
        }
      end

      def scope_includes?(scope, required_scope)
        scope.to_s.split.include?(required_scope)
      end

      def authorized_mcp_account?(account)
        account&.active?
      end

      def loopback_host?(host)
        %w[localhost 127.0.0.1 ::1].include?(host)
      end

      def configured_issuer
        ENV['MCP_OAUTH_ISSUER'].presence ||
          issuer_from_app_host ||
          default_issuer
      end

      def default_issuer
        return 'https://amplifa.ai' if Rails.env.production?

        'http://localhost:3000'
      end

      def issuer_from_app_host
        host = ENV['APP_HOST'].to_s.strip.delete_suffix('/')
        return if host.blank?
        return host if host.start_with?('http://', 'https://')

        "https://#{host}"
      end

      def client_verifier
        Rails.application.message_verifier('mcp_oauth_client')
      end

      def code_verifier
        Rails.application.message_verifier('mcp_oauth_code')
      end

      def access_token_verifier
        Rails.application.message_verifier('mcp_oauth_access_token')
      end

      def refresh_token_verifier
        Rails.application.message_verifier('mcp_oauth_refresh_token')
      end

      def registration_verifier
        Rails.application.message_verifier('mcp_oauth_registration')
      end

      def issued_code_cache_key(jti)
        "mcp:oauth:code:issued:#{jti}"
      end

      def consumed_code_cache_key(jti)
        "mcp:oauth:code:consumed:#{jti}"
      end

    end
  end
end
