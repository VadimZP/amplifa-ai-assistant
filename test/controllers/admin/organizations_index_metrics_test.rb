# frozen_string_literal: true

require 'test_helper'

class Admin::OrganizationsIndexMetricsTest < ActionDispatch::IntegrationTest
  setup do
    @admin = accounts(:amplifa_admin)
    @organization = organizations(:acme)
  end

  test 'index omits computed sending metrics from organization cards' do
    login_as(@admin)

    get admin_organizations_path, headers: inertia_headers

    assert_response :success

    org = inertia_props.fetch('organizations').find { |entry| entry['id'] == @organization.id }
    assert org.present?

    assert_not org.key?('sending_metrics')
  end

end
