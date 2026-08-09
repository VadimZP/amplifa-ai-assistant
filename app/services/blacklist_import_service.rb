# frozen_string_literal: true

# BlacklistImportService handles bulk import of blacklist entries from CSV or text input.
# Automatically detects value type (email vs domain) based on @ presence.
# Skips duplicates and tracks created count.
class BlacklistImportService
  attr_reader :organization, :created_by, :source, :results

  def initialize(organization:, created_by:, source: "import")
    @organization = organization
    @created_by = created_by
    @source = source
    @results = {
      created_count: 0,
      skipped_count: 0,
      invalid_count: 0,
      errors: []
    }
  end

  # Imports entries from text input (one value per line)
  # @param input [String] Text with one email or domain per line
  # @return [Hash] Results with created_count, skipped_count, invalid_count, errors
  def call(input)
    return results if input.blank?

    lines = input.split(/[\r\n]+/).map(&:strip).reject(&:blank?)

    lines.each_with_index do |line, index|
      process_line(line, index + 1)
    end

    results
  end

  private

  def process_line(value, line_number)
    normalized_value = normalize_value(value)

    if normalized_value.blank?
      @results[:skipped_count] += 1
      return
    end

    value_type = detect_value_type(normalized_value)

    if value_type == "invalid"
      @results[:invalid_count] += 1
      @results[:errors] << { line: line_number, value: value, error: "Invalid format" }
      return
    end

    if already_exists?(normalized_value, value_type)
      @results[:skipped_count] += 1
      return
    end

    create_entry(normalized_value, value_type, line_number)
  end

  def normalize_value(value)
    value.strip.downcase.gsub(/\s+/, "")
  end

  def detect_value_type(value)
    if value.include?("@")
      # It's an email
      value.match?(URI::MailTo::EMAIL_REGEXP) ? "email" : "invalid"
    else
      # It's a domain - validate format
      value.match?(/\A[a-z0-9][a-z0-9\-]*(\.[a-z0-9][a-z0-9\-]*)+\z/i) ? "domain" : "invalid"
    end
  end

  def already_exists?(value, value_type)
    scope = Blacklist.where(value: value, value_type: value_type)

    if organization
      scope.where(organization_id: organization.id).exists?
    else
      scope.where(organization_id: nil).exists?
    end
  end

  def create_entry(value, value_type, line_number)
    Blacklist.create!(
      organization: organization,
      created_by: created_by,
      value: value,
      value_type: value_type,
      source: source
    )
    @results[:created_count] += 1
  rescue ActiveRecord::RecordInvalid => e
    @results[:invalid_count] += 1
    @results[:errors] << { line: line_number, value: value, error: e.message }
  end
end
