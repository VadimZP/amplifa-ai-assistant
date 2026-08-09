# frozen_string_literal: true

# Customer-facing billing settings tab.
# Displays subscription info, plan details, and payment history.
# Currently all demo/placeholder data — no real billing system yet.
class Settings::BillingController < ApplicationController
  BILLING_INTEREST_ACTION_LABELS = {
    'get_10_more_meetings' => 'Get 10 more meetings',
    'upgrade_plan' => 'Upgrade plan',
    'upgrade_for_buying_signals' => 'Upgrade to get buying signals',
    'upgrade_to_annual' => 'Upgrade to Annual - Save 20%',
    'upgrade_to_growth' => 'Upgrade to Growth',
    'upgrade_to_scale' => 'Upgrade to Scale',
    'contact_sales_enterprise_plan' => 'Contact Sales for Enterprise Plan',
    'contact_sales' => 'Contact Sales'
  }.freeze

  skip_after_action :verify_policy_scoped
  skip_after_action :verify_authorized

  before_action :load_organization
  before_action :redirect_amplifa_admin

  def index
    skip_policy_scope
    authorize @organization, :show?
    app_setting = AppSetting.current
    current_plan = app_setting.billing_plan(@organization.plan_tier)

    render inertia: 'Customer/Settings/Billing', props: {
      organization: @organization.as_json(
        only: %i[id name monthly_subscription currency plan_tier monthly_meeting_limit]
      ),
      available_plans: app_setting.normalized_billing_plans,
      current_plan: current_plan,
      buying_signals_monthly_price: app_setting.buying_signals_monthly_price,
      billing_cycle_day: @organization.current_billing_cycle_day,
      billing_cycle_next_renewal_on: @organization.next_billing_cycle_start.iso8601,
      billing_cycle_meeting_limit: @organization.monthly_meeting_limit,
      billing_cycle_meetings_count: billing_cycle_meetings_count
    }
  end

  def notify_interest
    skip_policy_scope
    authorize @organization, :show?

    action_name = params[:action_name].to_s
    action_label = BILLING_INTEREST_ACTION_LABELS[action_name]

    if action_label.blank?
      return render json: { error: 'Invalid action' }, status: :unprocessable_entity if request.format.json?

      return redirect_to settings_billing_path, alert: 'Invalid action'
    end

    AdminNotificationMailer.billing_interest(
      @organization,
      current_account,
      action_name,
      action_label,
      resolve_interest_lead
    ).deliver_later

    return render json: { success: true, notice: 'Your account manager will be in touch shortly.' }, status: :ok if request.format.json?

    redirect_to settings_billing_path, notice: 'Thanks! We notified the Amplifa team.'
  end

  private

  def load_organization
    @organization = Current.organization
  end

  def redirect_amplifa_admin
    return unless current_account.amplifa_admin?

    skip_policy_scope
    redirect_to admin_dashboard_path and return
  end

  def billing_cycle_meetings_count
    @organization.meetings.where(created_at: @organization.current_billing_cycle_range).count
  end

  def resolve_interest_lead
    lead_id = params[:lead_id].presence
    return nil if lead_id.blank?

    @organization.leads.find_by(id: lead_id)
  end
end
