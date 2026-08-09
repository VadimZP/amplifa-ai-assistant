# frozen_string_literal: true

require "test_helper"
require "csv"

class LeadImportAnalyzerServiceTest < ActiveSupport::TestCase
  setup do
    @organization = organizations(:acme)
  end

  def create_csv_content(rows)
    CSV.generate(headers: true) do |csv|
      csv << rows.first.keys
      rows.each { |row| csv << row.values }
    end
  end

  test "identifies new_person status for emails not in database" do
    rows = [
      { "Email" => "brandnew@example.com", "Name" => "Brand New" }
    ]

    result = LeadImportAnalyzerService.new(
      csv_content: create_csv_content(rows),
      email_column: "Email",
      organization_id: @organization.id
    ).call

    assert_equal 1, result[:summary][:total_rows]
    assert_equal 1, result[:summary][:new_person_count]
    assert_equal 0, result[:summary][:new_lead_count]
    assert_equal 0, result[:summary][:update_lead_count]
    assert_equal "new_person", result[:rows].first[:status]
  end

  test "identifies new_lead status for existing person without lead in org" do
    Person.create!(email: "existingperson@example.com", first_name: "Existing")

    rows = [
      { "Email" => "existingperson@example.com", "Name" => "Existing Person" }
    ]

    result = LeadImportAnalyzerService.new(
      csv_content: create_csv_content(rows),
      email_column: "Email",
      organization_id: @organization.id
    ).call

    assert_equal 1, result[:summary][:new_lead_count]
    assert_equal 0, result[:summary][:new_person_count]
    assert_equal 0, result[:summary][:update_lead_count]
    assert_equal "new_lead", result[:rows].first[:status]
  end

  test "identifies update_lead status for existing lead in org" do
    person = Person.create!(email: "existinglead@example.com", first_name: "Existing")
    Lead.create!(
      email: "existinglead@example.com",
      organization: @organization,
      person: person
    )

    rows = [
      { "Email" => "existinglead@example.com", "Name" => "Existing Lead" }
    ]

    result = LeadImportAnalyzerService.new(
      csv_content: create_csv_content(rows),
      email_column: "Email",
      organization_id: @organization.id
    ).call

    assert_equal 1, result[:summary][:update_lead_count]
    assert_equal 0, result[:summary][:new_person_count]
    assert_equal 0, result[:summary][:new_lead_count]
    assert_equal "update_lead", result[:rows].first[:status]
  end

  test "identifies invalid status for rows with missing email" do
    rows = [
      { "Email" => "", "Name" => "No Email" },
      { "Email" => "valid@example.com", "Name" => "Valid" }
    ]

    result = LeadImportAnalyzerService.new(
      csv_content: create_csv_content(rows),
      email_column: "Email",
      organization_id: @organization.id
    ).call

    assert_equal 1, result[:summary][:invalid_count]
    assert_equal 1, result[:summary][:new_person_count]
    assert_equal "invalid", result[:rows].first[:status]
    assert_equal "new_person", result[:rows].second[:status]
  end

  test "handles mixed statuses correctly" do
    Person.create!(email: "person@example.com", first_name: "Person Only")
    person_with_lead = Person.create!(email: "lead@example.com", first_name: "Has Lead")
    Lead.create!(
      email: "lead@example.com",
      organization: @organization,
      person: person_with_lead
    )

    rows = [
      { "Email" => "brandnew@example.com", "Name" => "New Person" },
      { "Email" => "person@example.com", "Name" => "Person Only" },
      { "Email" => "lead@example.com", "Name" => "Has Lead" },
      { "Email" => "", "Name" => "Invalid" }
    ]

    result = LeadImportAnalyzerService.new(
      csv_content: create_csv_content(rows),
      email_column: "Email",
      organization_id: @organization.id
    ).call

    assert_equal 4, result[:summary][:total_rows]
    assert_equal 1, result[:summary][:new_person_count]
    assert_equal 1, result[:summary][:new_lead_count]
    assert_equal 1, result[:summary][:update_lead_count]
    assert_equal 1, result[:summary][:invalid_count]
  end

  test "normalizes email addresses for comparison" do
    Person.create!(email: "uppercase@example.com", first_name: "Upper")

    rows = [
      { "Email" => "  UPPERCASE@EXAMPLE.COM  ", "Name" => "With Spaces" }
    ]

    result = LeadImportAnalyzerService.new(
      csv_content: create_csv_content(rows),
      email_column: "Email",
      organization_id: @organization.id
    ).call

    assert_equal "new_lead", result[:rows].first[:status]
  end

  test "returns empty result for empty CSV" do
    result = LeadImportAnalyzerService.new(
      csv_content: "Email,Name\n",
      email_column: "Email",
      organization_id: @organization.id
    ).call

    assert_equal 0, result[:summary][:total_rows]
    assert_empty result[:rows]
  end

  test "only considers leads in the specified organization" do
    other_org = organizations(:beta)
    person = Person.create!(email: "crossorg@example.com", first_name: "Cross Org")
    Lead.create!(
      email: "crossorg@example.com",
      organization: other_org,
      person: person
    )

    rows = [
      { "Email" => "crossorg@example.com", "Name" => "Cross Org Lead" }
    ]

    result = LeadImportAnalyzerService.new(
      csv_content: create_csv_content(rows),
      email_column: "Email",
      organization_id: @organization.id
    ).call

    assert_equal "new_lead", result[:rows].first[:status]
  end

  test "includes row data in response" do
    rows = [
      { "Email" => "test@example.com", "Name" => "Test User", "Company" => "Test Corp" }
    ]

    result = LeadImportAnalyzerService.new(
      csv_content: create_csv_content(rows),
      email_column: "Email",
      organization_id: @organization.id
    ).call

    row_data = result[:rows].first[:data]
    assert_equal "test@example.com", row_data["Email"]
    assert_equal "Test User", row_data["Name"]
    assert_equal "Test Corp", row_data["Company"]
  end

  test "preserves German umlauts from Windows-1252 CSV content" do
    csv_content = "Email,Name,Company\nandy@example.de,Andy Fäger,ENgesser - Fürstenau\n"

    result = LeadImportAnalyzerService.new(
      csv_content: csv_content.encode(Encoding::Windows_1252),
      email_column: "Email",
      organization_id: @organization.id
    ).call

    row_data = result[:rows].first[:data]
    assert_equal "Andy Fäger", row_data["Name"]
    assert_equal "ENgesser - Fürstenau", row_data["Company"]
  end

  test "preserves German umlauts from binary UTF-8 CSV content" do
    csv_content = "Email,Name,Company\nferdinand@example.de,J. Ferdinand Fürstenau,Reflex Aerospace\n"

    result = LeadImportAnalyzerService.new(
      csv_content: csv_content.b,
      email_column: "Email",
      organization_id: @organization.id
    ).call

    row_data = result[:rows].first[:data]
    assert_equal "J. Ferdinand Fürstenau", row_data["Name"]
    assert_equal "Reflex Aerospace", row_data["Company"]
  end
end
