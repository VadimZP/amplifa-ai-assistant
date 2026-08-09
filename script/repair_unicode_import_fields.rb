#!/usr/bin/env ruby
# frozen_string_literal: true

require 'csv'
require 'optparse'

options = {
  apply: false,
  details_limit: 50,
  import_ids: [],
  organization_id: nil,
  repair_company_records: true
}

parser = OptionParser.new do |opts|
  opts.banner = <<~BANNER
    Usage: ruby script/repair_unicode_import_fields.rb --organization-id ID [options]

    Repairs previously stripped Unicode characters from CSV-backed lead imports.
    Dry-run is the default. Apply mode only updates exact stripped-Unicode matches.
  BANNER

  opts.on('--organization-id ID', Integer, 'Required organization ID scope') do |organization_id|
    options[:organization_id] = organization_id
  end

  opts.on('--import-id ID', Integer, 'Optional LeadImport ID scope; repeatable') do |import_id|
    options[:import_ids] << import_id
  end

  opts.on('--apply', 'Apply the repair plan; default is dry-run') do
    options[:apply] = true
  end

  opts.on('--details-limit LIMIT', Integer, 'Number of sample changes to include (default: 50)') do |limit|
    options[:details_limit] = limit
  end

  opts.on('--skip-company-records', 'Do not repair canonical Company.name records') do
    options[:repair_company_records] = false
  end

  opts.on('-h', '--help', 'Show this help') do
    puts opts
    exit 0
  end
end

parser.parse!

if options[:organization_id].nil?
  warn parser
  abort 'Missing required --organization-id'
end

require_relative '../config/environment'

