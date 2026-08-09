# frozen_string_literal: true

# Minimal JSON-RPC MCP endpoint for user-scoped assistant tooling.
class McpController < ActionController::API
  include Pundit::Authorization

  JSONRPC_VERSION = '2.0'
  PROTOCOL_VERSION = '2025-11-25'

  before_action :authenticate_mcp_access_token!
  before_action :establish_mcp_workspace!

  def create
    request_payload = parse_request_payload
    return unless request_payload
    return head :accepted if json_rpc_notification?(request_payload)

    render json: dispatch_json_rpc(request_payload)
  end

  def show
    render plain: server_sent_event(tools_list_changed_notification), content_type: 'text/event-stream'
  end

  private

  def authenticate_mcp_access_token!
    @mcp_access_token = Mcp::OauthServer.verify_access_token(bearer_token)
    return if @mcp_access_token

    response.set_header('WWW-Authenticate', Mcp::OauthServer.www_authenticate_header)
    render json: { error: 'Unauthorized' }, status: :unauthorized
  end

  def establish_mcp_workspace!
    Current.account = @mcp_access_token.account
    Current.organization = Organization.find_by(id: @mcp_access_token.organization_id)
    Current.organization_membership = Current.account.organization_memberships
                                             .active.find_by(organization: Current.organization)
    return if Current.organization && Current.organization_membership

    render json: { error: 'Forbidden' }, status: :forbidden
  end

  def pundit_user
    @mcp_access_token.account
  end

  def parse_request_payload
    JSON.parse(request.raw_post)
  rescue JSON::ParserError
    render json: json_rpc_error(nil, -32_700, 'Parse error'), status: :bad_request
    nil
  end

  def dispatch_json_rpc(payload)
    return invalid_request_response(payload) unless valid_json_rpc_request?(payload)

    dispatch_json_rpc_method(payload)
  end

  def valid_json_rpc_request?(payload)
    payload.is_a?(Hash) && payload['jsonrpc'] == JSONRPC_VERSION && payload['method'].present?
  end

  def json_rpc_notification?(payload)
    valid_json_rpc_request?(payload) && !payload.key?('id')
  end

  def invalid_request_response(payload)
    json_rpc_error(payload.is_a?(Hash) ? payload['id'] : nil, -32_600, 'Invalid Request')
  end

  def dispatch_json_rpc_method(payload)
    method = payload['method']

    case method
    when 'initialize'
      initialize_response(payload['id'])
    when 'tools/list'
      tools_list_response(payload['id'])
    when 'tools/call'
      tools_call_response(payload['id'], payload['params'])
    else
      json_rpc_error(payload['id'], -32_601, "Method not found: #{method}")
    end
  end

  def initialize_response(id)
    json_rpc_result(id, {
                      protocolVersion: PROTOCOL_VERSION,
                      capabilities: { tools: { listChanged: true } },
                      serverInfo: { name: 'Amplifa MCP Server', version: '1.0.0' }
                    })
  end

  def tools_list_changed_notification
    { jsonrpc: JSONRPC_VERSION, method: 'notifications/tools/list_changed' }
  end

  def server_sent_event(payload)
    "event: message\ndata: #{payload.to_json}\n\n"
  end

  def tools_list_response(id)
    json_rpc_result(id, { tools: Mcp::AssistantTools.tool_definitions })
  end

  def tools_call_response(id, params)
    unless params.is_a?(Hash) && params['name'].present?
      return json_rpc_error(id, -32_602, 'tools/call requires a tool name')
    end

    result = Mcp::AssistantTools.new(@mcp_access_token.account).call(params['name'], params['arguments'] || {})
    json_rpc_result(id, tool_success(result))
  rescue Mcp::AssistantTools::ToolError => e
    json_rpc_result(id, tool_error(e.message))
  rescue Pundit::NotAuthorizedError
    json_rpc_result(id, tool_error('Not authorized'))
  end

  def tool_success(data)
    {
      content: [{ type: 'text', text: JSON.pretty_generate(data) }],
      structuredContent: data,
      isError: false
    }
  end

  def tool_error(message)
    {
      content: [{ type: 'text', text: message }],
      isError: true
    }
  end

  def json_rpc_result(id, result)
    { jsonrpc: JSONRPC_VERSION, id: id, result: result }
  end

  def json_rpc_error(id, code, message)
    { jsonrpc: JSONRPC_VERSION, id: id, error: { code: code, message: message } }
  end

  def bearer_token
    request.authorization.to_s[/\ABearer (.+)\z/, 1]
  end
end
