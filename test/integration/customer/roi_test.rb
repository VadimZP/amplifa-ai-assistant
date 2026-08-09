# frozen_string_literal: true

require 'test_helper'

class Customer::RoiTest < ActionDispatch::IntegrationTest
  test 'roi counts sent emails from ready agents' do
    login_as(accounts(:customer_admin))

    step = SequenceStep.create!(
      agent: agents(:ready_agent),
      position: 3,
      event_type: 'email',
      name: 'ROI test step',
      delay_days: 0,
      active: true
    )

    GeneratedMessage.create!(
      agent_lead: agent_leads(:john_in_ready),
      sequence_step: step,
      subject: 'Checking in',
      body: 'Quick follow-up',
      status: 'sent',
      sent_at: 1.day.ago
    )

    get roi_path, headers: inertia_headers

    assert_response :success
    props = JSON.parse(response.body).fetch('props')
    metrics = props.fetch('metrics')

    assert_equal 1, metrics.fetch('emails_sent')
    assert_equal organizations(:acme).meetings.count, metrics.fetch('total_meetings')
    assert_equal((metrics.fetch('total_meetings').to_f / metrics.fetch('leads_contacted') * 100).round(1),
                 metrics.fetch('meeting_rate'))
    assert_equal true, props.fetch('can_edit_metrics')
  end

  test 'customer admin can update acv from roi screen' do
    admin = accounts(:customer_admin)
    login_as(admin)

    organization = admin.organization

    patch roi_path, params: {
      organization: {
        average_contract_value: 31_000
      }
    }

    assert_response :redirect
    assert_redirected_to roi_path(suppress_flash: true)

    organization.reload
    assert_equal 31_000.0, organization.average_contract_value.to_f
  end

  test 'customer user can update roi financial values' do
    user = accounts(:customer_user)
    login_as(user)

    organization = user.organization

    patch roi_path, params: {
      organization: {
        average_contract_value: 9999
      }
    }

    assert_response :redirect
    assert_redirected_to roi_path(suppress_flash: true)

    organization.reload
    assert_equal 9999.0, organization.average_contract_value.to_f
  end

  test 'customer user sees editable roi metrics' do
    user = accounts(:customer_user)
    login_as(user)

    get roi_path, headers: inertia_headers

    assert_response :success
    props = JSON.parse(response.body).fetch('props')
    assert_equal true, props.fetch('can_edit_metrics')
  end
end
