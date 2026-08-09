# frozen_string_literal: true

require "test_helper"

class Api::V1::LeadImportsTest < ActionDispatch::IntegrationTest
  # WHY: The API endpoint enables frontend AJAX polling for import progress
  # without full page reloads. This is essential for long-running imports.

  test "amplifa admin can get lead import progress via API" do
    # WHY: Admins need to poll import status to show real-time progress bars
    admin = accounts(:amplifa_admin)
    login_as(admin)

    lead_import = lead_imports(:processing_import)

    get api_v1_lead_import_path(lead_import), as: :json
    assert_response :success

    json = JSON.parse(response.body)
    assert_equal lead_import.id, json["id"]
    assert_equal "processing", json["status"]
    assert_equal 500, json["total_rows"]
    assert_equal 250, json["processed_rows"]
    assert_equal 50, json["progress_percentage"]
    assert_equal 200, json["created_count"]
    assert_equal 50, json["updated_count"]
    assert json.key?("started_at")
    assert json.key?("completed_at")
    assert json.key?("duration_seconds")
    assert json.key?("errors_detail")
  end

  test "customer can view their organizations lead import progress" do
    # WHY: Customers should be able to see import progress for their own org's imports
    customer = accounts(:customer_admin)
    login_as(customer)

    # This import belongs to the same org (acme) as customer_admin
    lead_import = lead_imports(:completed_import)

    get api_v1_lead_import_path(lead_import), as: :json
    assert_response :success

    json = JSON.parse(response.body)
    assert_equal lead_import.id, json["id"]
    assert_equal "completed", json["status"]
    assert_equal 1000, json["total_rows"]
    assert_equal 100, json["progress_percentage"]
    assert_equal 850, json["created_count"]
    assert_equal 100, json["updated_count"]
    assert_equal 30, json["skipped_count"]
    assert_equal 15, json["blacklisted_count"]
    assert_equal 5, json["error_count"]
    assert_equal 2, json["errors_detail"].length
  end

  test "customer cannot view another organizations import progress" do
    # WHY: Authorization must prevent cross-organization data access
    customer = accounts(:customer_admin)
    login_as(customer)

    # This import belongs to a different org (beta) than customer_admin (acme)
    lead_import = lead_imports(:failed_import)

    get api_v1_lead_import_path(lead_import), as: :json
    assert_response :redirect

    follow_redirect!
    assert_match(/not authorized/i, flash[:alert])
  end

  test "returns 404 for non-existent lead import" do
    # WHY: Handle edge case when polling for a deleted or invalid import ID
    admin = accounts(:amplifa_admin)
    login_as(admin)

    get api_v1_lead_import_path(id: 999999), as: :json
    assert_response :not_found
  end

  test "unauthenticated request is redirected to login" do
    # WHY: API endpoints should require authentication like all other endpoints
    lead_import = lead_imports(:processing_import)

    get api_v1_lead_import_path(lead_import), as: :json
    assert_response :redirect
    assert_redirected_to login_path
  end
end
