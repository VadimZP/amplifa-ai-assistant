# frozen_string_literal: true

require "test_helper"

class LeadImportTest < ActiveSupport::TestCase
  # Tests cover basic validation (WHY: ensure import records have required fields)
  test "requires organization" do
    import = LeadImport.new(imported_by: accounts(:customer_admin), original_filename: "test.csv", column_mapping: { "Email" => "email" })
    assert_not import.valid?
    assert_includes import.errors[:organization], "can't be blank"
  end

  test "requires imported_by" do
    import = LeadImport.new(organization: organizations(:acme), original_filename: "test.csv", column_mapping: { "Email" => "email" })
    assert_not import.valid?
    assert_includes import.errors[:imported_by], "can't be blank"
  end

  test "requires original_filename" do
    import = LeadImport.new(organization: organizations(:acme), imported_by: accounts(:customer_admin), column_mapping: { "Email" => "email" })
    assert_not import.valid?
    assert_includes import.errors[:original_filename], "can't be blank"
  end

  test "valid with all required fields" do
    import = LeadImport.new(
      organization: organizations(:acme),
      imported_by: accounts(:customer_admin),
      original_filename: "leads.csv",
      column_mapping: { "Email" => "email" }
    )
    assert import.valid?
  end

  # Tests cover status validation (WHY: ensure valid status values)
  test "validates status inclusion" do
    import = LeadImport.new(
      organization: organizations(:acme),
      imported_by: accounts(:customer_admin),
      original_filename: "test.csv",
      column_mapping: { "Email" => "email" },
      status: "invalid_status"
    )
    assert_not import.valid?
    assert_includes import.errors[:status], "is not included in the list"
  end

  test "allows valid statuses" do
    %w[pending processing completed failed].each do |status|
      import = LeadImport.new(
        organization: organizations(:acme),
        imported_by: accounts(:customer_admin),
        original_filename: "test.csv",
        column_mapping: { "Email" => "email" },
        status: status
      )
      assert import.valid?, "Expected status '#{status}' to be valid"
    end
  end

  # Tests cover column_mapping validation (WHY: email mapping is required for import)
  test "requires email in column_mapping" do
    import = LeadImport.new(
      organization: organizations(:acme),
      imported_by: accounts(:customer_admin),
      original_filename: "test.csv",
      column_mapping: { "Name" => "first_name" }
    )
    assert_not import.valid?
    assert_includes import.errors[:column_mapping], "must map a column to email"
  end

  test "accepts column_mapping with email" do
    import = LeadImport.new(
      organization: organizations(:acme),
      imported_by: accounts(:customer_admin),
      original_filename: "test.csv",
      column_mapping: { "Email Address" => "email" }
    )
    assert import.valid?
  end

  # Tests cover status predicate methods (WHY: convenient status checking)
  test "pending? returns true for pending status" do
    assert lead_imports(:pending_import).pending?
    assert_not lead_imports(:completed_import).pending?
  end

  test "processing? returns true for processing status" do
    assert lead_imports(:processing_import).processing?
    assert_not lead_imports(:pending_import).processing?
  end

  test "completed? returns true for completed status" do
    assert lead_imports(:completed_import).completed?
    assert_not lead_imports(:pending_import).completed?
  end

  test "failed? returns true for failed status" do
    assert lead_imports(:failed_import).failed?
    assert_not lead_imports(:completed_import).failed?
  end

  # Tests cover progress_percentage (WHY: track import progress for UI display)
  test "progress_percentage returns 0 when total_rows is zero" do
    import = LeadImport.new(total_rows: 0, processed_rows: 0)
    assert_equal 0, import.progress_percentage
  end

  test "progress_percentage calculates correctly" do
    import = LeadImport.new(total_rows: 100, processed_rows: 50)
    assert_equal 50, import.progress_percentage
  end

  test "progress_percentage rounds to nearest integer" do
    import = LeadImport.new(total_rows: 3, processed_rows: 1)
    assert_equal 33, import.progress_percentage
  end

  test "progress_percentage returns 100 when complete" do
    import = lead_imports(:completed_import)
    assert_equal 100, import.progress_percentage
  end

  # Tests cover duration_seconds (WHY: track import performance)
  test "duration_seconds returns nil when not started" do
    import = lead_imports(:pending_import)
    assert_nil import.duration_seconds
  end

  test "duration_seconds returns nil when not completed" do
    import = lead_imports(:processing_import)
    assert_nil import.duration_seconds
  end

  test "duration_seconds calculates time difference" do
    import = lead_imports(:completed_import)
    assert import.duration_seconds > 0
  end

  # Tests cover add_error (WHY: track individual row errors during import)
  test "add_error appends error to errors_detail" do
    # WHY: Test verifies error tracking works for import diagnostics
    import = LeadImport.new(errors_detail: [])
    import.add_error(row: 5, message: "Invalid email")

    assert_equal 1, import.errors_detail.length
    # JSONB serializes keys as strings
    assert_equal 5, import.errors_detail.first["row"]
    assert_equal "Invalid email", import.errors_detail.first["error"]
  end

  test "add_error caps at MAX_ERRORS" do
    import = LeadImport.new(errors_detail: (1..100).map { |i| { row: i, error: "Error" } })
    import.add_error(row: 101, message: "Should not be added")

    assert_equal 100, import.errors_detail.length
    assert_not import.errors_detail.any? { |e| e[:row] == 101 }
  end

  # Tests cover scopes (WHY: efficient filtering for admin views)
  test "for_organization scope filters by org" do
    results = LeadImport.for_organization(organizations(:acme))
    assert_includes results, lead_imports(:pending_import)
    assert_not_includes results, lead_imports(:failed_import)
  end

  test "pending scope returns only pending imports" do
    results = LeadImport.pending
    assert_includes results, lead_imports(:pending_import)
    assert_not_includes results, lead_imports(:completed_import)
  end

  test "completed scope returns only completed imports" do
    results = LeadImport.completed
    assert_includes results, lead_imports(:completed_import)
    assert_not_includes results, lead_imports(:pending_import)
  end

  # Tests cover associations (WHY: verify model relationships)
  test "belongs to organization" do
    assert_equal organizations(:acme), lead_imports(:pending_import).organization
  end

  test "belongs to imported_by (Account)" do
    assert_equal accounts(:customer_admin), lead_imports(:pending_import).imported_by
  end

  test "belongs to agent optionally" do
    assert_nil lead_imports(:pending_import).agent
    assert_equal agents(:draft_agent), lead_imports(:processing_import).agent
  end

  test "has many leads" do
    import = lead_imports(:completed_import)
    assert import.leads.count >= 1
  end
end
