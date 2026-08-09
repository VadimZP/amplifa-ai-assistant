class Organization < ApplicationRecord
  PLAN_TIERS = AppSetting::DEFAULT_BILLING_PLANS.map { |plan| plan[:identifier] }.freeze
  AUTO_FORWARD_INTERESTED_COMMENT_MODES = %w[none standard per_agent].freeze

  # ============================================================================
  # Associations
  # ============================================================================

  has_many :organization_memberships, dependent: :destroy
  has_many :accounts, through: :organization_memberships
  has_many :admin_activities, dependent: :destroy
  has_many :playbooks, dependent: :restrict_with_error
  has_many :leads, dependent: :restrict_with_error
  has_many :lead_imports, dependent: :destroy
  has_many :organization_files, dependent: :destroy
  has_many :organization_file_playbooks, through: :organization_files
  has_many :playbook_attachments, dependent: :destroy
  has_many :blacklists, dependent: :destroy
  has_many :email_domains, dependent: :restrict_with_error
  has_many :mailboxes, dependent: :restrict_with_error
  has_many :agents, dependent: :restrict_with_error
  has_many :senders, dependent: :destroy
  has_many :meetings, dependent: :destroy
  has_many :people, through: :leads
  has_many :conversations, dependent: :destroy

  before_validation :set_default_billing_cycle_started_on
  after_commit :ensure_website_domain_blacklisted, on: %i[create update], if: :saved_change_to_website?

  # ============================================================================
  # Validations
  # ============================================================================
  validates :name, presence: true, length: { maximum: 100 }
  validates :industry, length: { maximum: 100 }, allow_blank: true
  validates :size, inclusion: { in: %w[1-10 11-50 51-200 201-1000 1000+] }, allow_blank: true
  validates :website,
            format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]), message: 'must be a valid URL' }, allow_blank: true
  validates :status, inclusion: { in: %w[onboarding active paused churned] }
  validates :monthly_subscription, numericality: { greater_than_or_equal_to: 0, allow_nil: true }
  validates :monthly_meeting_limit, numericality: { only_integer: true, greater_than: 0 }
  validates :plan_tier, inclusion: { in: PLAN_TIERS }
  validates :meeting_price, numericality: { greater_than_or_equal_to: 0, allow_nil: true }
  validates :average_contract_value, numericality: { greater_than_or_equal_to: 0, allow_nil: true }
  validates :calendly_url,
            format: { with: %r{\Ahttps://calendly\.com/}, message: 'must start with https://calendly.com/' }, allow_blank: true
  validates :locale, inclusion: { in: SupportedLocale::ALL }
  validates :currency, inclusion: { in: %w[EUR USD GBP CHF] }
  validates :slack_webhook_url,
            format: { with: %r{\Ahttps://hooks\.slack\.com/}, message: 'must start with https://hooks.slack.com/' },
            allow_blank: true
  validates :auto_forward_interested_comment_mode, inclusion: { in: AUTO_FORWARD_INTERESTED_COMMENT_MODES }
  validates :auto_forward_interested_email, presence: true, if: :auto_forward_interested_enabled?
  validates :auto_forward_interested_email,
            format: { with: URI::MailTo::EMAIL_REGEXP, message: 'must be a valid email address' },
            allow_blank: true
  validates :welcome_back_email_enabled, inclusion: { in: [true, false] }

  def billing_cycle_anchor_date
    billing_cycle_started_on || Time.current.to_date.beginning_of_month
  end

  def billing_cycle_day
    billing_cycle_anchor_date.day
  end

  def current_billing_cycle_range(reference_time = Time.current)
    today = reference_time.to_date
    this_month_start = billing_cycle_start_for_month(today.year, today.month)
    cycle_start = if today < this_month_start
                    billing_cycle_start_for_month((today << 1).year,
                                                  (today << 1).month)
                  else
                    this_month_start
                  end
    next_cycle_start = billing_cycle_start_for_month((cycle_start >> 1).year, (cycle_start >> 1).month)

    cycle_start.beginning_of_day...next_cycle_start.beginning_of_day
  end

  def next_billing_cycle_start(reference_time = Time.current)
    current_billing_cycle_range(reference_time).end.to_date
  end

  def current_billing_cycle_day(reference_time = Time.current)
    cycle_start = current_billing_cycle_range(reference_time).begin.to_date
    (reference_time.to_date - cycle_start).to_i + 1
  end

  # Scopes
  scope :active, -> { where(deactivated_at: nil) }
  scope :not_archived, -> { where(archived_at: nil) }
  scope :onboarded, -> { where(onboarded: true) }
  scope :pending_onboarding, -> { where(onboarded: false) }
  scope :by_status, ->(status) { where(status: status) }

  # Status methods
  def active?
    deactivated_at.nil?
  end

  def deactivate!
    update!(deactivated_at: Time.current)
  end

  def archived?
    archived_at.present?
  end

  def archive!
    update!(archived_at: Time.current)
  end

  # Account methods
  def admin_accounts
    accounts_for_membership_roles('customer_admin')
  end

  def admin_users
    accounts_for_membership_roles('customer_admin')
  end

  def regular_users
    accounts_for_membership_roles('customer_user')
  end

  def all_users
    accounts_for_membership_roles(%w[customer_admin customer_user])
  end

  # Onboarding methods
  def onboarding_completion_percentage
    completed = onboarding_steps_completed.count
    total = OnboardingSteps::STEPS.count
    return 0 if total.zero?

    (completed.to_f / total * 100).round
  end

  def onboarding_steps_completed
    OnboardingSteps::STEPS.select { |_key, step| step[:check].call(self) }.keys
  end

  def onboarding_steps_pending
    OnboardingSteps::STEPS.keys - onboarding_steps_completed
  end

  def onboarding_complete?
    onboarding_steps_pending.empty?
  end

  def slack_configured?
    slack_webhook_url.present? && slack_notify_on_reply?
  end

  def ensure_website_domain_blacklist_entry!
    domain = normalized_website_domain
    return :skipped_no_domain if domain.blank?

    actor = blacklist_actor
    return :skipped_no_actor if actor.blank?

    entry = Blacklist.find_or_create_by!(organization: self, value: domain, value_type: 'domain') do |blacklist_entry|
      blacklist_entry.created_by = actor
      blacklist_entry.source = 'manual'
      blacklist_entry.reason = 'Organization domain'
    end

    entry.previously_new_record? ? :created : :existing
  rescue ActiveRecord::RecordNotUnique
    :existing
  end

  private

  def ensure_website_domain_blacklisted
    ensure_website_domain_blacklist_entry!
  end

  def normalized_website_domain
    return if website.blank?

    host = URI.parse(website).host&.downcase
    return if host.blank?

    host.sub(/\Awww\./, '')
  rescue URI::InvalidURIError
    nil
  end

  def blacklist_actor
    admin_users.order(:id).first ||
      accounts.order(:id).first ||
      Account.amplifa_admins.order(:id).first
  end

  def set_default_billing_cycle_started_on
    self.billing_cycle_started_on ||= Time.current.to_date.beginning_of_month
  end

  def billing_cycle_start_for_month(year, month)
    last_day = Date.new(year, month, -1).day
    Date.new(year, month, [billing_cycle_day, last_day].min)
  end

  def accounts_for_membership_roles(roles)
    Account
      .joins(:organization_memberships)
      .merge(OrganizationMembership.active)
      .where(organization_memberships: { organization_id: id, role: roles })
      .distinct
  end
end
