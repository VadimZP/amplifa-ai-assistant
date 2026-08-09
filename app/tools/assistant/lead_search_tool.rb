# frozen_string_literal: true

# Searches leads in the current organization for the assistant. Mirrors the search pattern used
# in Customer::AgentsController#apply_lead_search so the assistant can answer the same questions
# the user could answer from the Agents UI.
module Assistant
  class LeadSearchTool < BaseTool
    DEFAULT_LIMIT = 20
    MAX_LIMIT = 50

    description 'Searches leads in the current organization by first name, last name, full name, ' \
                'email, or company. Returns matching rows plus total_count. Call this before ' \
                'answering any lead question — never claim a lead does not exist without calling ' \
                'this tool first. Read-only — does not change data.'

    param :query, desc: 'Free-text search over lead first name, last name, email and company',
                  required: true
    param :limit, type: :integer, desc: "Rows to return (default #{DEFAULT_LIMIT}, max #{MAX_LIMIT})",
                  required: false

    def execute(query:, limit: DEFAULT_LIMIT)
      term = query.to_s.strip
      return { error: 'Query is required.' } if term.blank?

      scope = apply_search(scoped(Lead), term)
      total = scope.count
      rows = scope.recent.limit(limit.to_i.clamp(1, MAX_LIMIT)).to_a

      { total_count: total, returned_count: rows.size, leads: serialize(rows) }
    end

    private

    def apply_search(scope, query)
      LeadSearchSql.apply(scope, query)
    end

    def serialize(rows)
      rows.map do |lead|
        {
          id: lead.id,
          name: lead.display_name,
          email: lead.email,
          company: lead.company,
          job_title: lead.job_title,
          blacklisted: lead.blacklisted?
        }
      end
    end
  end
end
