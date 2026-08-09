# frozen_string_literal: true

# Applies URL-backed filters and sort order for the admin OOO dashboard list.
class AdminSettingsOooQuery
  INDEX_LIMIT = 100
  WELCOME_BACK_STATUS_FILTERS = %w[all none pending sent cancelled].freeze
  PERIOD_STATUS_FILTERS = %w[all active resolved].freeze
  SORT_FIELDS = %w[detected_at welcome_back_sent_at welcome_back_send_at return_date].freeze
  SORT_DIRECTIONS = %w[asc desc].freeze
  ORDER_FIELDS = {
    'welcome_back_sent_at' => [
      'welcome_back_messages.sent_at',
      'out_of_office_periods.welcome_back_send_at',
      'out_of_office_periods.id'
    ],
    'welcome_back_send_at' => [
      'out_of_office_periods.welcome_back_send_at',
      'out_of_office_periods.detected_at',
      'out_of_office_periods.id'
    ],
    'return_date' => [
      'out_of_office_periods.effective_return_date',
      'out_of_office_periods.detected_at',
      'out_of_office_periods.id'
    ]
  }.freeze

  attr_reader :filters, :sort

  def initialize(scope, params = {})
    @scope = scope
    @filters = normalize_filters(params)
    @sort = normalize_sort(params)
  end

  def records
    scope = apply_filters(@scope)
    scope = apply_sort(scope)
    scope.limit(INDEX_LIMIT)
  end

  private

  def normalize_filters(params)
    welcome_back_status = params[:welcome_back_status].to_s
    period_status = params[:period_status].to_s

    {
      welcome_back_status: normalized_value(welcome_back_status, WELCOME_BACK_STATUS_FILTERS),
      period_status: normalized_value(period_status, PERIOD_STATUS_FILTERS)
    }
  end

  def normalize_sort(params)
    field = params[:sort].to_s
    direction = params[:direction].to_s

    {
      field: normalized_value(field, SORT_FIELDS, fallback: 'detected_at'),
      direction: normalized_value(direction, SORT_DIRECTIONS, fallback: 'desc')
    }
  end

  def normalized_value(value, allowed_values, fallback: 'all')
    return value if allowed_values.include?(value)

    fallback
  end

  def apply_filters(scope)
    scope = apply_welcome_back_status_filter(scope)
    apply_period_status_filter(scope)
  end

  def apply_welcome_back_status_filter(scope)
    return scope if filters[:welcome_back_status] == 'all'

    scope.where(welcome_back_status: filters[:welcome_back_status])
  end

  def apply_period_status_filter(scope)
    case filters[:period_status]
    when 'active'
      scope.where(resolved_at: nil)
    when 'resolved'
      scope.where.not(resolved_at: nil)
    else
      scope
    end
  end

  def apply_sort(scope)
    return apply_detected_sort(scope) if detected_sort?

    scope = scope.joins(welcome_back_message_join) if sort[:field] == 'welcome_back_sent_at'
    scope.order(ordered_by(ORDER_FIELDS.fetch(sort[:field])))
  end

  def detected_sort?
    sort[:field] == 'detected_at'
  end

  def apply_detected_sort(scope)
    scope.order(detected_at: sort[:direction], created_at: sort[:direction], id: sort[:direction])
  end

  def welcome_back_message_join
    <<~SQL.squish
      LEFT OUTER JOIN generated_messages welcome_back_messages
        ON welcome_back_messages.out_of_office_period_id = out_of_office_periods.id
       AND welcome_back_messages.message_kind = 'welcome_back'
    SQL
  end

  def ordered_by(fields)
    primary_field, secondary_field, tie_breaker = fields

    Arel.sql(
      "#{primary_field} #{sort[:direction]} NULLS LAST, " \
      "#{secondary_field} #{sort[:direction]}, " \
      "#{tie_breaker} #{sort[:direction]}"
    )
  end
end
