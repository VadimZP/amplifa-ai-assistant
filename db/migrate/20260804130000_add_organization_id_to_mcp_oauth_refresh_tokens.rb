class AddOrganizationIdToMcpOauthRefreshTokens < ActiveRecord::Migration[8.1]
  def change
    return if column_exists?(:mcp_oauth_refresh_tokens, :organization_id)

    add_reference :mcp_oauth_refresh_tokens, :organization, null: true, foreign_key: true
  end
end
