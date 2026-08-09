# frozen_string_literal: true

# LeadImportAnalyzerService analyzes a CSV before import to determine which rows
# will create new Person records, new Lead records, or update existing Leads.
#
# Status values:
# - "new_person": Email doesn't exist in Person table (will create both Person and Lead)
# - "new_lead": Person exists but Lead doesn't exist in this organization
# - "update_lead": Both Person and Lead exist in this organization
class LeadImportAnalyzerService
  attr_reader :csv_content, :email_column, :organization_id

  def initialize(csv_content:, email_column:, organization_id:)
    @csv_content = csv_content
    @email_column = email_column
    @organization_id = organization_id
  end

  def call
    return empty_result if rows.empty?

    {
      summary: build_summary,
      rows: analyze_rows
    }
  end

  private

  def rows
    @rows ||= CSV.parse(CsvEncodingNormalizer.normalize(csv_content), headers: true, liberal_parsing: true).map(&:to_h)
  end

  def emails
    @emails ||= rows.map { |row| normalize_email(row[email_column]) }.compact.uniq
  end

  def existing_people_emails
    @existing_people_emails ||= Person
      .where("lower(email) IN (?)", emails)
      .pluck(:email)
      .map(&:downcase)
      .to_set
  end

  def existing_lead_emails
    @existing_lead_emails ||= Lead
      .where(organization_id: organization_id)
      .where("lower(email) IN (?)", emails)
      .pluck(:email)
      .map(&:downcase)
      .to_set
  end

  def analyze_rows
    rows.map.with_index do |row, index|
      email = normalize_email(row[email_column])
      status = determine_status(email)

      {
        row_number: index + 1,
        email: email,
        status: status,
        data: row
      }
    end
  end

  def determine_status(email)
    return "invalid" if email.blank?

    person_exists = existing_people_emails.include?(email)
    lead_exists = existing_lead_emails.include?(email)

    if lead_exists
      "update_lead"
    elsif person_exists
      "new_lead"
    else
      "new_person"
    end
  end

  def build_summary
    statuses = rows.map { |row| determine_status(normalize_email(row[email_column])) }

    {
      total_rows: rows.count,
      new_person_count: statuses.count("new_person"),
      new_lead_count: statuses.count("new_lead"),
      update_lead_count: statuses.count("update_lead"),
      invalid_count: statuses.count("invalid")
    }
  end

  def normalize_email(email)
    email&.strip&.downcase.presence
  end

  def empty_result
    {
      summary: {
        total_rows: 0,
        new_person_count: 0,
        new_lead_count: 0,
        update_lead_count: 0,
        invalid_count: 0
      },
      rows: []
    }
  end
end
