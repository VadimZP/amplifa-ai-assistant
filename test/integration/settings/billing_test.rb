# frozen_string_literal: true

require 'test_helper'

class Settings::BillingTest < ActionDispatch::IntegrationTest
  setup do
    @customer_admin = accounts(:customer_admin)
    @acme = organizations(:acme)
  end

  test 'billing page includes billing-cycle day and real billing-cycle meetings count' do
    login_as(@customer_admin)

    @acme.update!(billing_cycle_started_on: Date.new(2026, 1, 17))

    travel_to Time.zone.local(2026, 3, 20, 12, 0, 0) do
      range = @acme.current_billing_cycle_range
      baseline_count = @acme.meetings.where(created_at: range).count

      @acme.meetings.create!(
        agent_lead: agent_leads(:john_in_draft),
        lead: leads(:john_doe),
        agent: agents(:draft_agent),
        status: 'scheduled',
        created_at: range.begin + 2.days,
        updated_at: range.begin + 2.days
      )

      @acme.meetings.create!(
        agent_lead: agent_leads(:john_in_draft),
        lead: leads(:john_doe),
        agent: agents(:draft_agent),
        status: 'scheduled',
        created_at: range.begin - 1.day,
        updated_at: range.begin - 1.day
      )

      get settings_billing_path, headers: inertia_headers

      assert_response :success
      assert_inertia_component 'Customer/Settings/Billing'

      assert_equal 4, inertia_props['billing_cycle_day']
      assert_equal (baseline_count + 1), inertia_props['billing_cycle_meetings_count']
      assert_equal 5, inertia_props['billing_cycle_meeting_limit']
      assert_equal @acme.next_billing_cycle_start.iso8601, inertia_props['billing_cycle_next_renewal_on']
    end
  end

  test 'billing page reflects organization selected plan and custom pricing' do
    login_as(@customer_admin)

    @acme.update!(
      plan_tier: 'growth',
      monthly_meeting_limit: 15,
      monthly_subscription: 2199
    )

    get settings_billing_path, headers: inertia_headers

    assert_response :success
    assert_inertia_component 'Customer/Settings/Billing'
    assert_equal 'growth', inertia_props['organization']['plan_tier']
    assert_equal 15, inertia_props['billing_cycle_meeting_limit']
    assert_equal '2199.0', inertia_props['organization']['monthly_subscription']
    assert_equal 'growth', inertia_props['current_plan']['identifier']
    assert_equal %w[basic enterprise growth scale], inertia_props['available_plans'].map { |plan| plan['identifier'] }.sort
    assert_equal 999, inertia_props['buying_signals_monthly_price']
  end

  test 'notify interest sends email to amplifa inbox with clicked button and account context' do
    login_as(@customer_admin)
    ActionMailer::Base.deliveries.clear

    perform_enqueued_jobs do
      post '/settings/billing/notify_interest', params: { action_name: 'upgrade_to_scale' }
    end

    assert_redirected_to settings_billing_path
    assert_match(/notified/i, flash[:notice])

    mail = ActionMailer::Base.deliveries.last
    assert_not_nil mail
    assert_equal ['hello@amplifa.ai'], mail.to
    assert_includes mail.subject, 'Upgrade to Scale'
    assert_includes mail.body.to_s, 'Upgrade to Scale'
    assert_includes mail.body.to_s, @customer_admin.email
    assert_includes mail.body.to_s, @acme.name
  end

  test 'enterprise contact sales CTA sends enterprise-specific notification' do
    login_as(@customer_admin)
    ActionMailer::Base.deliveries.clear

    perform_enqueued_jobs do
      post '/settings/billing/notify_interest', params: { action_name: 'contact_sales_enterprise_plan' }
    end

    assert_redirected_to settings_billing_path
    assert_match(/notified/i, flash[:notice])

    mail = ActionMailer::Base.deliveries.last
    assert_not_nil mail
    assert_equal ['hello@amplifa.ai'], mail.to
    assert_includes mail.subject, 'Contact Sales for Enterprise Plan'
    assert_includes mail.body.to_s, 'Contact Sales for Enterprise Plan'
    assert_includes mail.body.to_s, @customer_admin.email
    assert_includes mail.body.to_s, @acme.name
  end

  test 'notify interest includes lead context for buying signals upgrade CTA' do
    login_as(@customer_admin)
    lead = leads(:john_doe)
    ActionMailer::Base.deliveries.clear

    perform_enqueued_jobs do
      post '/settings/billing/notify_interest', params: {
        action_name: 'upgrade_for_buying_signals',
        lead_id: lead.id
      }
    end

    assert_redirected_to settings_billing_path
    assert_match(/notified/i, flash[:notice])

    mail = ActionMailer::Base.deliveries.last
    assert_not_nil mail
    assert_equal ['hello@amplifa.ai'], mail.to
    assert_includes mail.subject, 'Upgrade to get buying signals'
    assert_includes mail.body.to_s, @customer_admin.full_name
    assert_includes mail.body.to_s, @customer_admin.email
    assert_includes mail.body.to_s, @acme.name
    assert_includes mail.body.to_s, lead.display_name
    assert_includes mail.body.to_s, lead.email
    assert_includes mail.body.to_s, lead.company
  end

  test 'notify interest returns json success for buying signals CTA requests' do
    login_as(@customer_admin)
    lead = leads(:john_doe)
    ActionMailer::Base.deliveries.clear

    perform_enqueued_jobs do
      post '/settings/billing/notify_interest',
           params: {
             action_name: 'upgrade_for_buying_signals',
             lead_id: lead.id
           },
           as: :json
    end

    assert_response :success
    assert_equal 'Your account manager will be in touch shortly.', JSON.parse(response.body)['notice']

    mail = ActionMailer::Base.deliveries.last
    assert_not_nil mail
    assert_includes mail.subject, 'Upgrade to get buying signals'
    assert_includes mail.body.to_s, lead.display_name
  end
end
