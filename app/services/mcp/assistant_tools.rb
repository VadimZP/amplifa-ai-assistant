# frozen_string_literal: true

module Mcp
  # Example user-scoped MCP tools for the Amplifa takehome assignment.
  # Each tool resolves the current user's organization from the token and
  # authorizes through Pundit — the same pattern candidates should follow
  # when building their own tools.
  class AssistantTools
    ToolError = Class.new(StandardError)

    def self.tool_definitions
      [
        {
          name: 'conversation_list',
          title: 'List Conversations',
          description: 'List email conversations for the current user\'s organization, optionally filtered by interest status or unread state.',
          inputSchema: {
            type: 'object',
            properties: {
              interest_status: { type: 'string', enum: %w[interested meeting_request not_interested neutral] },
              unread_only: { type: 'boolean' },
              limit: { type: 'integer', minimum: 1, maximum: 50 }
            },
            additionalProperties: false
          }
        },
        {
          name: 'meeting_create',
          title: 'Create Meeting',
          description: 'Create a meeting for a lead in the current user\'s organization.',
          inputSchema: {
            type: 'object',
            properties: {
              lead_id: { type: 'integer' },
              scheduled_at: { type: 'string', description: 'ISO 8601 datetime' },
              notes: { type: 'string' }
            },
            required: %w[lead_id scheduled_at],
            additionalProperties: false
          }
        },
        {
          name: 'lead_search',
          title: 'Search Leads',
          description: 'Search leads in the current user\'s organization by name, email, or company.',
          inputSchema: {
            type: 'object',
            properties: {
              query: { type: 'string' },
              limit: { type: 'integer', minimum: 1, maximum: 50 }
            },
            required: ['query'],
            additionalProperties: false
          }
        }
      ]
    end

    def initialize(account)
      @account = account
    end

    def call(tool_name, arguments)
      case tool_name
      when 'conversation_list' then conversation_list(arguments)
      when 'meeting_create' then meeting_create(arguments)
      when 'lead_search' then lead_search(arguments)
      else raise ToolError, "Unknown tool: #{tool_name}"
      end
    end

    private

    def organization
      Current.organization
    end

    def conversation_list(args)
      scope = policy_scope(Conversation).where(organization: organization)
      scope = scope.where(interest_status: args['interest_status']) if args['interest_status']
      if args['unread_only']
        read_ids = ConversationRead.where(account: @account).select(:conversation_id)
        scope = scope.where.not(id: read_ids)
      end
      limit = [args.fetch('limit', 25).to_i, 50].min
      scope.order(updated_at: :desc).limit(limit).map do |c|
        { id: c.id, interest_status: c.interest_status, updated_at: c.updated_at }
      end
    end

    def meeting_create(args)
      lead = policy_scope(Lead).find_by(id: args['lead_id'])
      raise ToolError, 'Lead not found or not accessible' unless lead

      meeting = Meeting.new(
        lead: lead,
        organization: organization,
        scheduled_at: Time.zone.parse(args['scheduled_at']),
        notes: args['notes']
      )
      authorize meeting, :create?
      meeting.save!
      { id: meeting.id, scheduled_at: meeting.scheduled_at }
    rescue ActiveRecord::RecordInvalid => e
      raise ToolError, e.message
    end

    def lead_search(args)
      query = args['query'].to_s.strip
      raise ToolError, 'Query is required' if query.blank?

      limit = [args.fetch('limit', 25).to_i, 50].min
      scope = policy_scope(Lead).where(organization: organization)
      results = scope.where(
        'leads.first_name ILIKE :q OR leads.last_name ILIKE :q OR leads.email ILIKE :q OR leads.company ILIKE :q',
        q: "%#{query}%"
      ).limit(limit)
      results.map { |l| { id: l.id, name: "#{l.first_name} #{l.last_name}", email: l.email, company: l.company } }
    end

    def policy_scope(klass)
      Pundit.policy_scope!(@account, klass)
    end

    def authorize(record, query)
      Pundit.authorize(@account, record, query)
    end
  end
end
