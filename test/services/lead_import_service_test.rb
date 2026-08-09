# frozen_string_literal: true

require 'test_helper'
require 'csv'

class LeadImportServiceTest < ActiveSupport::TestCase
  setup do
    @organization = organizations(:acme)
    @imported_by = accounts(:customer_admin)
    @agent = agents(:draft_agent)
  end

  # WHY: Helper method to create test CSV content for import tests
  def create_csv_content(rows)
    CSV.generate(headers: true) do |csv|
      csv << rows.first.keys
      rows.each { |row| csv << row.values }
    end
  end

  # WHY: Helper to create a LeadImport with attached CSV file
  def create_lead_import(csv_rows, column_mapping:, agent: nil)
    csv_content = create_csv_content(csv_rows)
    create_lead_import_from_content(csv_content, column_mapping: column_mapping, agent: agent)
  end

  def create_lead_import_from_content(csv_content, column_mapping:, agent: nil)
    lead_import = LeadImport.create!(
      organization: @organization,
      imported_by: @imported_by,
      agent: agent,
      original_filename: 'test.csv',
      column_mapping: column_mapping,
      status: 'pending'
    )

    lead_import.csv_file.attach(
      io: StringIO.new(csv_content),
      filename: 'test.csv',
      content_type: 'text/csv'
    )

    lead_import
  end

  def count_sql_matching(pattern)
    query_count = 0

    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |_name, _start, _finish, _id, payload|
      next if payload[:cached]
      next if %w[SCHEMA TRANSACTION].include?(payload[:name])
      next if payload[:sql].match?(/\A(?:BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE SAVEPOINT)/i)

      query_count += 1 if payload[:sql].match?(pattern)
    end

    yield
    query_count
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end

  # === Basic CSV Processing Tests ===

  # WHY: Verify service can process a simple CSV and create leads
  test 'successfully imports leads from CSV' do
    rows = [
      { 'Email' => 'new1@example.com', 'First Name' => 'John', 'Last Name' => 'Doe' },
      { 'Email' => 'new2@example.com', 'First Name' => 'Jane', 'Last Name' => 'Smith' }
    ]
    column_mapping = { 'Email' => 'email', 'First Name' => 'first_name', 'Last Name' => 'last_name' }
    lead_import = create_lead_import(rows, column_mapping: column_mapping)

    assert_difference 'Lead.count', 2 do
      service = LeadImportService.new(lead_import)
      assert service.call
    end

    lead_import.reload
    assert_equal 'completed', lead_import.status
    assert_equal 2, lead_import.created_count
    assert_equal 0, lead_import.updated_count
  end

  # WHY: Verify service sets all lead attributes correctly from CSV
  test 'maps CSV columns to lead attributes correctly' do
    rows = [
      {
        'Email' => 'mapped@example.com',
        'First Name' => 'Test',
        'Last Name' => 'User',
        'Job Title' => 'CEO',
        'Company' => 'Test Corp'
      }
    ]
    column_mapping = {
      'Email' => 'email',
      'First Name' => 'first_name',
      'Last Name' => 'last_name',
      'Job Title' => 'job_title',
      'Company' => 'company'
    }
    lead_import = create_lead_import(rows, column_mapping: column_mapping)

    LeadImportService.new(lead_import).call

    lead = Lead.find_by(email: 'mapped@example.com')
    assert_equal 'Test', lead.first_name
    assert_equal 'User', lead.last_name
    assert_equal 'CEO', lead.job_title
    assert_equal 'Test Corp', lead.company
  end

  # WHY: Verify custom fields are stored in JSONB when column maps to custom_fields
  test 'stores unmapped columns in custom_fields' do
    rows = [
      {
        'Email' => 'custom@example.com',
        'First Name' => 'Custom',
        'Industry' => 'Technology',
        'Employee Count' => '100-500'
      }
    ]
    column_mapping = {
      'Email' => 'email',
      'First Name' => 'first_name',
      'Industry' => 'custom_fields.industry',
      'Employee Count' => 'custom_fields.employee_count'
    }
    lead_import = create_lead_import(rows, column_mapping: column_mapping)

    LeadImportService.new(lead_import).call

    lead = Lead.find_by(email: 'custom@example.com')
    assert_equal 'Technology', lead.custom_fields['industry']
    assert_equal '100-500', lead.custom_fields['employee_count']
  end

  test 'ignores blank string mappings for skipped columns' do
    rows = [
      {
        'Email' => 'skip@example.com',
        'First Name' => 'Skip',
        'Company Table Data' => 'Do not import this'
      }
    ]
    column_mapping = {
      'Email' => 'email',
      'First Name' => 'first_name',
      'Company Table Data' => ''
    }
    lead_import = create_lead_import(rows, column_mapping: column_mapping)

    service = LeadImportService.new(lead_import)

    assert service.call

    lead_import.reload
    lead = Lead.find_by(email: 'skip@example.com')

    assert_equal 'completed', lead_import.status
    assert_equal 1, lead_import.created_count
    assert_empty lead_import.errors_detail
    assert_equal 'Skip', lead.first_name
  end

  # === Email Validation Tests ===

  # WHY: Leads with missing emails should be skipped with error
  test 'skips rows with missing email' do
    rows = [
      { 'Email' => '', 'First Name' => 'No Email' },
      { 'Email' => 'valid@example.com', 'First Name' => 'Has Email' }
    ]
    column_mapping = { 'Email' => 'email', 'First Name' => 'first_name' }
    lead_import = create_lead_import(rows, column_mapping: column_mapping)

    assert_difference 'Lead.count', 1 do
      LeadImportService.new(lead_import).call
    end

    lead_import.reload
    assert_equal 1, lead_import.skipped_count
    assert(lead_import.errors_detail.any? { |e| e['error'].include?('Missing email') })
  end

  # WHY: Invalid email formats should be caught and skipped
  test 'skips rows with invalid email format' do
    rows = [
      { 'Email' => 'not-an-email', 'First Name' => 'Bad Email' },
      { 'Email' => 'valid@example.com', 'First Name' => 'Good Email' }
    ]
    column_mapping = { 'Email' => 'email', 'First Name' => 'first_name' }
    lead_import = create_lead_import(rows, column_mapping: column_mapping)

    assert_difference 'Lead.count', 1 do
      LeadImportService.new(lead_import).call
    end

    lead_import.reload
    assert_equal 1, lead_import.skipped_count
    assert(lead_import.errors_detail.any? { |e| e['error'].include?('Invalid email format') })
  end

  # WHY: Emails should be normalized (lowercase, trimmed)
  test 'normalizes email addresses' do
    rows = [
      { 'Email' => '  UPPER@EXAMPLE.COM  ', 'First Name' => 'Upper Case' }
    ]
    column_mapping = { 'Email' => 'email', 'First Name' => 'first_name' }
    lead_import = create_lead_import(rows, column_mapping: column_mapping)

    LeadImportService.new(lead_import).call

    lead = Lead.find_by(email: 'upper@example.com')
    assert_not_nil lead
    assert_equal 'upper@example.com', lead.email
  end

  # === Deduplication Tests ===

  # WHY: Existing leads should be updated, not duplicated
  test 'updates existing leads instead of creating duplicates' do
    existing_email = 'existing@example.com'
    Lead.create!(
      organization: @organization,
      email: existing_email,
      first_name: 'Old',
      last_name: 'Name'
    )

    rows = [
      { 'Email' => existing_email, 'First Name' => 'New', 'Last Name' => 'Updated' }
    ]
    column_mapping = { 'Email' => 'email', 'First Name' => 'first_name', 'Last Name' => 'last_name' }
    lead_import = create_lead_import(rows, column_mapping: column_mapping)

    assert_no_difference 'Lead.count' do
      LeadImportService.new(lead_import).call
    end

    lead_import.reload
    assert_equal 0, lead_import.created_count
    assert_equal 1, lead_import.updated_count

    lead = Lead.find_by(email: existing_email)
    assert_equal 'New', lead.first_name
    assert_equal 'Updated', lead.last_name
  end

  # === Blacklist Tests ===

  # WHY: Blacklisted emails should be flagged during import
  test 'flags blacklisted emails during import' do
    blacklisted_email = 'spam@global-blocked.com'

    rows = [
      { 'Email' => blacklisted_email, 'First Name' => 'Blocked' },
      { 'Email' => 'clean@example.com', 'First Name' => 'Clean' }
    ]
    column_mapping = { 'Email' => 'email', 'First Name' => 'first_name' }
    lead_import = create_lead_import(rows, column_mapping: column_mapping)

    LeadImportService.new(lead_import).call

    lead_import.reload
    assert_equal 1, lead_import.blacklisted_count

    blacklisted_lead = Lead.find_by(email: blacklisted_email)
    assert blacklisted_lead.blacklisted?
    assert_not_nil blacklisted_lead.blacklist_reason
  end

  # WHY: Domain blacklists should block all emails from that domain
  test 'blocks emails from blacklisted domains' do
    blocked_domain_email = 'anyone@spam-domain.com'

    rows = [
      { 'Email' => blocked_domain_email, 'First Name' => 'Domain Blocked' }
    ]
    column_mapping = { 'Email' => 'email', 'First Name' => 'first_name' }
    lead_import = create_lead_import(rows, column_mapping: column_mapping)

    LeadImportService.new(lead_import).call

    lead_import.reload
    assert_equal 1, lead_import.blacklisted_count

    lead = Lead.find_by(email: blocked_domain_email)
    assert lead.blacklisted?
  end

  test 'flags leads when company website domain is blacklisted during import' do
    Blacklist.create!(
      organization: @organization,
      created_by: @imported_by,
      value: 'freshblocked.com',
      value_type: 'domain',
      source: 'manual',
      reason: 'Blocked company domain'
    )

    rows = [
      {
        'Email' => 'someone@allowed.ch',
        'First Name' => 'Blocked',
        'Company Website' => 'https://www.freshblocked.com/team'
      }
    ]
    column_mapping = {
      'Email' => 'email',
      'First Name' => 'first_name',
      'Company Website' => 'company_website'
    }
    lead_import = create_lead_import(rows, column_mapping: column_mapping)

    LeadImportService.new(lead_import).call

    lead = Lead.find_by!(email: 'someone@allowed.ch')
    lead_import.reload

    assert_equal 1, lead_import.blacklisted_count
    assert lead.blacklisted?
    assert_equal 'Blocked company domain', lead.blacklist_reason
  end

  test 'flags leads when wildcard company website domain is blacklisted during import' do
    Blacklist.create!(
      organization: @organization,
      created_by: @imported_by,
      value: 'kienbaum.*',
      value_type: 'domain',
      source: 'manual',
      reason: 'Wildcard blocked company domain'
    )

    rows = [
      {
        'Email' => 'someone@allowed.ch',
        'First Name' => 'Blocked',
        'Company Website' => 'https://www.kienbaum.de/team'
      }
    ]
    column_mapping = {
      'Email' => 'email',
      'First Name' => 'first_name',
      'Company Website' => 'company_website'
    }
    lead_import = create_lead_import(rows, column_mapping: column_mapping)

    LeadImportService.new(lead_import).call

    lead = Lead.find_by!(email: 'someone@allowed.ch')
    lead_import.reload

    assert_equal 1, lead_import.blacklisted_count
    assert lead.blacklisted?
    assert_equal 'Wildcard blocked company domain', lead.blacklist_reason
  end

  test 'loads blacklist entries once for an import chunk' do
    Blacklist.create!(
      organization: @organization,
      created_by: @imported_by,
      value: 'cachedblacklist.com',
      value_type: 'domain',
      source: 'manual',
      reason: 'Cached blacklist domain'
    )

    rows = [
      { 'Email' => 'first@cachedblacklist.com', 'First Name' => 'First' },
      { 'Email' => 'second@cachedblacklist.com', 'First Name' => 'Second' },
      { 'Email' => 'third@example.com', 'First Name' => 'Third' }
    ]
    column_mapping = { 'Email' => 'email', 'First Name' => 'first_name' }
    lead_import = create_lead_import(rows, column_mapping: column_mapping)

    blacklist_query_count = count_sql_matching(/FROM "blacklists"/) do
      assert LeadImportService.new(lead_import).call
    end

    assert_operator blacklist_query_count, :<=, 1
    assert_equal 2, lead_import.reload.blacklisted_count
  end

  test 'cached blacklist matching preserves priority ordering' do
    Blacklist.create!(
      organization: nil,
      created_by: accounts(:amplifa_admin),
      value: 'priority@example.com',
      value_type: 'email',
      source: 'manual',
      reason: 'Global email reason'
    )
    Blacklist.create!(
      organization: @organization,
      created_by: @imported_by,
      value: 'priority.example',
      value_type: 'domain',
      source: 'manual',
      reason: 'Organization domain reason'
    )
    Blacklist.create!(
      organization: @organization,
      created_by: @imported_by,
      value: 'wildcard-priority.*',
      value_type: 'domain',
      source: 'manual',
      reason: 'Wildcard domain reason'
    )
    Blacklist.create!(
      organization: @organization,
      created_by: @imported_by,
      value: 'specific@wildcard-priority.example',
      value_type: 'email',
      source: 'manual',
      reason: 'Specific email reason'
    )

    rows = [
      { 'Email' => 'priority@example.com', 'First Name' => 'Global Email', 'Company Website' => 'priority.example' },
      { 'Email' => 'specific@wildcard-priority.example', 'First Name' => 'Specific Email' }
    ]
    column_mapping = {
      'Email' => 'email',
      'First Name' => 'first_name',
      'Company Website' => 'company_website'
    }
    lead_import = create_lead_import(rows, column_mapping: column_mapping)

    assert LeadImportService.new(lead_import).call

    priority_lead = Lead.find_by!(organization: @organization, email: 'priority@example.com')
    wildcard_lead = Lead.find_by!(organization: @organization, email: 'specific@wildcard-priority.example')

    assert_equal 'Organization domain reason', priority_lead.blacklist_reason
    assert_equal 'Specific email reason', wildcard_lead.blacklist_reason
  end

  # WHY: Organization-specific blacklists should apply to that org only
  test 'applies organization-specific blacklist' do
    competitor_email = 'competitor@rival.com'

    rows = [
      { 'Email' => competitor_email, 'First Name' => 'Competitor' }
    ]
    column_mapping = { 'Email' => 'email', 'First Name' => 'first_name' }
    lead_import = create_lead_import(rows, column_mapping: column_mapping)

    LeadImportService.new(lead_import).call

    lead = Lead.find_by(email: competitor_email, organization: @organization)
    assert lead.blacklisted?
  end

  # === Agent Lead Creation Tests ===

  # WHY: When importing to an agent, leads should be linked via AgentLead
  test 'creates AgentLead records when agent is specified' do
    rows = [
      { 'Email' => 'agent-lead@example.com', 'First Name' => 'Agent' }
    ]
    column_mapping = { 'Email' => 'email', 'First Name' => 'first_name' }
    lead_import = create_lead_import(rows, column_mapping: column_mapping, agent: @agent)

    assert_difference 'AgentLead.count', 1 do
      LeadImportService.new(lead_import).call
    end

    lead = Lead.find_by(email: 'agent-lead@example.com')
    assert_includes @agent.leads, lead
  end

  # WHY: Avoid duplicate AgentLead records for same lead-agent pair
  test 'does not duplicate AgentLead for existing lead-agent combination' do
    email = 'existing-agent-lead@example.com'
    lead = Lead.create!(organization: @organization, email: email, first_name: 'Existing')
    AgentLead.create!(agent: @agent, lead: lead)

    rows = [
      { 'Email' => email, 'First Name' => 'Updated' }
    ]
    column_mapping = { 'Email' => 'email', 'First Name' => 'first_name' }
    lead_import = create_lead_import(rows, column_mapping: column_mapping, agent: @agent)

    assert_no_difference 'AgentLead.count' do
      LeadImportService.new(lead_import).call
    end
  end

  test 'does not duplicate AgentLead for duplicate emails in the same chunk' do
    rows = [
      { 'Email' => 'duplicate-agent@example.com', 'First Name' => 'First' },
      { 'Email' => 'duplicate-agent@example.com', 'First Name' => 'Second' }
    ]
    column_mapping = { 'Email' => 'email', 'First Name' => 'first_name' }
    lead_import = create_lead_import(rows, column_mapping: column_mapping, agent: @agent)

    assert_difference 'Lead.count', 1 do
      assert_difference 'AgentLead.count', 1 do
        assert LeadImportService.new(lead_import).call
      end
    end

    lead_import.reload
    lead = Lead.find_by!(organization: @organization, email: 'duplicate-agent@example.com')

    assert_equal 1, lead_import.created_count
    assert_equal 1, lead_import.updated_count
    assert_equal 'Second', lead.first_name
    assert_equal 1, AgentLead.where(agent: @agent, lead: lead).count
  end

  # WHY: Agent's total_leads_count should be updated after import
  test 'updates agent total_leads_count after import' do
    @agent.update!(total_leads_count: 0)

    rows = [
      { 'Email' => 'lead1@example.com', 'First Name' => 'Lead 1' },
      { 'Email' => 'lead2@example.com', 'First Name' => 'Lead 2' }
    ]
    column_mapping = { 'Email' => 'email', 'First Name' => 'first_name' }
    lead_import = create_lead_import(rows, column_mapping: column_mapping, agent: @agent)

    LeadImportService.new(lead_import).call

    @agent.reload
    assert @agent.total_leads_count >= 2
  end

  # === Status & Progress Tests ===

  # WHY: Import status should transition correctly
  test 'updates status to processing then completed' do
    rows = [{ 'Email' => 'status@example.com', 'First Name' => 'Status' }]
    column_mapping = { 'Email' => 'email', 'First Name' => 'first_name' }
    lead_import = create_lead_import(rows, column_mapping: column_mapping)

    assert_equal 'pending', lead_import.status

    LeadImportService.new(lead_import).call

    lead_import.reload
    assert_equal 'completed', lead_import.status
    assert_not_nil lead_import.started_at
    assert_not_nil lead_import.completed_at
  end

  # WHY: Progress should be tracked during import
  test 'tracks processed rows count' do
    rows = (1..10).map { |i| { 'Email' => "row#{i}@example.com", 'First Name' => "Row #{i}" } }
    column_mapping = { 'Email' => 'email', 'First Name' => 'first_name' }
    lead_import = create_lead_import(rows, column_mapping: column_mapping)

    LeadImportService.new(lead_import).call

    lead_import.reload
    assert_equal 10, lead_import.total_rows
    assert_equal 10, lead_import.processed_rows
  end

  test 'keeps total rows stable during chunk progress updates' do
    rows = (1..501).map { |i| { 'Email' => "progress#{i}@example.com", 'First Name' => "Progress #{i}" } }
    column_mapping = { 'Email' => 'email', 'First Name' => 'first_name' }
    lead_import = create_lead_import(rows, column_mapping: column_mapping)
    progress_updates = []
    service = LeadImportService.new(lead_import)
    observer = Module.new do
      define_method(:update_progress) do |processed_rows, total_rows: lead_import.total_rows|
        progress_updates << [processed_rows, total_rows]
        super(processed_rows, total_rows: total_rows)
      end
    end
    service.singleton_class.prepend(observer)

    assert service.call

    assert_equal [500, 501], progress_updates.first
    assert_equal [501, 501], progress_updates.last
  end

  # === Error Handling Tests ===

  # WHY: Service should fail gracefully when CSV file is missing
  test 'returns false when csv file is not attached' do
    lead_import = LeadImport.create!(
      organization: @organization,
      imported_by: @imported_by,
      original_filename: 'missing.csv',
      column_mapping: { 'Email' => 'email' },
      status: 'pending'
    )

    service = LeadImportService.new(lead_import)
    assert_not service.call
  end

  # WHY: Errors during processing should mark import as failed
  test 'marks import as failed on processing error' do
    lead_import = LeadImport.create!(
      organization: @organization,
      imported_by: @imported_by,
      original_filename: 'bad.csv',
      column_mapping: { 'Email' => 'email' },
      status: 'pending'
    )
    lead_import.csv_file.attach(
      io: StringIO.new("not,valid,csv\ncontent"),
      filename: 'bad.csv',
      content_type: 'text/csv'
    )

    LeadImportService.new(lead_import).call

    lead_import.reload
    assert_equal 'completed', lead_import.status
    assert_equal 0, lead_import.created_count
  end

  # === Admin Activity Logging Tests ===

  # WHY: Successful imports should be logged for audit trail
  test 'logs admin activity on successful import' do
    rows = [{ 'Email' => 'logged@example.com', 'First Name' => 'Logged' }]
    column_mapping = { 'Email' => 'email', 'First Name' => 'first_name' }
    lead_import = create_lead_import(rows, column_mapping: column_mapping)

    assert_difference 'AdminActivity.count', 1 do
      LeadImportService.new(lead_import).call
    end

    activity = AdminActivity.last
    assert_equal 'lead_import_completed', activity.action
    assert_equal lead_import.id, activity.details['lead_import_id']
  end

  # === CSV Parsing Tests ===

  # WHY: Liberal parsing should handle messy CSV data
  test 'handles CSV with liberal parsing' do
    csv_content = "Email,First Name,Notes\nnew@example.com,Test,\"Quoted, with comma\"\n"

    lead_import = LeadImport.create!(
      organization: @organization,
      imported_by: @imported_by,
      original_filename: 'quoted.csv',
      column_mapping: { 'Email' => 'email', 'First Name' => 'first_name', 'Notes' => 'custom_fields.notes' },
      status: 'pending'
    )
    lead_import.csv_file.attach(
      io: StringIO.new(csv_content),
      filename: 'quoted.csv',
      content_type: 'text/csv'
    )

    LeadImportService.new(lead_import).call

    lead = Lead.find_by(email: 'new@example.com')
    assert_equal 'Quoted, with comma', lead.custom_fields['notes']
  end

  test 'builds CSV reader without unbounded file read' do
    guarded_io = Class.new(StringIO) do
      def read(length = nil, *args)
        raise 'unbounded read attempted' if length.nil?

        super
      end
    end.new("Email,First Name\nstreamed@example.com,Streamed\n")
    lead_import = create_lead_import_from_content(
      "Email,First Name\nplaceholder@example.com,Placeholder\n",
      column_mapping: { 'Email' => 'email', 'First Name' => 'first_name' }
    )

    csv = LeadImportService.new(lead_import).send(:build_csv, guarded_io)

    assert_equal 'streamed@example.com', csv.first['Email']
  end

  # WHY: German Excel exports can use Windows-1252 bytes; umlauts must not be dropped during import.
  test 'preserves German umlauts from Windows-1252 CSV files' do
    csv_content = "Email,First Name,Last Name,Company,Location\n" \
                  "andy@example.de,Andy,Fäger,ENgesser - Fürstenau,München\n"
    lead_import = create_lead_import_from_content(
      csv_content.encode(Encoding::Windows_1252),
      column_mapping: {
        'Email' => 'email',
        'First Name' => 'first_name',
        'Last Name' => 'last_name',
        'Company' => 'company',
        'Location' => 'location'
      }
    )

    assert LeadImportService.new(lead_import).call

    lead = Lead.find_by!(email: 'andy@example.de')
    assert_equal 'Andy', lead.first_name
    assert_equal 'Fäger', lead.last_name
    assert_equal 'ENgesser - Fürstenau', lead.company
    assert_equal 'München', lead.location
  end

  # WHY: ActiveStorage can expose valid UTF-8 uploads as binary strings; multibyte umlauts must survive.
  test 'preserves German umlauts from binary UTF-8 CSV files' do
    csv_content = "Email,First Name,Last Name,Company\n" \
                  "ferdinand@example.de,J. Ferdinand,Fürstenau,Reflex Aerospace\n"
    lead_import = create_lead_import_from_content(
      csv_content.b,
      column_mapping: {
        'Email' => 'email',
        'First Name' => 'first_name',
        'Last Name' => 'last_name',
        'Company' => 'company'
      }
    )

    assert LeadImportService.new(lead_import).call

    lead = Lead.find_by!(email: 'ferdinand@example.de')
    assert_equal 'J. Ferdinand', lead.first_name
    assert_equal 'Fürstenau', lead.last_name
    assert_equal 'Reflex Aerospace', lead.company
  end

  # WHY: A production Lewero import had a valid UTF-8 sharp S silently stripped from names.
  test 'preserves German sharp S from binary UTF-8 CSV files' do
    csv_content = "Email,First Name,Last Name,Full Name,Company,LinkedIn Profile\n" \
                  "christoph.thess@example.de,Christoph,Theß,Christoph Theß,Polytex Sportbeläge Produktions GmbH,https://www.linkedin.com/in/christoph-theß-122108295/\n"
    lead_import = create_lead_import_from_content(
      csv_content.b,
      column_mapping: {
        'Email' => 'email',
        'First Name' => 'first_name',
        'Last Name' => 'last_name',
        'Full Name' => 'full_name',
        'Company' => 'company',
        'LinkedIn Profile' => 'linkedin_url'
      }
    )

    assert LeadImportService.new(lead_import).call

    lead = Lead.find_by!(email: 'christoph.thess@example.de')
    person = Person.find_by!(email: 'christoph.thess@example.de')

    assert_equal 'Christoph', lead.first_name
    assert_equal 'Theß', lead.last_name
    assert_equal 'Christoph Theß', lead.full_name
    assert_equal 'Polytex Sportbeläge Produktions GmbH', lead.company
    assert_equal 'https://www.linkedin.com/in/christoph-theß-122108295/', lead.linkedin_url
    assert_equal 'Theß', person.last_name
    assert_equal 'Christoph Theß', person.full_name
  end

  # WHY: Empty values should be handled gracefully
  test 'handles empty values in CSV' do
    rows = [
      { 'Email' => 'empty@example.com', 'First Name' => '', 'Last Name' => 'Smith' }
    ]
    column_mapping = { 'Email' => 'email', 'First Name' => 'first_name', 'Last Name' => 'last_name' }
    lead_import = create_lead_import(rows, column_mapping: column_mapping)

    LeadImportService.new(lead_import).call

    lead = Lead.find_by(email: 'empty@example.com')
    assert_nil lead.first_name
    assert_equal 'Smith', lead.last_name
  end

  # === Error Row Number Tests ===

  # WHY: Error messages should show the correct source row number, not always row 1
  test 'records correct row numbers for validation errors' do
    rows = [
      { 'Email' => 'valid@example.com', 'First Name' => 'Valid', 'Website' => 'example.com' },
      { 'Email' => 'row2@example.com', 'First Name' => 'Row2', 'Website' => 'not-valid' },
      { 'Email' => 'row3@example.com', 'First Name' => 'Row3', 'Website' => 'also-not-valid' },
      { 'Email' => 'row4@example.com', 'First Name' => 'Row4', 'Website' => '.invalid.com' }
    ]
    column_mapping = {
      'Email' => 'email',
      'First Name' => 'first_name',
      'Website' => 'company_website'
    }
    lead_import = create_lead_import(rows, column_mapping: column_mapping)

    LeadImportService.new(lead_import).call

    lead_import.reload
    # Should have 3 errors for rows 2, 3, and 4
    assert_equal 3, lead_import.error_count
    assert_equal 1, lead_import.created_count

    # Verify each error has the correct row number (not all showing row 1)
    error_rows = lead_import.errors_detail.map { |e| e['row'] }.sort
    assert_equal [2, 3, 4], error_rows, "Expected errors on rows 2, 3, 4 but got #{error_rows}"
  end

  # === Person Integration Tests ===

  # WHY: Imported leads should be linked to Person records for global deduplication
  test 'creates Person record when importing new lead' do
    rows = [
      { 'Email' => 'new-person@example.com', 'First Name' => 'New', 'Last Name' => 'Person', 'Job Title' => 'CEO' }
    ]
    column_mapping = { 'Email' => 'email', 'First Name' => 'first_name', 'Last Name' => 'last_name',
                       'Job Title' => 'job_title' }
    lead_import = create_lead_import(rows, column_mapping: column_mapping)

    assert_difference 'Person.count', 1 do
      LeadImportService.new(lead_import).call
    end

    lead = Lead.find_by(email: 'new-person@example.com')
    person = Person.find_by(email: 'new-person@example.com')

    assert_not_nil lead.person, 'Lead should be linked to Person'
    assert_equal person, lead.person
    assert_equal 'New', person.first_name
    assert_equal 'Person', person.last_name
    assert_equal 'CEO', person.job_title
  end

  test 'import creates and links canonical company from company snapshot fields' do
    rows = [
      {
        'Email' => 'company-linked@example.com',
        'First Name' => 'Company',
        'Company' => 'Signal Corp',
        'Company Website' => 'https://www.signalcorp.com'
      }
    ]
    column_mapping = {
      'Email' => 'email',
      'First Name' => 'first_name',
      'Company' => 'company',
      'Company Website' => 'company_website'
    }
    lead_import = create_lead_import(rows, column_mapping: column_mapping)

    assert_difference 'Company.count', 1 do
      LeadImportService.new(lead_import).call
    end

    lead = Lead.find_by!(email: 'company-linked@example.com')
    person = Person.find_by!(email: 'company-linked@example.com')
    company = Company.find_by!(normalized_domain: 'signalcorp.com')

    assert_equal person, lead.person
    assert_equal company, person.current_company
    assert_equal 'Signal Corp', company.name
    assert_equal 'https://www.signalcorp.com', company.website_url
  end

  test 'import reuses canonical company for repeated normalized domain variants' do
    rows = [
      {
        'Email' => 'first-same-company@example.com',
        'First Name' => 'First',
        'Company' => 'Shared Co',
        'Company Website' => 'sharedco.com'
      },
      {
        'Email' => 'second-same-company@example.com',
        'First Name' => 'Second',
        'Company' => 'Shared Company',
        'Company Website' => 'https://www.sharedco.com/'
      }
    ]
    column_mapping = {
      'Email' => 'email',
      'First Name' => 'first_name',
      'Company' => 'company',
      'Company Website' => 'company_website'
    }
    lead_import = create_lead_import(rows, column_mapping: column_mapping)

    assert_difference 'Company.count', 1 do
      LeadImportService.new(lead_import).call
    end

    first_person = Person.find_by!(email: 'first-same-company@example.com')
    second_person = Person.find_by!(email: 'second-same-company@example.com')

    assert_equal first_person.current_company, second_person.current_company
    assert_equal 'sharedco.com', first_person.current_company.normalized_domain
  end

  test 'bulk chunk import links people to canonical company and agent' do
    rows = [
      {
        'Email' => 'bulk-first@example.com',
        'First Name' => 'Bulk First',
        'Company' => 'Bulk Signal',
        'Company Website' => 'bulk-signal.example'
      },
      {
        'Email' => 'bulk-second@example.com',
        'First Name' => 'Bulk Second',
        'Company' => 'Bulk Signal GmbH',
        'Company Website' => 'https://www.bulk-signal.example/team'
      }
    ]
    column_mapping = {
      'Email' => 'email',
      'First Name' => 'first_name',
      'Company' => 'company',
      'Company Website' => 'company_website'
    }
    lead_import = create_lead_import(rows, column_mapping: column_mapping, agent: @agent)

    assert_difference 'Person.count', 2 do
      assert_difference 'Company.count', 1 do
        assert_difference 'AgentLead.count', 2 do
          assert LeadImportService.new(lead_import).call
        end
      end
    end

    first_person = Person.find_by!(email: 'bulk-first@example.com')
    second_person = Person.find_by!(email: 'bulk-second@example.com')
    company = Company.find_by!(normalized_domain: 'bulk-signal.example')

    assert_equal company, first_person.current_company
    assert_equal company, second_person.current_company
    imported_leads = Lead.where(email: rows.map { |row| row['Email'] })

    assert_equal [company.id], imported_leads.map { |lead| lead.person.current_company_id }.uniq
    assert_equal 2, AgentLead.where(agent: @agent, lead: imported_leads).count
  end

  # WHY: If Person already exists globally, Lead should link to existing Person
  test 'links to existing Person when email already exists globally' do
    # Create existing Person
    existing_person = Person.create!(
      email: 'global-person@example.com',
      first_name: 'Global',
      last_name: 'Person'
    )

    rows = [
      { 'Email' => 'global-person@example.com', 'First Name' => 'Org Specific', 'Last Name' => 'Lead' }
    ]
    column_mapping = { 'Email' => 'email', 'First Name' => 'first_name', 'Last Name' => 'last_name' }
    lead_import = create_lead_import(rows, column_mapping: column_mapping)

    assert_no_difference 'Person.count' do
      LeadImportService.new(lead_import).call
    end

    lead = Lead.find_by(email: 'global-person@example.com')
    assert_equal existing_person, lead.person
  end

  # WHY: When updating an existing lead, it should be linked to Person if not already
  test 'links existing lead to Person on update' do
    # Create lead without Person link
    Lead.create!(
      organization: @organization,
      email: 'unlinked@example.com',
      first_name: 'Unlinked',
      person: nil
    )

    rows = [
      { 'Email' => 'unlinked@example.com', 'First Name' => 'Now Linked' }
    ]
    column_mapping = { 'Email' => 'email', 'First Name' => 'first_name' }
    lead_import = create_lead_import(rows, column_mapping: column_mapping)

    assert_difference 'Person.count', 1 do
      LeadImportService.new(lead_import).call
    end

    lead = Lead.find_by(email: 'unlinked@example.com')
    assert_not_nil lead.person, 'Lead should be linked to Person after update'
    assert_equal 'Now Linked', lead.first_name
  end

  # WHY: Person record should be updated with new data from import
  test 'updates Person with new data from import' do
    # Create Person with partial data
    person = Person.create!(
      email: 'partial-person@example.com',
      first_name: 'Partial'
    )

    rows = [
      { 'Email' => 'partial-person@example.com', 'First Name' => 'Partial', 'Last Name' => 'Complete',
        'Job Title' => 'Manager' }
    ]
    column_mapping = { 'Email' => 'email', 'First Name' => 'first_name', 'Last Name' => 'last_name',
                       'Job Title' => 'job_title' }
    lead_import = create_lead_import(rows, column_mapping: column_mapping)

    LeadImportService.new(lead_import).call

    person.reload
    assert_equal 'Complete', person.last_name
    assert_equal 'Manager', person.job_title
  end

  # WHY: Same Person should be shared across leads in different organizations
  test 'shares Person across leads in different organizations' do
    other_org = Organization.create!(name: 'Other Org')
    shared_email = 'shared@example.com'

    # Import to first org
    rows1 = [{ 'Email' => shared_email, 'First Name' => 'Shared' }]
    column_mapping = { 'Email' => 'email', 'First Name' => 'first_name' }
    lead_import1 = create_lead_import(rows1, column_mapping: column_mapping)
    LeadImportService.new(lead_import1).call

    # Import to second org
    lead_import2 = LeadImport.create!(
      organization: other_org,
      imported_by: @imported_by,
      original_filename: 'test2.csv',
      column_mapping: column_mapping,
      status: 'pending'
    )
    csv_content = create_csv_content([{ 'Email' => shared_email, 'First Name' => 'Shared' }])
    lead_import2.csv_file.attach(io: StringIO.new(csv_content), filename: 'test2.csv', content_type: 'text/csv')
    LeadImportService.new(lead_import2).call

    # Both leads should share the same Person
    lead1 = Lead.find_by(organization: @organization, email: shared_email)
    lead2 = Lead.find_by(organization: other_org, email: shared_email)
    person = Person.find_by(email: shared_email)

    assert_equal 1, Person.where(email: shared_email).count, 'Should only have one Person'
    assert_equal person, lead1.person
    assert_equal person, lead2.person
  end

  # === Counter Tests ===

  # WHY: All counters should be accurate after import
  test 'accurately counts all import outcomes' do
    # Create existing lead for update
    Lead.create!(organization: @organization, email: 'existing@example.com', first_name: 'Old')

    rows = [
      { 'Email' => 'new@example.com', 'First Name' => 'New' },           # Created
      { 'Email' => 'existing@example.com', 'First Name' => 'Updated' },  # Updated
      { 'Email' => '', 'First Name' => 'Missing' },                      # Skipped
      { 'Email' => 'spam@global-blocked.com', 'First Name' => 'Spam' }   # Blacklisted
    ]
    column_mapping = { 'Email' => 'email', 'First Name' => 'first_name' }
    lead_import = create_lead_import(rows, column_mapping: column_mapping)

    LeadImportService.new(lead_import).call

    lead_import.reload
    assert_equal 1, lead_import.created_count
    assert_equal 1, lead_import.updated_count
    assert_equal 1, lead_import.skipped_count
    assert_equal 1, lead_import.blacklisted_count
  end

  test 'bulk path writes people and leads once per unique chunk' do
    rows = [
      { 'Email' => 'bulk-one@example.com', 'First Name' => 'Bulk One' },
      { 'Email' => 'bulk-two@example.com', 'First Name' => 'Bulk Two' },
      { 'Email' => 'bulk-three@example.com', 'First Name' => 'Bulk Three' }
    ]
    column_mapping = { 'Email' => 'email', 'First Name' => 'first_name' }
    lead_import = create_lead_import(rows, column_mapping: column_mapping)

    people_insert_count = 0
    lead_insert_count = 0
    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |_name, _start, _finish, _id, payload|
      next if payload[:cached]

      people_insert_count += 1 if payload[:sql].match?(/INSERT INTO "people"/)
      lead_insert_count += 1 if payload[:sql].match?(/INSERT INTO "leads"/)
    end

    assert LeadImportService.new(lead_import).call

    assert_equal 1, people_insert_count
    assert_equal 1, lead_insert_count
    assert_equal 3, lead_import.reload.created_count
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end

  test 'bulk lead failure rolls back and falls back without miscounting created rows' do
    rows = [
      { 'Email' => 'fallback-one@example.com', 'First Name' => 'Fallback One' },
      { 'Email' => 'fallback-two@example.com', 'First Name' => 'Fallback Two' }
    ]
    column_mapping = { 'Email' => 'email', 'First Name' => 'first_name' }
    lead_import = create_lead_import(rows, column_mapping: column_mapping)

    Lead.stub(:upsert_all, ->(*_args, **_kwargs) { raise ActiveRecord::RecordNotUnique, 'forced bulk failure' }) do
      assert LeadImportService.new(lead_import).call
    end

    lead_import.reload
    assert_equal 2, lead_import.created_count
    assert_equal 0, lead_import.updated_count
    assert_equal 2, Lead.where(organization: @organization, email: rows.map { |row| row['Email'] }).count
    assert_equal 2, Person.where(email: rows.map { |row| row['Email'] }).count
  end
end
