require 'test_helper'

class CompanyTest < ActiveSupport::TestCase
  test 'normalizes website url and domain' do
    company = Company.create!(name: 'Fresh Corp', website_url: 'www.freshcorp.com')

    assert_equal 'https://www.freshcorp.com', company.website_url
    assert_equal 'freshcorp.com', company.normalized_domain
    assert_equal 'freshcorp.com', company.domain
  end

end
