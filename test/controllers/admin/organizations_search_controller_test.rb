# frozen_string_literal: true

require 'test_helper'

module Admin
  class OrganizationsSearchTest < ActionDispatch::IntegrationTest
    setup do
      @admin = accounts(:amplifa_admin)
    end

    test 'index filters organizations by name search' do
      login_as(@admin)

      matching_org = Organization.create!(
        name: 'Searchable Admin Organization',
        status: 'onboarding',
        locale: 'en',
        currency: 'EUR'
      )

      Organization.create!(
        name: 'Different Organization Name',
        status: 'onboarding',
        locale: 'en',
        currency: 'EUR'
      )

      get admin_organizations_path, params: { search: 'searchable' }, headers: inertia_headers

      assert_response :success
      props = inertia_props

      assert_equal 'searchable', props['filters']['search']
      assert_equal([matching_org.id], props['organizations'].map { |org| org['id'] })
      assert_equal 1, props['pagination']['total_count']
    end

    test 'index preserves name search filter across pages' do
      login_as(@admin)

      search_term = 'Paginated Search Org'

      per_page = OrganizationsController::PER_PAGE

      (per_page + 1).times do |index|
        Organization.create!(
          name: "#{search_term} #{index}",
          status: 'onboarding',
          locale: 'en',
          currency: 'EUR'
        )
      end

      Organization.create!(
        name: 'Unrelated Organization',
        status: 'onboarding',
        locale: 'en',
        currency: 'EUR'
      )

      get admin_organizations_path, params: { search: search_term, page: 2 }, headers: inertia_headers

      assert_response :success
      props = inertia_props

      assert_equal search_term, props['filters']['search']
      assert_equal 2, props['pagination']['current_page']
      assert_equal per_page + 1, props['pagination']['total_count']
      assert_equal 1, props['organizations'].length
      assert(props['organizations'].all? { |org| org['name'].include?(search_term) })
    end
  end
end
