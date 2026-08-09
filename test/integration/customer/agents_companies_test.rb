# frozen_string_literal: true

require 'test_helper'

class Customer::AgentsCompaniesTest < ActionDispatch::IntegrationTest
  test 'customer can view company table index' do
    login_as(accounts(:customer_admin))

    get '/agents/companies', headers: inertia_headers

    assert_response :success
    assert_inertia_component 'Customer/Agents/Companies'
    assert inertia_props['companies'].is_a?(Array)
    assert inertia_props['agents'].is_a?(Array)
    assert inertia_props['filters'].is_a?(Hash)
    assert inertia_props['pagination'].is_a?(Hash)
  end

  test 'company index groups rows by current company id' do
    login_as(accounts(:customer_admin))

    get '/agents/companies', headers: inertia_headers

    assert_response :success

    rows = inertia_props['companies']
    example_rows = rows.select { |row| row['id'] == companies(:example_corp).id }

    assert_equal 1, example_rows.size
    assert_equal 1, example_rows.first['leads_count']
    assert_equal ['Ready Campaign', 'Test Campaign'], example_rows.first['agents'].map { |agent| agent['name'] }.sort
    assert_equal ['not_contacted'], example_rows.first['delivery_statuses']
  end

  test 'company status filters include companies with any matching lead and count companies' do
    login_as(accounts(:customer_admin))
    agent_leads(:john_in_ready).update!(delivery_status: 'in_sequence')

    get '/agents/companies', headers: inertia_headers
    assert_response :success

    assert_equal 2, inertia_props.dig('status_counts', 'not_contacted')
    assert_equal 1, inertia_props.dig('status_counts', 'in_sequence')

    get '/agents/companies', params: { status: 'in_sequence' }, headers: inertia_headers
    assert_response :success

    rows = inertia_props['companies']
    assert_equal [companies(:example_corp).id], rows.map { |row| row['id'] }
    assert_equal ['in_sequence'], rows.first['delivery_statuses']
    assert_equal 'in_sequence', inertia_props.dig('filters', 'status')
    assert_equal 1, inertia_props.dig('pagination', 'total_count')
  end

  test 'company index groups each delivery status once per company row' do
    login_as(accounts(:customer_admin))
    agent_leads(:john_in_ready).update!(delivery_status: 'in_sequence')

    get '/agents/companies', headers: inertia_headers

    assert_response :success
    example_row = inertia_props['companies'].find { |row| row['id'] == companies(:example_corp).id }
    assert_equal ['not_contacted', 'in_sequence'], example_row['delivery_statuses']
  end

  private

  def create_buying_signals_summary!(agent:, markdown:)
    BuyingSignalsSummary.create!(
      company: companies(:example_corp),
      agent: agent,
      status: 'completed',
      raw_response_markdown: markdown,
      generated_at: Time.current,
      lookback_days: 120,
      prompt_version: 'test',
      model_id: 'test-model'
    )
  end
end