# Builds and optionally applies exact-match repairs for CSV import Unicode loss.
class UnicodeImportFieldRepair
  REPAIR_FIELDS = %w[
    first_name
    last_name
    full_name
    job_title
    company
    company_website
    linkedin_url
    location
  ].freeze

  TARGET_CLASSES = {
    'Lead' => Lead,
    'Person' => Person,
    'Company' => Company
  }.freeze

  def initialize(organization_id:, import_ids:, apply:, details_limit:, repair_company_records:)
    @organization = Organization.find(organization_id)
    @import_ids = import_ids
    @apply = apply
    @details_limit = details_limit
    @repair_company_records = repair_company_records
    @field_candidates = {}
    @company_candidates = {}
    @company_by_domain = {}
    @import_summaries = []
  end

  def call
    scan_imports

    field_plan = build_plan(@field_candidates)
    company_plan = build_plan(@company_candidates)
    apply_result = apply_plan(field_plan[:eligible] + company_plan[:eligible]) if @apply

    {
      marker: 'UNICODE_IMPORT_FIELD_REPAIR',
      mode: @apply ? 'apply' : 'dry_run',
      organization: { id: @organization.id, name: @organization.name },
      scoped_import_ids: @import_ids,
      repair_company_records: @repair_company_records,
      imports: @import_summaries,
      lead_person_updates: summarize_plan(field_plan),
      company_name_updates: summarize_plan(company_plan),
      apply: apply_result || { applied: 0, stale_skipped: 0, errors: [] }
    }
  end

  private

  def scan_imports
    imports_scope.each do |lead_import|
      summary = new_import_summary(lead_import)

      unless lead_import.csv_file.attached?
        summary[:error] = 'CSV file is not attached'
        @import_summaries << summary
        next
      end

      scan_import(lead_import, summary)
      @import_summaries << summary
    rescue StandardError => e
      summary[:error] = "#{e.class}: #{e.message}"
      @import_summaries << summary
    end
  end

  def imports_scope
    scope = LeadImport.where(organization: @organization, source: 'csv')
    scope = scope.where(id: @import_ids) if @import_ids.any?
    scope.order(:id)
  end

  def new_import_summary(lead_import)
    {
      id: lead_import.id,
      filename: lead_import.original_filename,
      rows: 0,
      candidate_fields: 0,
      candidate_company_names: 0,
      conflicts: 0,
      attached: lead_import.csv_file.attached?
    }
  end

  def scan_import(lead_import, summary)
    rows = CSV.parse(
      CsvEncodingNormalizer.normalize(lead_import.csv_file.blob.download),
      headers: true,
      liberal_parsing: true
    )
    summary[:rows] = rows.length

    columns_by_field = columns_by_field(lead_import)
    email_columns = columns_by_field['email']
    if email_columns.blank?
      summary[:error] = 'Missing email mapping'
      return
    end

    leads_by_email = leads_by_email(rows, email_columns)

    rows.each_with_index do |row, index|
      email = row_value(row, email_columns)&.downcase
      lead = leads_by_email[email]
      next unless lead

      scan_row(lead_import, row, index + 2, columns_by_field, lead, summary)
    end
  end

  def columns_by_field(lead_import)
    lead_import.column_mapping.each_with_object({}) do |(column, field), result|
      normalized_field = field.to_s.strip
      result[normalized_field] ||= []
      result[normalized_field] << column
    end
  end

  def leads_by_email(rows, email_columns)
    emails = rows.filter_map { |row| row_value(row, email_columns)&.downcase }.uniq
    Lead.where(organization: @organization, email: emails)
        .includes(person: :current_company)
        .index_by { |lead| lead.email.downcase }
  end

  def scan_row(lead_import, row, row_number, columns_by_field, lead, summary)
    REPAIR_FIELDS.each do |field|
      source = row_value(row, columns_by_field[field])
      next unless unicode_stripped_candidate?(source)

      summary[:candidate_fields] += record_field_candidates(
        lead_import: lead_import,
        row_number: row_number,
        email: lead.email,
        lead: lead,
        field: field,
        source: source
      )
    end

    return unless @repair_company_records

    company_source = row_value(row, columns_by_field['company'])
    company_website = row_value(row, columns_by_field['company_website'])
    summary[:candidate_company_names] += record_company_candidate(
      lead_import: lead_import,
      row_number: row_number,
      email: lead.email,
      lead: lead,
      company_source: company_source,
      company_website: company_website
    )
  end

  def row_value(row, columns)
    Array(columns).each do |column|
      value = row[column].to_s.strip
      return value if value.present?
    end

    nil
  end

  def unicode_stripped_candidate?(source)
    source.present? && source.match?(/[^\x00-\x7F]/) && strip_unicode(source) != source
  end

  def strip_unicode(value)
    value.to_s.gsub(/[^\x00-\x7F]/, '')
  end

  def record_field_candidates(lead_import:, row_number:, email:, lead:, field:, source:)
    count = 0
    stripped = strip_unicode(source)

    if lead.respond_to?(field) && lead.public_send(field).to_s == stripped
      add_candidate(
        @field_candidates,
        model: 'Lead',
        id: lead.id,
        field: field,
        source: source,
        current: stripped,
        lead_import: lead_import,
        row_number: row_number,
        email: email
      )
      count += 1
    end

    person = lead.person
    if person.present? && person.respond_to?(field) && person.public_send(field).to_s == stripped
      add_candidate(
        @field_candidates,
        model: 'Person',
        id: person.id,
        field: field,
        source: source,
        current: stripped,
        lead_import: lead_import,
        row_number: row_number,
        email: email
      )
      count += 1
    end

    count
  end

  def record_company_candidate(lead_import:, row_number:, email:, lead:, company_source:, company_website:)
    return 0 unless unicode_stripped_candidate?(company_source)

    stripped = strip_unicode(company_source)
    domain = Company.normalize_domain(company_website || lead.company_website || lead.person&.company_website)
    return 0 if domain.blank?

    company = company_for_domain(domain)
    return 0 unless company&.normalized_domain == domain
    return 0 unless company.name.to_s == stripped

    add_candidate(
      @company_candidates,
      model: 'Company',
      id: company.id,
      field: 'name',
      source: company_source,
      current: stripped,
      lead_import: lead_import,
      row_number: row_number,
      email: email
    )
    1
  end

  def company_for_domain(domain)
    @company_by_domain.fetch(domain) do
      @company_by_domain[domain] = Company.find_by(normalized_domain: domain)
    end
  end

  def add_candidate(store, model:, id:, field:, source:, current:, lead_import:, row_number:, email:)
    key = [model, id, field]
    entry = store[key] ||= {
      model: model,
      id: id,
      field: field,
      current: current,
      sources: [],
      samples: []
    }
    entry[:sources] << source unless entry[:sources].include?(source)
    return unless entry[:samples].length < @details_limit

    entry[:samples] << sample_hash(lead_import, row_number, email, current, source)
  end

  def sample_hash(lead_import, row_number, email, current, source)
    {
      import_id: lead_import.id,
      row: row_number,
      email: email,
      current: current,
      source: source
    }
  end

  def build_plan(candidates)
    candidates.values.each_with_object({ eligible: [], conflicts: [] }) do |entry, result|
      if entry[:sources].one?
        result[:eligible] << entry.merge(source: entry[:sources].first)
      else
        result[:conflicts] << entry.merge(sources: entry[:sources].to_a)
      end
    end
  end

  def summarize_plan(plan)
    {
      eligible_targets: plan[:eligible].length,
      conflict_targets: plan[:conflicts].length,
      eligible_samples: plan[:eligible].first(@details_limit).map { |entry| public_entry(entry) },
      conflict_samples: plan[:conflicts].first(@details_limit).map { |entry| public_entry(entry) }
    }
  end

  def public_entry(entry)
    {
      model: entry[:model],
      id: entry[:id],
      field: entry[:field],
      source: entry[:source],
      sources: entry[:sources]&.to_a,
      samples: entry[:samples]
    }.compact
  end

  def apply_plan(entries)
    result = { applied: 0, stale_skipped: 0, errors: [] }

    entries.each do |entry|
      record = TARGET_CLASSES.fetch(entry[:model]).find(entry[:id])
      current = record.public_send(entry[:field]).to_s

      if current != strip_unicode(entry[:source]) || current == entry[:source]
        result[:stale_skipped] += 1
        next
      end

      record.update_columns(entry[:field] => entry[:source])
      result[:applied] += 1
    rescue StandardError => e
      result[:errors] << {
        model: entry[:model],
        id: entry[:id],
        field: entry[:field],
        error: "#{e.class}: #{e.message}"
      }
    end

    result
  end
end

result = UnicodeImportFieldRepair.new(**options).call
puts JSON.pretty_generate(result)
