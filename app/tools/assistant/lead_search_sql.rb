# frozen_string_literal: true

# Shared lead search predicate for assistant tools. Matches email, individual name
# fields, company, full_name, and CONCAT(first_name, ' ', last_name) so queries like
# "John Doe" find leads stored as separate first/last names.
module Assistant
  module LeadSearchSql
    LEAD_SEARCH_COLUMNS = <<~SQL.squish
      leads.email ILIKE :term
      OR leads.first_name ILIKE :term
      OR leads.last_name ILIKE :term
      OR leads.company ILIKE :term
      OR leads.full_name ILIKE :term
      OR CONCAT(leads.first_name, ' ', leads.last_name) ILIKE :term
    SQL

    module_function

    def search_term(query)
      "%#{ActiveRecord::Base.sanitize_sql_like(query.to_s.strip)}%"
    end

    def apply(scope, query)
      term = search_term(query)
      scope.where(LEAD_SEARCH_COLUMNS, term: term)
    end
  end
end
