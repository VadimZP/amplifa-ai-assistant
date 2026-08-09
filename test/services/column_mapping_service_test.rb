# frozen_string_literal: true

require "test_helper"

class ColumnMappingServiceTest < ActiveSupport::TestCase
  # === Basic Mapping Tests ===

  # WHY: Verify service returns proper structure with all required keys
  test "returns hash with suggested_mappings, unmapped_columns, and unmapped_fields" do
    headers = %w[Email Name]
    result = ColumnMappingService.new(headers).call

    assert_kind_of Hash, result
    assert result.key?(:suggested_mappings)
    assert result.key?(:unmapped_columns)
    assert result.key?(:unmapped_fields)
  end

  # WHY: Common headers should map correctly without any processing
  test "maps standard headers exactly" do
    headers = %w[email first_name last_name company job_title]
    result = ColumnMappingService.new(headers).call

    assert_equal "email", result[:suggested_mappings]["email"]
    assert_equal "first_name", result[:suggested_mappings]["first_name"]
    assert_equal "last_name", result[:suggested_mappings]["last_name"]
    assert_equal "company", result[:suggested_mappings]["company"]
    assert_equal "job_title", result[:suggested_mappings]["job_title"]
    assert_empty result[:unmapped_columns]
  end

  # === Fuzzy Matching Tests ===

  # WHY: CSV exports often use varied formats like "E-Mail" or "Email Address"
  test "matches email variations" do
    variations = ["Email", "E-Mail", "email address", "Work Email", "Business Email"]

    variations.each do |header|
      result = ColumnMappingService.new([header]).call
      assert_equal "email", result[:suggested_mappings][header],
                   "Failed to map '#{header}' to email"
    end
  end

  # WHY: First name has many common variations across different systems
  test "matches first name variations" do
    variations = ["First Name", "FirstName", "first_name", "Given Name", "Vorname"]

    variations.each do |header|
      result = ColumnMappingService.new([header]).call
      assert_equal "first_name", result[:suggested_mappings][header],
                   "Failed to map '#{header}' to first_name"
    end
  end

  # WHY: Last name exports differ between CRMs and regions
  test "matches last name variations" do
    variations = ["Last Name", "LastName", "Surname", "Family Name", "Nachname"]

    variations.each do |header|
      result = ColumnMappingService.new([header]).call
      assert_equal "last_name", result[:suggested_mappings][header],
                   "Failed to map '#{header}' to last_name"
    end
  end

  # WHY: Company names come in various forms from different data sources
  test "matches company variations" do
    variations = ["Company", "Company Name", "Organization", "Employer", "Firma"]

    variations.each do |header|
      result = ColumnMappingService.new([header]).call
      assert_equal "company", result[:suggested_mappings][header],
                   "Failed to map '#{header}' to company"
    end
  end

  # WHY: Job title field names vary significantly across exports
  test "matches job title variations" do
    variations = ["Job Title", "Title", "Position", "Role", "Designation"]

    variations.each do |header|
      result = ColumnMappingService.new([header]).call
      assert_equal "job_title", result[:suggested_mappings][header],
                   "Failed to map '#{header}' to job_title"
    end
  end

  # WHY: LinkedIn field often has URL or Profile suffix
  test "matches linkedin url variations" do
    variations = ["LinkedIn", "LinkedIn URL", "LinkedIn Profile", "Profile URL"]

    variations.each do |header|
      result = ColumnMappingService.new([header]).call
      assert_equal "linkedin_url", result[:suggested_mappings][header],
                   "Failed to map '#{header}' to linkedin_url"
    end
  end

  # WHY: Website URLs have multiple naming conventions
  test "matches company website variations" do
    variations = ["Website", "Company Website", "Website URL", "URL", "Homepage"]

    variations.each do |header|
      result = ColumnMappingService.new([header]).call
      assert_equal "company_website", result[:suggested_mappings][header],
                   "Failed to map '#{header}' to company_website"
    end
  end

  # WHY: Location data comes in different granularities
  test "matches location variations" do
    variations = ["Location", "City", "Address", "Country", "Region"]

    variations.each do |header|
      result = ColumnMappingService.new([header]).call
      assert_equal "location", result[:suggested_mappings][header],
                   "Failed to map '#{header}' to location"
    end
  end

  # === Case Sensitivity Tests ===

  # WHY: Headers should match regardless of case
  test "matches headers case-insensitively" do
    headers = ["EMAIL", "FIRST NAME", "last name", "CoMpAnY"]
    result = ColumnMappingService.new(headers).call

    assert_equal "email", result[:suggested_mappings]["EMAIL"]
    assert_equal "first_name", result[:suggested_mappings]["FIRST NAME"]
    assert_equal "last_name", result[:suggested_mappings]["last name"]
    assert_equal "company", result[:suggested_mappings]["CoMpAnY"]
  end

  # === Unmapped Columns Tests ===

  # WHY: Unknown columns should be reported for manual mapping or custom fields
  test "returns unmapped columns for unknown headers" do
    headers = ["Email", "Industry", "Revenue", "Custom Field 1"]
    result = ColumnMappingService.new(headers).call

    assert_equal "email", result[:suggested_mappings]["Email"]
    assert_includes result[:unmapped_columns], "Industry"
    assert_includes result[:unmapped_columns], "Revenue"
    assert_includes result[:unmapped_columns], "Custom Field 1"
  end

  # WHY: Users need to know which fields are still available for mapping
  test "returns unmapped fields that were not matched" do
    headers = ["Email", "First Name"]
    result = ColumnMappingService.new(headers).call

    assert_includes result[:unmapped_fields], "last_name"
    assert_includes result[:unmapped_fields], "company"
    assert_includes result[:unmapped_fields], "job_title"
    assert_not_includes result[:unmapped_fields], "email"
    assert_not_includes result[:unmapped_fields], "first_name"
  end

  # === Edge Cases ===

  # WHY: Empty or nil headers should be handled gracefully
  test "handles empty and nil headers" do
    headers = ["Email", "", nil, "Company"]
    result = ColumnMappingService.new(headers).call

    assert_equal 2, result[:suggested_mappings].size
    assert_equal "email", result[:suggested_mappings]["Email"]
    assert_equal "company", result[:suggested_mappings]["Company"]
  end

  # WHY: Service should not crash with nil input
  test "handles nil csv_headers array" do
    result = ColumnMappingService.new(nil).call

    assert_empty result[:suggested_mappings]
    assert_empty result[:unmapped_columns]
    assert_equal ColumnMappingService::MAPPABLE_FIELDS, result[:unmapped_fields]
  end

  # WHY: Empty array should return empty mappings
  test "handles empty csv_headers array" do
    result = ColumnMappingService.new([]).call

    assert_empty result[:suggested_mappings]
    assert_empty result[:unmapped_columns]
    assert_equal ColumnMappingService::MAPPABLE_FIELDS, result[:unmapped_fields]
  end

  # WHY: Each field should only be mapped once to prevent data loss
  test "does not map same field twice" do
    headers = ["Email", "Work Email", "Business Email"]
    result = ColumnMappingService.new(headers).call

    # Only first email header should be mapped
    email_mappings = result[:suggested_mappings].select { |_, v| v == "email" }
    assert_equal 1, email_mappings.size
    assert_equal "email", result[:suggested_mappings]["Email"]

    # Other email columns become unmapped
    assert_includes result[:unmapped_columns], "Work Email"
    assert_includes result[:unmapped_columns], "Business Email"
  end

  # WHY: Headers with extra whitespace should still match
  test "handles headers with extra whitespace" do
    headers = ["  Email  ", " First Name ", "  Company  "]
    result = ColumnMappingService.new(headers).call

    assert_equal "email", result[:suggested_mappings]["  Email  "]
    assert_equal "first_name", result[:suggested_mappings][" First Name "]
    assert_equal "company", result[:suggested_mappings]["  Company  "]
  end

  # === Custom Field Helper Tests ===

  # WHY: Unmapped columns need valid JSONB keys for custom_fields storage
  test "custom_field_key converts header to valid key" do
    assert_equal "industry", ColumnMappingService.custom_field_key("Industry")
    assert_equal "employee_count", ColumnMappingService.custom_field_key("Employee Count")
    assert_equal "annual_revenue", ColumnMappingService.custom_field_key("Annual Revenue")
    assert_equal "custom_field_1", ColumnMappingService.custom_field_key("Custom Field 1")
  end

  # WHY: Special characters should be removed for valid JSONB keys
  test "custom_field_key removes special characters" do
    assert_equal "revenue", ColumnMappingService.custom_field_key("Revenue ($)")
    assert_equal "notes", ColumnMappingService.custom_field_key("Notes!!!")
    assert_equal "data_test", ColumnMappingService.custom_field_key("Data [test]")
    assert_equal "percentage", ColumnMappingService.custom_field_key("% Percentage")
  end

  # WHY: Edge cases for custom field key generation
  test "custom_field_key handles edge cases" do
    assert_nil ColumnMappingService.custom_field_key(nil)
    assert_nil ColumnMappingService.custom_field_key("")
    assert_equal "field", ColumnMappingService.custom_field_key("  Field  ")
  end

  # === Integration-like Tests ===

  # WHY: Verify realistic CSV headers from common exports are handled well
  test "handles realistic LinkedIn export headers" do
    headers = [
      "Email Address",
      "First Name",
      "Last Name",
      "Position",
      "Company Name",
      "Location",
      "Profile URL",
      "Connected On"
    ]
    result = ColumnMappingService.new(headers).call

    assert_equal "email", result[:suggested_mappings]["Email Address"]
    assert_equal "first_name", result[:suggested_mappings]["First Name"]
    assert_equal "last_name", result[:suggested_mappings]["Last Name"]
    assert_equal "job_title", result[:suggested_mappings]["Position"]
    assert_equal "company", result[:suggested_mappings]["Company Name"]
    assert_equal "location", result[:suggested_mappings]["Location"]
    assert_equal "linkedin_url", result[:suggested_mappings]["Profile URL"]
    assert_includes result[:unmapped_columns], "Connected On"
  end

  # WHY: Verify HubSpot-style headers are handled
  test "handles realistic HubSpot export headers" do
    headers = [
      "Email",
      "First name",
      "Last name",
      "Job title",
      "Company name",
      "Website URL",
      "City",
      "Industry",
      "Number of Employees"
    ]
    result = ColumnMappingService.new(headers).call

    assert_equal "email", result[:suggested_mappings]["Email"]
    assert_equal "first_name", result[:suggested_mappings]["First name"]
    assert_equal "last_name", result[:suggested_mappings]["Last name"]
    assert_equal "job_title", result[:suggested_mappings]["Job title"]
    assert_equal "company", result[:suggested_mappings]["Company name"]
    assert_equal "company_website", result[:suggested_mappings]["Website URL"]
    assert_equal "location", result[:suggested_mappings]["City"]
    assert_includes result[:unmapped_columns], "Industry"
    assert_includes result[:unmapped_columns], "Number of Employees"
  end
end
