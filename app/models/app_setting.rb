class AppSetting < ApplicationRecord
  DEFAULT_LINKEDIN_CONNECTION_LINK = 'https://example.com/connect'.freeze
  DEFAULT_BILLING_PLANS = [
    { identifier: 'basic', name: 'Basic', monthly_meeting_limit: 5, monthly_price: 1499 },
    { identifier: 'growth', name: 'Growth', monthly_meeting_limit: 15, monthly_price: 2499 },
    { identifier: 'scale', name: 'Scale', monthly_meeting_limit: 30, monthly_price: 3499 },
    { identifier: 'enterprise', name: 'Enterprise', monthly_meeting_limit: 100, monthly_price: 0 }
  ].freeze
  DEFAULT_BUYING_SIGNALS_MONTHLY_PRICE = 999
  DEFAULT_GLOBAL_SEQUENCE_PREVIEW_MODEL = Agent::DEFAULT_LLM_MODEL

  validates :linkedin_connection_link, presence: true, format: {
    with: URI::DEFAULT_PARSER.make_regexp(%w[http https]),
    message: 'must be a valid URL'
  }
  validates :global_sequence_preview_model, presence: true
  validates :buying_signals_monthly_price, numericality: { greater_than_or_equal_to: 0 }
  validate :validate_billing_plans

  before_validation :apply_defaults

  def self.current
    first || create!
  end

  def billing_plan(identifier)
    normalized_billing_plans.find { |plan| plan['identifier'] == identifier.to_s }
  end

  def normalized_billing_plans
    normalize_billing_plans(billing_plans)
  end

  private

  def apply_defaults
    self.linkedin_connection_link = DEFAULT_LINKEDIN_CONNECTION_LINK if linkedin_connection_link.blank?
    self.billing_plans = DEFAULT_BILLING_PLANS if billing_plans.blank?
    self.buying_signals_monthly_price = DEFAULT_BUYING_SIGNALS_MONTHLY_PRICE if buying_signals_monthly_price.blank?
    self.global_sequence_preview_model = DEFAULT_GLOBAL_SEQUENCE_PREVIEW_MODEL if global_sequence_preview_model.blank?
  end

  def validate_billing_plans
    plans = normalize_billing_plans(billing_plans)
    required_identifiers = DEFAULT_BILLING_PLANS.map { |plan| plan[:identifier] }.sort
    provided_identifiers = plans.map { |plan| plan['identifier'] }.sort

    if provided_identifiers != required_identifiers
      errors.add(:billing_plans, 'must include basic, growth, scale, and enterprise plans')
      return
    end

    plans.each do |plan|
      errors.add(:billing_plans, "#{plan['identifier']} name can't be blank") if plan['name'].blank?

      meeting_limit = Integer(plan['monthly_meeting_limit'], exception: false)
      if meeting_limit.nil? || meeting_limit <= 0
        errors.add(:billing_plans, "#{plan['identifier']} monthly meeting limit must be a positive number")
      end

      monthly_price = BigDecimal(plan['monthly_price'].to_s, exception: false)
      if monthly_price.nil? || monthly_price.negative?
        errors.add(:billing_plans, "#{plan['identifier']} monthly price must be zero or greater")
      end
    end
  end

  def normalize_billing_plans(raw_plans)
    return DEFAULT_BILLING_PLANS.map { |plan| plan.deep_stringify_keys } if raw_plans.blank?

    raw_plans.map do |plan|
      identifier = plan['identifier'] || plan[:identifier]
      name = plan['name'] || plan[:name]
      meeting_limit = plan['monthly_meeting_limit'] || plan[:monthly_meeting_limit]
      monthly_price = plan['monthly_price'] || plan[:monthly_price]

      {
        'identifier' => identifier.to_s,
        'name' => name.to_s,
        'monthly_meeting_limit' => Integer(meeting_limit, exception: false),
        'monthly_price' => BigDecimal(monthly_price.to_s, exception: false)&.to_f
      }
    end
  end
end
