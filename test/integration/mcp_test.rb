# frozen_string_literal: true

require 'test_helper'
require 'base64'
require 'digest'

class McpTest < ActionDispatch::IntegrationTest
  ISSUER = 'https://mcp.example.test'
  REDIRECT_URI = 'https://claude.ai/api/mcp/auth_callback'

  setup do
    @original_issuer = ENV['MCP_OAUTH_ISSUER']
    @original_app_host = ENV['APP_HOST']
    ENV['MCP_OAUTH_ISSUER'] = ISSUER
    Rails.cache.clear

    @nina  = accounts(:customer_admin)   # customer_admin, primary org (Acme)
    @noah  = accounts(:customer_user)    # customer_user, primary org (Acme)
    @sam   = accounts(:growth_lab_admin) # customer_admin, decoy org (Growth Lab)
    @dana  = accounts(:dana)             # dual-membership: Acme (primary) + Growth Lab (decoy)
    @admin = accounts(:amplifa_admin)    # amplifa_admin, no org => blocked from MCP

    @primary_org = organizations(:acme)
    @decoy_org   = organizations(:growth_lab)

    @primary_lead = leads(:john_doe)        # Acme lead ("Doe")
    @decoy_lead   = leads(:growth_lab_lead) # Growth Lab lead ("Prospect")
    @primary_conversation = conversations(:acme_john_conversation)
    @decoy_conversation   = conversations(:growth_lab_conversation)
  end

  teardown do
    ENV['MCP_OAUTH_ISSUER'] = @original_issuer
    ENV['APP_HOST'] = @original_app_host
    Rails.cache.clear
  end

  def test_missing_bearer_token_returns_unauthorized_with_metadata_challenge
    post mcp_path, params: json_rpc('initialize'), as: :json

    assert_response :unauthorized
    assert_includes response.headers['WWW-Authenticate'],
                    %(resource_metadata="#{ISSUER}/.well-known/oauth-protected-resource/mcp")
  end

  def test_wrong_bearer_token_returns_unauthorized
    post_mcp(json_rpc('initialize'), token: 'wrong-token')

    assert_response :unauthorized
  end

  def test_oauth_metadata_advertises_workspace_scope_and_endpoints
    get '/.well-known/oauth-authorization-server'

    assert_response :success
    metadata = JSON.parse(response.body)
    assert_equal ISSUER, metadata['issuer']
    assert_equal "#{ISSUER}/oauth/authorize", metadata['authorization_endpoint']
    assert_equal "#{ISSUER}/oauth/token", metadata['token_endpoint']
    assert_includes metadata['code_challenge_methods_supported'], 'S256'
    assert_equal [Mcp::OauthServer::SCOPE], metadata['scopes_supported']
    assert_equal 'mcp:workspace', Mcp::OauthServer::SCOPE
  end

  def test_dynamic_client_registration_returns_public_workspace_scoped_client
    client = register_mcp_client

    assert client['client_id'].present?
    assert_equal [REDIRECT_URI], client['redirect_uris']
    assert_equal 'none', client['token_endpoint_auth_method']
    assert_equal Mcp::OauthServer::SCOPE, client['scope']
    assert_nil client['client_secret']
  end

  def test_customer_user_can_authorize_and_obtain_access_token
    result = mcp_pkce_flow(@noah.email, 'password')

    assert result[:access_token].present?
    assert_equal @primary_org.id, result[:organization_id]

    post_mcp(json_rpc('initialize'), token: result[:access_token])
    assert_response :success
    assert_equal 'Amplifa MCP Server', parsed_response.dig('result', 'serverInfo', 'name')
  end

  def test_customer_admin_can_authorize_and_obtain_access_token
    result = mcp_pkce_flow(@nina.email, 'password')

    assert result[:access_token].present?
    assert_equal @primary_org.id, result[:organization_id]
  end

  def test_amplifa_admin_is_blocked_at_consent
    client = register_mcp_client
    pkce = pkce_pair
    login(@admin.email, 'password123')

    get '/oauth/authorize', params: authorization_params(client, pkce)
    assert_response :forbidden
    assert_match(/customer accounts only/i, response.body)

    post '/oauth/authorize', params: authorization_params(client, pkce)
    assert_response :forbidden
    assert_match(/customer accounts only/i, response.body)
  end

  def test_deactivated_account_cannot_obtain_token
    client = register_mcp_client
    pkce = pkce_pair
    code = authorize_code(@noah.email, 'password', client, pkce)

    @noah.deactivate!

    post '/oauth/token', params: token_params(client, pkce, code)
    assert_response :forbidden
    assert_equal 'account is not authorized', JSON.parse(response.body)['error_description']
  end

  def test_authorization_code_cannot_be_reused
    client = register_mcp_client
    pkce = pkce_pair
    code = authorize_code(@nina.email, 'password', client, pkce)

    post '/oauth/token', params: token_params(client, pkce, code)
    assert_response :success

    post '/oauth/token', params: token_params(client, pkce, code)
    assert_response :bad_request
    assert_equal 'code has already been used', JSON.parse(response.body)['error_description']
  end

  def test_refresh_token_rotates_and_old_token_invalidated
    result = mcp_pkce_flow(@nina.email, 'password')
    client_id = result[:client].fetch('client_id')

    assert_difference 'McpOauthRefreshToken.where.not(consumed_at: nil).count', 1 do
      post '/oauth/token', params: {
        grant_type: 'refresh_token', client_id: client_id, refresh_token: result[:refresh_token]
      }
      assert_response :success
    end
    rotated = JSON.parse(response.body)
    assert rotated['access_token'].present?
    refute_equal result[:refresh_token], rotated['refresh_token']

    post '/oauth/token', params: {
      grant_type: 'refresh_token', client_id: client_id, refresh_token: result[:refresh_token]
    }
    assert_response :bad_request
    assert_equal 'refresh_token has already been used', JSON.parse(response.body)['error_description']
  end

  def test_tools_list_returns_exactly_the_three_assistant_tools
    token = mcp_pkce_flow(@nina.email, 'password')[:access_token]

    post_mcp(json_rpc('tools/list'), token: token)

    assert_response :success
    tool_names = parsed_response.dig('result', 'tools').map { |tool| tool['name'] }
    assert_equal 3, tool_names.length
    assert_equal %w[conversation_list lead_search meeting_create], tool_names.sort
  end

  def test_conversation_list_returns_own_org_conversations_only
    token = mcp_pkce_flow(@nina.email, 'password')[:access_token]

    response_json = mcp_tool_call(token, 'conversation_list')

    assert_response :success
    assert_equal false, response_json.dig('result', 'isError')
    ids = structured_content.map { |row| row['id'] }
    assert_includes ids, @primary_conversation.id
    refute_includes ids, @decoy_conversation.id
  end

  def test_lead_search_returns_own_org_leads_only
    token = mcp_pkce_flow(@nina.email, 'password')[:access_token]

    own = mcp_tool_call(token, 'lead_search', { 'query' => 'Doe' })
    assert_equal false, own.dig('result', 'isError')
    own_ids = own.dig('result', 'structuredContent').map { |row| row['id'] }
    assert_includes own_ids, @primary_lead.id

    decoy = mcp_tool_call(token, 'lead_search', { 'query' => 'Prospect' })
    assert_equal false, decoy.dig('result', 'isError')
    assert_empty decoy.dig('result', 'structuredContent')
  end

  def test_meeting_create_cross_org_denial_rejects_decoy_org_lead
    token = mcp_pkce_flow(@nina.email, 'password')[:access_token]

    assert_no_difference 'Meeting.count' do
      denied = mcp_tool_call(token, 'meeting_create', {
        'lead_id' => @decoy_lead.id, 'scheduled_at' => 2.days.from_now.iso8601
      })
      assert_equal true, denied.dig('result', 'isError')
      assert_match(/not found|not accessible/i, denied.dig('result', 'content', 0, 'text'))
    end

    assert_no_difference 'Meeting.count' do
      own = mcp_tool_call(token, 'meeting_create', {
        'lead_id' => @primary_lead.id, 'scheduled_at' => 2.days.from_now.iso8601
      })
      assert_equal true, own.dig('result', 'isError')
      refute_match(/not found or not accessible/i, own.dig('result', 'content', 0, 'text'))
    end
  end

  def test_dual_membership_token_is_scoped_to_consented_primary_org
    result = mcp_pkce_flow(@dana.email, 'password')

    assert_equal @primary_org.id, result[:organization_id]

    own = mcp_tool_call(result[:access_token], 'lead_search', { 'query' => 'Doe' })
    own_ids = own.dig('result', 'structuredContent').map { |row| row['id'] }
    assert_includes own_ids, @primary_lead.id

    decoy = mcp_tool_call(result[:access_token], 'lead_search', { 'query' => 'Prospect' })
    assert_empty decoy.dig('result', 'structuredContent')
  end

  def test_token_rejected_after_consented_membership_deactivated
    token = mcp_pkce_flow(@dana.email, 'password')[:access_token]

    post_mcp(json_rpc('tools/list'), token: token)
    assert_response :success

    @dana.organization_memberships.find_by!(organization: @primary_org).update!(status: 'inactive')

    post_mcp(json_rpc('tools/list'), token: token)
    assert_response :forbidden
  end

  private

  def post_mcp(payload, token:)
    post mcp_path,
         params: payload.to_json,
         headers: {
           'Authorization' => "Bearer #{token}",
           'Content-Type' => 'application/json'
         }
  end

  def mcp_tool_call(access_token, tool_name, arguments = {})
    post_mcp(tool_call(tool_name, arguments), token: access_token)
    parsed_response
  end

  def mcp_pkce_flow(email, password)
    client = register_mcp_client
    pkce = pkce_pair
    code = authorize_code(email, password, client, pkce)

    post '/oauth/token', params: token_params(client, pkce, code)
    assert_response :success
    body = JSON.parse(response.body)
    access_token = body.fetch('access_token')

    {
      access_token: access_token,
      refresh_token: body.fetch('refresh_token'),
      organization_id: Mcp::OauthServer.verify_access_token(access_token)&.organization_id,
      client: client,
      pkce: pkce,
      code: code
    }
  end

  def authorize_code(email, password, client, pkce)
    login(email, password)

    get '/oauth/authorize', params: authorization_params(client, pkce)
    assert_response :success
    assert_includes response.body, 'Authorize Amplifa MCP'

    post '/oauth/authorize', params: authorization_params(client, pkce)
    assert_response :redirect

    redirected_uri = URI.parse(response.location)
    Rack::Utils.parse_nested_query(redirected_uri.query).fetch('code')
  end

  def login(email, password)
    post login_path, params: { email: email, password: password }
  end

  def register_mcp_client
    post '/oauth/register', params: {
      client_name: 'Claude Desktop',
      redirect_uris: [REDIRECT_URI],
      grant_types: %w[authorization_code refresh_token],
      response_types: ['code'],
      token_endpoint_auth_method: 'none'
    }, as: :json
    assert_response :created

    JSON.parse(response.body)
  end

  def json_rpc(method, params = {})
    { jsonrpc: '2.0', id: 1, method: method, params: params }
  end

  def tool_call(name, arguments)
    json_rpc('tools/call', { name: name, arguments: arguments })
  end

  def parsed_response
    JSON.parse(response.body)
  end

  def structured_content
    parsed_response.dig('result', 'structuredContent')
  end

  def authorization_params(client, pkce)
    {
      response_type: 'code',
      client_id: client.fetch('client_id'),
      redirect_uri: REDIRECT_URI,
      scope: Mcp::OauthServer::SCOPE,
      state: 'claude-state',
      code_challenge: pkce.fetch(:challenge),
      code_challenge_method: 'S256',
      resource: "#{ISSUER}/mcp"
    }
  end

  def token_params(client, pkce, code)
    {
      grant_type: 'authorization_code',
      code: code,
      client_id: client.fetch('client_id'),
      redirect_uri: REDIRECT_URI,
      code_verifier: pkce.fetch(:verifier),
      resource: "#{ISSUER}/mcp"
    }
  end

  def pkce_pair
    verifier = SecureRandom.urlsafe_base64(48)
    challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
    { verifier: verifier, challenge: challenge }
  end
end
