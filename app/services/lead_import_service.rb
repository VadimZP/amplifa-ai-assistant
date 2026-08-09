# frozen_string_literal: true

require 'csv'
require 'set'

class LeadImportService
  CHUNK_SIZE = 500
  ENCODING_SAMPLE_SIZE = 64.kilobytes
  HTML_INDICATORS = %w[<!doctype <html <head <body <meta <?xml].freeze
  LINKEDIN_URL_PATTERN = %r{\Ahttps?://(www\.)?linkedin\.com/}i
  DOMAIN_ONLY_PATTERN = /\A[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+\z/i
  PERSON_IMPORT_COLUMNS = %i[
    email first_name last_name full_name job_title company company_website location linkedin_url
    current_company_id timezone timezone_source timezone_resolved_at created_at updated_at
  ].freeze
  PERSON_UPDATE_COLUMNS = (PERSON_IMPORT_COLUMNS - %i[email created_at]).freeze
  LEAD_IMPORT_COLUMNS = %i[
    organization_id email first_name last_name full_name job_title company company_website location linkedin_url
    custom_fields lead_import_id person_id blacklisted blacklist_reason blacklist_reason_category blacklisted_at
    created_at updated_at
  ].freeze
  LEAD_UPDATE_COLUMNS = (LEAD_IMPORT_COLUMNS - %i[organization_id email created_at]).freeze

  class ImportError < StandardError; end
  class InvalidFileError < ImportError; end
  class EncodingError < ImportError; end

  # Presents uploaded files to CSV as a line-oriented UTF-8 stream.
  class StreamingCsvIO
    def initialize(io, source_encoding)
      @io = io
      @source_encoding = source_encoding
      @strip_bom = true
    end

    def gets(*args)
      line = @io.gets(*args)
      return unless line

      line = encode_line(line)
      return line unless @strip_bom

      @strip_bom = false
      line.delete_prefix(CsvEncodingNormalizer::UTF_8_BOM.dup.force_encoding(Encoding::UTF_8))
    end

    def rewind
      @strip_bom = true
      @io.rewind
    end

    private

    def encode_line(line)
      line = line.to_s.b.force_encoding(@source_encoding)
      return line if @source_encoding == Encoding::UTF_8 && line.valid_encoding?

      line.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: '')
    end
  end

  attr_reader :lead_import, :results, :last_error

  def initialize(lead_import)
    @lead_import = lead_import
    @last_error = nil
    @results = {
      created_count: 0,
      updated_count: 0,
      skipped_count: 0,
      blacklisted_count: 0,
      error_count: 0
    }
  end

  def call
    validation_error = validate_import
    if validation_error
      @last_error = validation_error
      finalize_failure(validation_error)
      return false
    end

    begin
      start_processing
      process_csv
      finalize_success
      true
    rescue InvalidFileError, EncodingError => e
      @last_error = e.message
      finalize_failure(e.message)
      false
    rescue CSV::MalformedCSVError => e
      @last_error = "Invalid CSV format: #{e.message}"
      finalize_failure(@last_error)
      false
    rescue StandardError => e
      @last_error = e.message
      finalize_failure(e.message)
      false
    end
  end

  private

  def validate_import
    return 'CSV file is not attached' unless lead_import.csv_file.attached?

    validate_file_content
  end

  def validate_file_content
    lead_import.csv_file.open do |file|
      sample = file.read(1024)
      return 'File is empty' if sample.nil? || sample.empty?

      html_error = detect_html_content(sample)
      return html_error if html_error

      file.rewind
      validate_csv_structure(file)
    end
  rescue StandardError => e
    "Failed to validate file: #{e.message}"
  end

  def detect_html_content(sample)
    sample_lower = CsvEncodingNormalizer.normalize(sample).downcase
    HTML_INDICATORS.each do |indicator|
      if sample_lower.include?(indicator)
        return 'File appears to be HTML, not CSV. This often happens when downloading a CSV ' \
               'from a website with an expired session - please re-download the file and try again.'
      end
    end
    nil
  end

  def validate_csv_structure(file)
    csv = build_csv(file)
    first_row = csv.first

    return 'CSV file has no data rows (only headers or empty)' if first_row.nil?

    headers = csv.headers
    return 'CSV file has no valid headers' if headers.nil? || headers.empty? || headers.all?(&:nil?)

    nil
  rescue CSV::MalformedCSVError => e
    "CSV parsing failed: #{e.message}"
  rescue ArgumentError => e
    if e.message.include?('invalid byte sequence')
      'File has encoding issues - please save the CSV as UTF-8 and try again'
    else
      "CSV validation failed: #{e.message}"
    end
  end

  def start_processing
    lead_import.update!(
      status: 'processing',
      started_at: Time.current
    )
  end

  def process_csv
    processed_rows = 0

    lead_import.csv_file.open do |file|
      total_rows = count_csv_rows(file)
      csv = build_csv(file)
      lead_import.update!(total_rows: total_rows, processed_rows: 0)

      csv.each_slice(CHUNK_SIZE) do |chunk|
        process_chunk(chunk, processed_rows)
        processed_rows += chunk.size
        update_progress(processed_rows, total_rows: total_rows)
      end
    end

    lead_import.update!(total_rows: processed_rows)
  end

  def count_csv_rows(file)
    build_csv(file).count
  ensure
    file.rewind if file.respond_to?(:rewind)
  end

  def process_chunk(chunk, processed_rows)
    prepared_rows = prepare_chunk_rows(chunk, processed_rows)
    prepared_rows = reject_invalid_prepared_rows(prepared_rows)
    return if prepared_rows.empty?

    if duplicate_emails?(prepared_rows)
      process_chunk_row_by_row(prepared_rows)
      return
    end

    bulk_process_prepared_rows(prepared_rows)
  rescue ActiveRecord::ActiveRecordError
    process_chunk_row_by_row(prepared_rows)
  end

  def process_chunk_row_by_row(prepared_rows)
    emails = prepared_rows.map { |row| row[:email] }.uniq
    leads_by_email = preload_leads(emails)
    people_by_email = preload_people(emails)
    agent_lead_rows = []

    prepared_rows.each do |prepared_row|
      process_prepared_row(prepared_row, leads_by_email, people_by_email, agent_lead_rows)
    end

    create_agent_leads(agent_lead_rows)
  end

  def bulk_process_prepared_rows(prepared_rows)
    Lead.transaction do
      emails = prepared_rows.map { |row| row[:email] }
      leads_by_email = preload_leads(emails)
      people_by_email = preload_people(emails)
      existing_lead_emails = leads_by_email.keys.to_set

      upsert_people(prepared_rows, leads_by_email, people_by_email)
      people_by_email = preload_people(emails)

      upsert_leads(prepared_rows, leads_by_email, people_by_email)
      leads_by_email = preload_leads(emails)

      create_agent_leads(prepared_rows.filter_map { |row| agent_lead_row_for(leads_by_email[row[:email]]) })
      update_bulk_counts(prepared_rows, existing_lead_emails)
    end
  end

  def reject_invalid_prepared_rows(prepared_rows)
    prepared_rows.filter do |prepared_row|
      valid_prepared_row?(prepared_row)
    end
  end

  def valid_prepared_row?(prepared_row)
    attributes = prepared_row[:attributes]
    linkedin_url = attributes[:linkedin_url]
    company_website = attributes[:company_website]

    if linkedin_url.present? && !linkedin_url.match?(LINKEDIN_URL_PATTERN)
      add_error(prepared_row[:row_number], 'Validation failed: Linkedin url must be a LinkedIn URL')
      return false
    end

    if company_website.present? && !valid_company_website?(company_website)
      add_error(prepared_row[:row_number], 'Validation failed: Company website must be a valid URL or domain')
      return false
    end

    true
  end

  def valid_company_website?(value)
    url = value.to_s.strip
    return true if url.blank?

    if url.match?(%r{\Ahttps?://}i)
      uri = URI.parse(url)
      uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
    else
      url.match?(DOMAIN_ONLY_PATTERN)
    end
  rescue URI::InvalidURIError
    false
  end

  def duplicate_emails?(prepared_rows)
    emails = Set.new
    prepared_rows.any? { |row| !emails.add?(row[:email]) }
  end

  def upsert_people(prepared_rows, leads_by_email, people_by_email)
    rows = prepared_rows.map do |prepared_row|
      person_row_attributes(prepared_row, leads_by_email, people_by_email)
    end

    Person.upsert_all(
      rows,
      unique_by: :index_people_on_email_unique,
      update_only: PERSON_UPDATE_COLUMNS,
      returning: false,
      record_timestamps: false
    )
  end

  def person_row_attributes(prepared_row, leads_by_email, people_by_email)
    email = prepared_row[:email]
    attributes = prepared_row[:attributes]
    existing_person = leads_by_email[email]&.person || people_by_email[email]
    row = base_person_attributes(email, existing_person)

    person_import_fields.each do |field|
      value = attributes[field]
      row[field] = value if value.present?
    end

    apply_person_company_attributes(row, attributes)
    apply_person_timezone_attributes(row, attributes, existing_person)
    row.slice(*PERSON_IMPORT_COLUMNS)
  end

  def base_person_attributes(email, existing_person)
    now = Time.current
    if existing_person
      existing_person.attributes.symbolize_keys.slice(*PERSON_IMPORT_COLUMNS).merge(updated_at: now)
    else
      PERSON_IMPORT_COLUMNS.index_with(nil).merge(email: email, created_at: now, updated_at: now)
    end
  end

  def person_import_fields
    %i[first_name last_name full_name job_title company company_website location linkedin_url]
  end

  def apply_person_company_attributes(row, attributes)
    company = Company.find_or_create_from_identity(
      name: row[:company],
      website_url: row[:company_website]
    )
    row[:current_company_id] = company&.id if company
  rescue ActiveRecord::RecordNotUnique
    normalized_domain = Company.normalize_domain(attributes[:company_website])
    row[:current_company_id] = Company.find_by(normalized_domain: normalized_domain)&.id if normalized_domain.present?
  end

  def apply_person_timezone_attributes(row, attributes, existing_person)
    return unless attributes[:location].present?
    return if existing_person && existing_person.location == attributes[:location]

    resolved = LocationTimezoneResolver.resolve(attributes[:location])
    return if resolved.blank?

    row[:timezone] = resolved
    row[:timezone_source] = 'location'
    row[:timezone_resolved_at] = Time.current
  end

  def upsert_leads(prepared_rows, leads_by_email, people_by_email)
    rows = prepared_rows.map do |prepared_row|
      lead_row_attributes(prepared_row, leads_by_email, people_by_email)
    end

    Lead.upsert_all(
      rows,
      unique_by: :idx_leads_org_email_unique,
      update_only: LEAD_UPDATE_COLUMNS,
      returning: false,
      record_timestamps: false
    )
  end

  def lead_row_attributes(prepared_row, leads_by_email, people_by_email)
    email = prepared_row[:email]
    existing_lead = leads_by_email[email]
    attributes = prepared_row[:attributes]
    row = base_lead_attributes(email, existing_lead)

    lead_import_fields.each do |field|
      value = attributes[field]
      row[field] = value if value.present?
    end

    row[:custom_fields] = attributes[:custom_fields] if attributes[:custom_fields].present?
    row[:person_id] = existing_lead&.person_id || people_by_email.fetch(email).id
    apply_lead_blacklist_attributes(row, attributes, prepared_row[:count_as_blacklisted], existing_lead)
    row.slice(*LEAD_IMPORT_COLUMNS)
  end

  def base_lead_attributes(email, existing_lead)
    now = Time.current
    if existing_lead
      existing_lead.attributes.symbolize_keys.slice(*LEAD_IMPORT_COLUMNS).merge(updated_at: now)
    else
      LEAD_IMPORT_COLUMNS.index_with(nil).merge(
        organization_id: lead_import.organization_id,
        email: email,
        lead_import_id: lead_import.id,
        custom_fields: {},
        blacklisted: false,
        created_at: now,
        updated_at: now
      )
    end
  end

  def lead_import_fields
    %i[first_name last_name full_name job_title company company_website location linkedin_url]
  end

  def apply_lead_blacklist_attributes(row, attributes, count_as_blacklisted, existing_lead)
    return unless count_as_blacklisted

    row[:blacklisted] = true
    row[:blacklist_reason] = attributes[:blacklist_reason]
    row[:blacklist_reason_category] = attributes[:blacklist_reason_category]
    row[:blacklisted_at] = attributes[:blacklisted_at] || existing_lead&.blacklisted_at || Time.current
  end

  def agent_lead_row_for(lead)
    return unless lead_import.agent.present?
    return unless lead&.organization_id == lead_import.agent.organization_id

    {
      agent_id: lead_import.agent_id,
      lead_id: lead.id,
      created_at: Time.current,
      updated_at: Time.current
    }
  end

  def update_bulk_counts(prepared_rows, existing_lead_emails)
    prepared_rows.each do |prepared_row|
      if prepared_row[:count_as_blacklisted]
        @results[:blacklisted_count] += 1
      elsif existing_lead_emails.include?(prepared_row[:email])
        @results[:updated_count] += 1
      else
        @results[:created_count] += 1
      end
    end
  end

  def prepare_chunk_rows(chunk, processed_rows)
    chunk.filter_map.with_index do |row, index|
      prepare_row(row, processed_rows + index + 1)
    end
  end

  def prepare_row(row, row_number)
    email = extract_email(row)

    if email.blank?
      add_error(row_number, 'Missing email address')
      @results[:skipped_count] += 1
      return nil
    end

    unless valid_email?(email)
      add_error(row_number, "Invalid email format: #{email}")
      @results[:skipped_count] += 1
      return nil
    end

    attributes = apply_mapping(row)
    blacklist_entry = matching_blacklist_entry(email, attributes[:company_website])
    apply_blacklist_attributes(attributes, blacklist_entry) if blacklist_entry

    {
      email: email,
      row_number: row_number,
      attributes: attributes,
      count_as_blacklisted: blacklist_entry.present?
    }
  end

  def extract_email(row)
    email_column = column_mapping.find { |_csv_col, lead_field| lead_field == 'email' }&.first
    return nil unless email_column

    sanitize_string(row[email_column])&.strip&.downcase
  end

  def sanitize_string(value)
    return nil if value.nil?

    CsvEncodingNormalizer.normalize(value)
  end

  def build_csv(file)
    file.rewind if file.respond_to?(:rewind)
    source_encoding = detect_csv_encoding(file)
    csv = CSV.new(StreamingCsvIO.new(file, source_encoding), headers: true, liberal_parsing: true)
    file.rewind if file.respond_to?(:rewind)
    csv
  end

  def detect_csv_encoding(file)
    sample = file.read(ENCODING_SAMPLE_SIZE)
    normalized_sample = CsvEncodingNormalizer.normalize(sample)

    if utf8_sample?(sample, normalized_sample)
      Encoding::UTF_8
    else
      Encoding::Windows_1252
    end
  ensure
    file.rewind if file.respond_to?(:rewind)
  end

  def utf8_sample?(sample, normalized_sample)
    sample.to_s.b.delete_prefix(CsvEncodingNormalizer::UTF_8_BOM).force_encoding(Encoding::UTF_8).valid_encoding? &&
      normalized_sample.encoding == Encoding::UTF_8
  end

  def valid_email?(email)
    email.match?(URI::MailTo::EMAIL_REGEXP)
  end

  def matching_blacklist_entry(email, company_website)
    normalized_email = email.to_s.strip.downcase
    domains = [normalized_email.split('@').last, Lead.normalize_domain(company_website)].compact.map(&:downcase).uniq

    email_entry = blacklist_index[:exact_emails][normalized_email]
    domain_entry = domains.filter_map { |domain| blacklist_index[:exact_domains][domain] }.min_by { |entry| blacklist_entry_priority(entry) }
    wildcard_entry = blacklist_index[:wildcard_domains].find do |entry|
      domains.any? { |domain| blacklist_domain_matches?(domain, entry.value) }
    end

    [email_entry, domain_entry, wildcard_entry].compact.min_by { |entry| blacklist_entry_priority(entry) }
  end

  def blacklist_entries
    @blacklist_entries ||= Blacklist
                           .where('organization_id IS NULL OR organization_id = ?', lead_import.organization_id)
                           .to_a
                           .sort_by { |entry| blacklist_entry_priority(entry) }
  end

  def blacklist_index
    @blacklist_index ||= begin
      exact_emails = {}
      exact_domains = {}
      wildcard_domains = []

      blacklist_entries.each do |entry|
        value = entry.value.to_s.downcase
        if entry.value_type == 'email'
          exact_emails[value] ||= entry
        elsif value.include?('*')
          wildcard_domains << entry
        else
          exact_domains[value] ||= entry
        end
      end

      { exact_emails: exact_emails, exact_domains: exact_domains, wildcard_domains: wildcard_domains }
    end
  end

  def blacklist_domain_matches?(domain, pattern)
    return false if domain.blank? || pattern.blank?

    pattern = pattern.to_s.downcase
    domain = domain.to_s.downcase

    if pattern.include?('*')
      File.fnmatch?(pattern, domain, File::FNM_CASEFOLD)
    else
      pattern == domain
    end
  end

  def blacklist_entry_priority(entry)
    [
      entry.organization_id.nil? ? 1 : 0,
      entry.value_type == 'email' ? 0 : 1,
      entry.value.to_s.include?('*') ? 1 : 0,
      entry.id
    ]
  end

  def apply_blacklist_attributes(attributes, blacklist_entry)
    attributes[:blacklisted] = true
    attributes[:blacklist_reason] = blacklist_entry.effective_reason
    attributes[:blacklist_reason_category] = blacklist_entry.reason_category.presence ||
                                             Blacklist::REASON_CATEGORIES[:other]
    attributes[:blacklisted_at] = Time.current
  end

  def preload_leads(emails)
    Lead
      .where(organization: lead_import.organization, email: emails)
      .index_by(&:email)
  end

  def preload_people(emails)
    return {} if emails.empty?

    Person
      .where('lower(email) IN (?)', emails)
      .index_by { |person| person.email.downcase }
  end

  def process_prepared_row(prepared_row, leads_by_email, people_by_email, agent_lead_rows)
    email = prepared_row[:email]
    lead = leads_by_email[email]

    if lead
      update_existing_lead(lead, email, prepared_row[:attributes], prepared_row[:count_as_blacklisted], people_by_email)
    else
      lead = create_new_lead_with_person(
        email,
        prepared_row[:attributes],
        prepared_row[:count_as_blacklisted],
        people_by_email
      )
      leads_by_email[email] = lead
    end

    stage_agent_lead(lead, agent_lead_rows)
  rescue ActiveRecord::RecordInvalid => e
    add_error(prepared_row[:row_number], e.message)
  end

  def update_existing_lead(lead, email, attributes, count_as_blacklisted, people_by_email = nil)
    person = find_or_create_person(email, attributes, people_by_email)
    lead.person ||= person

    lead.update!(attributes.merge(person: lead.person))

    update_person_attributes(lead.person, attributes)

    if count_as_blacklisted
      @results[:blacklisted_count] += 1
    else
      @results[:updated_count] += 1
    end

    lead
  end

  def create_new_lead_with_person(email, attributes, count_as_blacklisted, people_by_email = nil)
    person = find_or_create_person(email, attributes, people_by_email)

    update_person_attributes(person, attributes)

    lead = Lead.create!(
      attributes.merge(
        organization: lead_import.organization,
        lead_import: lead_import,
        email: email,
        person: person
      )
    )

    if count_as_blacklisted
      @results[:blacklisted_count] += 1
    else
      @results[:created_count] += 1
    end

    lead
  end

  def find_or_create_person(email, attributes, people_by_email = nil)
    normalized_email = email.strip.downcase
    person = people_by_email&.fetch(normalized_email, nil)
    return person if person

    person = Person.create!(person_creation_attributes(normalized_email, attributes))
    people_by_email[normalized_email] = person if people_by_email
    person
  rescue ActiveRecord::RecordNotUnique
    person = Person.where('lower(email) = ?', normalized_email).first!
    people_by_email[normalized_email] = person if people_by_email
    person
  end

  def person_creation_attributes(email, attributes)
    {
      email: email,
      first_name: attributes[:first_name],
      last_name: attributes[:last_name],
      full_name: attributes[:full_name],
      job_title: attributes[:job_title],
      company: attributes[:company],
      company_website: attributes[:company_website],
      location: attributes[:location],
      linkedin_url: attributes[:linkedin_url]
    }
  end

  def stage_agent_lead(lead, agent_lead_rows)
    return unless lead_import.agent.present?
    return unless lead.organization_id == lead_import.agent.organization_id

    agent_lead_rows << {
      agent_id: lead_import.agent_id,
      lead_id: lead.id,
      created_at: Time.current,
      updated_at: Time.current
    }
  end

  def create_agent_leads(agent_lead_rows)
    return if agent_lead_rows.empty?

    unique_rows = agent_lead_rows.uniq { |row| [row[:agent_id], row[:lead_id]] }
    AgentLead.insert_all(unique_rows, unique_by: :idx_agent_leads_unique)
  end

  def update_person_attributes(person, attributes)
    person_updates = {}

    %i[first_name last_name full_name job_title company company_website location
       linkedin_url].each do |field|
      if attributes[field].present? && (person.send(field).blank? || person.send(field) != attributes[field])
        person_updates[field] = attributes[field]
      end
    end

    person.update!(person_updates) if person_updates.present?
  end

  def apply_mapping(row)
    attributes = {}
    custom_fields = {}

    column_mapping.each do |csv_column, lead_field|
      normalized_field = lead_field.to_s.strip
      next if normalized_field.blank?

      value = sanitize_string(row[csv_column])&.strip
      next if value.blank?

      if normalized_field.start_with?('custom_fields.')
        field_name = normalized_field.delete_prefix('custom_fields.')
        next if field_name.blank?

        custom_fields[field_name] = value
      elsif normalized_field != 'email'
        attributes[normalized_field.to_sym] = value
      end
    end

    attributes[:custom_fields] = custom_fields if custom_fields.present?
    attributes
  end

  def column_mapping
    @column_mapping ||= lead_import.column_mapping
  end

  def update_progress(processed_rows, total_rows: lead_import.total_rows)
    lead_import.update!(
      total_rows: total_rows,
      processed_rows: processed_rows,
      created_count: @results[:created_count],
      updated_count: @results[:updated_count],
      skipped_count: @results[:skipped_count],
      blacklisted_count: @results[:blacklisted_count],
      error_count: @results[:error_count]
    )
  end

  def add_error(row_number, message)
    lead_import.add_error(row: row_number, message: message)
    @results[:error_count] += 1
  end

  def finalize_success
    lead_import.update!(
      status: 'completed',
      completed_at: Time.current,
      processed_rows: lead_import.total_rows,
      created_count: @results[:created_count],
      updated_count: @results[:updated_count],
      skipped_count: @results[:skipped_count],
      blacklisted_count: @results[:blacklisted_count],
      error_count: @results[:error_count]
    )

    update_agent_lead_count

    log_admin_activity('lead_import_completed', {
                         lead_import_id: lead_import.id,
                         filename: lead_import.original_filename,
                         created_count: @results[:created_count],
                         updated_count: @results[:updated_count],
                         blacklisted_count: @results[:blacklisted_count],
                         error_count: @results[:error_count]
                       })
  end

  def finalize_failure(error_message)
    lead_import.update!(
      status: 'failed',
      completed_at: Time.current,
      created_count: @results[:created_count],
      updated_count: @results[:updated_count],
      skipped_count: @results[:skipped_count],
      blacklisted_count: @results[:blacklisted_count],
      error_count: @results[:error_count]
    )
    lead_import.add_error(row: 0, message: "Import failed: #{error_message}")

    update_agent_lead_count

    log_admin_activity('lead_import_failed', {
                         lead_import_id: lead_import.id,
                         filename: lead_import.original_filename,
                         error: error_message,
                         partial_created: @results[:created_count],
                         partial_updated: @results[:updated_count]
                       })
  end

  def update_agent_lead_count
    return unless lead_import.agent.present?

    lead_import.agent.update!(total_leads_count: lead_import.agent.leads.count)
  end

  def log_admin_activity(action, details)
    AdminActivity.create!(
      account_id: lead_import.imported_by_id,
      organization_id: lead_import.organization_id,
      action: action,
      details: details
    )
  end
end
