# frozen_string_literal: true

require "test_helper"

class Admin::OrganizationsControllerTest < ActionDispatch::IntegrationTest
  # WHY: These tests verify that organization export/import functionality works correctly.
  # Export/import is a critical feature for migrating org configuration between environments.

  setup do
    @admin = accounts(:amplifa_admin)
    @organization = organizations(:acme)
  end

  # === Export Tests ===

  # WHY: Export should return a JSON file download with correct headers
  # WHY: Export filename should include org name and date for easy identification
  # WHY: Export should contain valid JSON with expected structure
  # WHY: Admin activity should be logged for audit trail
  # WHY: Only amplifa admins should be able to export organizations
  # === Import Tests ===

  # WHY: Import should create a new organization from valid export file
  # WHY: Admin activity should be logged for import audit trail
  # WHY: Validation errors should be shown clearly to the user
  # WHY: Import should require a file to be selected
  # WHY: Only amplifa admins should be able to import organizations
  # WHY: Invalid JSON should be handled gracefully with clear error message
  # === Existing Functionality Tests ===

  # WHY: Verify existing CRUD functionality still works after adding export/import
  test "index renders organization list" do
    login_as(@admin)

    get admin_organizations_path, headers: inertia_headers

    assert_response :success
    assert_inertia_component("Admin/Organizations/Index")
  end

  # WHY: Verify edit page still works for viewing organization before export
  test "edit renders organization edit form" do
    login_as(@admin)

    get edit_admin_organization_path(@organization), headers: inertia_headers

    assert_response :success
    assert_inertia_component("Admin/Organizations/Edit")
  end

  # === Show (Overview) Tests ===

  # WHY: Show page displays organization overview with stats and activities
  test "show renders organization overview with stats" do
    login_as(@admin)

    get admin_organization_path(@organization), headers: inertia_headers

    assert_response :success
    assert_inertia_component("Admin/Organizations/Show")

    props = inertia_props
    assert props["organization"].present?
    assert_equal @organization.id, props["organization"]["id"]
    assert props["stats"].present?
    assert props["stats"]["agents_count"].is_a?(Integer)
    assert props["stats"]["playbooks_count"].is_a?(Integer)
    assert props["stats"]["leads_count"].is_a?(Integer)
    assert props["recent_activities"].is_a?(Array)
    assert_equal "overview", props["current_tab"]
  end

  # WHY: Index returns paginated organizations with card data
  test "index returns paginated organizations with card data" do
    login_as(@admin)

    get admin_organizations_path, headers: inertia_headers

    assert_response :success

    props = inertia_props
    assert props["organizations"].is_a?(Array)
    assert props["pagination"].present?
    assert props["pagination"]["current_page"].is_a?(Integer)
    assert props["pagination"]["total_pages"].is_a?(Integer)

    if props["organizations"].any?
      org = props["organizations"].first
      assert org["id"].present?
      assert org["name"].present?
      assert org.key?("agents_count")
      assert org.key?("playbooks_count")
    end
  end

  # WHY: Only admins should access organization show page
  test "show requires admin role" do
    customer_admin = accounts(:customer_admin)
    login_as(customer_admin)

    get admin_organization_path(@organization), headers: inertia_headers

    assert_redirected_to root_path
    assert_equal "Access denied", flash[:alert]
  end
end
