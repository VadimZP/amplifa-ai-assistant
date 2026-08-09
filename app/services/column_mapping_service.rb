# frozen_string_literal: true

# ColumnMappingService suggests column mappings between CSV headers and Lead model fields.
# Uses fuzzy matching to handle common header variations like "E-Mail", "Work Email", etc.
class ColumnMappingService
  # Lead model fields that can be mapped to
  MAPPABLE_FIELDS = %w[
    email
    first_name
    last_name
    full_name
    job_title
    company
    company_website
    linkedin_url
    location
  ].freeze

  # Common header variations mapped to their canonical Lead field
  # Keys are downcased and stripped for matching
  HEADER_VARIATIONS = {
    # Email variations
    'email' => 'email',
    'e-mail' => 'email',
    'email address' => 'email',
    'email_address' => 'email',
    'emailaddress' => 'email',
    'work email' => 'email',
    'work_email' => 'email',
    'workemail' => 'email',
    'business email' => 'email',
    'primary email' => 'email',
    'contact email' => 'email',
    'mail' => 'email',

    # First name variations
    'first name' => 'first_name',
    'first_name' => 'first_name',
    'firstname' => 'first_name',
    'first' => 'first_name',
    'given name' => 'first_name',
    'given_name' => 'first_name',
    'givenname' => 'first_name',
    'forename' => 'first_name',
    'vorname' => 'first_name',

    # Last name variations
    'last name' => 'last_name',
    'last_name' => 'last_name',
    'lastname' => 'last_name',
    'last' => 'last_name',
    'surname' => 'last_name',
    'family name' => 'last_name',
    'family_name' => 'last_name',
    'familyname' => 'last_name',
    'nachname' => 'last_name',

    # Full name variations
    'full name' => 'full_name',
    'full_name' => 'full_name',
    'fullname' => 'full_name',
    'name' => 'full_name',
    'contact name' => 'full_name',
    'contact' => 'full_name',

    # Job title variations
    'job title' => 'job_title',
    'job_title' => 'job_title',
    'jobtitle' => 'job_title',
    'title' => 'job_title',
    'position' => 'job_title',
    'role' => 'job_title',
    'designation' => 'job_title',
    'job' => 'job_title',

    # Company variations
    'company' => 'company',
    'company name' => 'company',
    'company_name' => 'company',
    'companyname' => 'company',
    'organization' => 'company',
    'organisation' => 'company',
    'org' => 'company',
    'employer' => 'company',
    'firm' => 'company',
    'business' => 'company',
    'firma' => 'company',
    'unternehmen' => 'company',
    'company table data' => 'company',

    # Company domain variations (redirected to company_website)
    'company domain' => 'company_website',
    'company_domain' => 'company_website',
    'companydomain' => 'company_website',
    'domain' => 'company_website',
    'website domain' => 'company_website',

    # Company website variations
    'company website' => 'company_website',
    'company_website' => 'company_website',
    'companywebsite' => 'company_website',
    'website' => 'company_website',
    'website url' => 'company_website',
    'website_url' => 'company_website',
    'websiteurl' => 'company_website',
    'url' => 'company_website',
    'company url' => 'company_website',
    'web' => 'company_website',
    'homepage' => 'company_website',

    # LinkedIn variations
    'linkedin' => 'linkedin_url',
    'linkedin url' => 'linkedin_url',
    'linkedin_url' => 'linkedin_url',
    'linkedinurl' => 'linkedin_url',
    'linkedin profile' => 'linkedin_url',
    'linkedin_profile' => 'linkedin_url',
    'linkedinprofile' => 'linkedin_url',
    'profile url' => 'linkedin_url',
    'profile_url' => 'linkedin_url',

    # Location variations
    'location' => 'location',
    'city' => 'location',
    'address' => 'location',
    'region' => 'location',
    'country' => 'location',
    'state' => 'location',
    'area' => 'location',
    'standort' => 'location',
    'ort' => 'location'
  }.freeze

  attr_reader :csv_headers

  def initialize(csv_headers)
    @csv_headers = csv_headers || []
  end

  # Returns a hash with suggested mappings and unmapped columns
  # @return [Hash] { suggested_mappings: {}, unmapped_columns: [], unmapped_fields: [] }
  def call
    suggested_mappings = {}
    unmapped_columns = []
    mapped_fields = []

    csv_headers.each do |header|
      next if header.blank?

      field = find_matching_field(header)

      if field && !mapped_fields.include?(field)
        suggested_mappings[header] = field
        mapped_fields << field
      else
        unmapped_columns << header
      end
    end

    {
      suggested_mappings: suggested_mappings,
      unmapped_columns: unmapped_columns,
      unmapped_fields: MAPPABLE_FIELDS - mapped_fields
    }
  end

  # Suggests a custom_field name for an unmapped column
  # Converts header to snake_case for use as JSONB key
  def self.custom_field_key(header)
    return nil if header.blank?

    key = header.strip.downcase
    key = key.gsub(/\s+/, '_')           # Replace spaces with underscores
    key = key.gsub(/[^a-z0-9_]/, '')     # Remove special characters
    key = key.gsub(/_+/, '_')            # Collapse multiple underscores
    key = key.gsub(/^_|_$/, '')          # Remove leading/trailing underscores
    key.presence
  end

  private

  def find_matching_field(header)
    normalized = normalize_header(header)

    # First try exact match
    return HEADER_VARIATIONS[normalized] if HEADER_VARIATIONS.key?(normalized)

    # Try partial matching for compound headers
    HEADER_VARIATIONS.each do |variation, field|
      return field if normalized.include?(variation) || variation.include?(normalized)
    end

    nil
  end

  def normalize_header(header)
    header.to_s.strip.downcase.gsub(/[_-]/, ' ').gsub(/\s+/, ' ')
  end
end
