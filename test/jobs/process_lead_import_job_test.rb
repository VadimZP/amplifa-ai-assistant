# frozen_string_literal: true

require 'test_helper'
require 'csv'

class ProcessLeadImportJobTest < ActiveJob::TestCase
  setup do
    @organization = organizations(:acme)
    @imported_by = accounts(:customer_admin)
    @imported_by_admin = accounts(:amplifa_admin)
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
  def create_lead_import(csv_rows, column_mapping:, agent: nil, imported_by: @imported_by)
    csv_content = create_csv_content(csv_rows)

    lead_import = LeadImport.create!(
      organization: @organization,
      imported_by: imported_by,
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

  test 'job is enqueued to lead imports queue' do
    assert_equal 'lead_imports', ProcessLeadImportJob.new.queue_name
  end

  # WHY: Verify job can process a simple import successfully
  test 'processes lead import successfully' do
    rows = [
      { 'Email' => 'job1@example.com', 'First Name' => 'Job', 'Last Name' => 'Test' },
      { 'Email' => 'job2@example.com', 'First Name' => 'Another', 'Last Name' => 'User' }
    ]
    column_mapping = { 'Email' => 'email', 'First Name' => 'first_name', 'Last Name' => 'last_name' }
    lead_import = create_lead_import(rows, column_mapping: column_mapping)

    assert_difference 'Lead.count', 2 do
      ProcessLeadImportJob.perform_now(lead_import.id)
    end

    lead_import.reload
    assert_equal 'completed', lead_import.status
    assert_equal 2, lead_import.created_count
  end

  test 'job import populates canonical company linkage' do
    rows = [
      {
        'Email' => 'job-company@example.com',
        'First Name' => 'Job',
        'Company' => 'Job Signals',
        'Company Website' => 'jobsignals.com'
      }
    ]
    column_mapping = {
      'Email' => 'email',
      'First Name' => 'first_name',
      'Company' => 'company',
      'Company Website' => 'company_website'
    }
    lead_import = create_lead_import(rows, column_mapping: column_mapping)

    ProcessLeadImportJob.perform_now(lead_import.id)

    person = Person.find_by!(email: 'job-company@example.com')
    assert_not_nil person.current_company
    assert_equal 'jobsignals.com', person.current_company.normalized_domain
  end

  # WHY: Job should be discarded when LeadImport record doesn't exist to avoid infinite retries
  test 'discards job when lead import not found' do
    assert_nothing_raised do
      ProcessLeadImportJob.perform_now(-1)
    end
  end

  # WHY: Job should process imports with agent assignment
  test 'processes import with agent and creates AgentLead records' do
    rows = [
      { 'Email' => 'agent-job@example.com', 'First Name' => 'Agent' }
    ]
    column_mapping = { 'Email' => 'email', 'First Name' => 'first_name' }
    lead_import = create_lead_import(rows, column_mapping: column_mapping, agent: @agent)

    assert_difference 'AgentLead.count', 1 do
      ProcessLeadImportJob.perform_now(lead_import.id)
    end

    lead = Lead.find_by(email: 'agent-job@example.com')
    assert_includes @agent.leads, lead
  end

  test 'fails after first attempt without retrying and persists failure reason' do
    lead_import = LeadImport.create!(
      organization: @organization,
      imported_by: @imported_by,
      original_filename: 'missing.csv',
      column_mapping: { 'Email' => 'email' },
      status: 'pending'
    )

    assert_nothing_raised do
      assert_no_enqueued_jobs only: ProcessLeadImportJob do
        ProcessLeadImportJob.perform_now(lead_import.id)
      end
    end

    lead_import.reload
    assert_equal 'failed', lead_import.status
    assert(lead_import.errors_detail.any? { |error| error['error'].include?('CSV file is not attached') })
  end

  test 'records unexpected runtime error reason without retrying' do
    rows = [
      { 'Email' => 'runtime-error@example.com', 'First Name' => 'Runtime' }
    ]
    column_mapping = { 'Email' => 'email', 'First Name' => 'first_name' }
    lead_import = create_lead_import(rows, column_mapping: column_mapping)

    failing_service = Object.new
    failing_service.define_singleton_method(:call) { raise StandardError, 'simulated crash in service call' }
    failing_service.define_singleton_method(:last_error) { nil }

    LeadImportService.stub(:new, ->(_lead_import) { failing_service }) do
      assert_nothing_raised do
        assert_no_enqueued_jobs only: ProcessLeadImportJob do
          ProcessLeadImportJob.perform_now(lead_import.id)
        end
      end
    end

    lead_import.reload
    assert_equal 'failed', lead_import.status
    assert_includes lead_import.errors_detail.to_json, 'simulated crash in service call'
  end

  # WHY: Job should handle blacklisted emails correctly
  test 'correctly handles blacklisted emails during import' do
    rows = [
      { 'Email' => 'spam@global-blocked.com', 'First Name' => 'Spam' },
      { 'Email' => 'clean@example.com', 'First Name' => 'Clean' }
    ]
    column_mapping = { 'Email' => 'email', 'First Name' => 'first_name' }
    lead_import = create_lead_import(rows, column_mapping: column_mapping)

    ProcessLeadImportJob.perform_now(lead_import.id)

    lead_import.reload
    assert_equal 1, lead_import.blacklisted_count
    assert_equal 1, lead_import.created_count

    spam_lead = Lead.find_by(email: 'spam@global-blocked.com')
    assert spam_lead.blacklisted?
  end

  test 'correctly handles blacklisted company website domains during import' do
    Blacklist.create!(
      organization: @organization,
      created_by: @imported_by,
      value: 'kienbaum.*',
      value_type: 'domain',
      source: 'manual',
      reason: 'Wildcard import block'
    )

    rows = [
      { 'Email' => 'safe@allowed.ch', 'First Name' => 'Blocked', 'Company Website' => 'https://www.kienbaum.de' }
    ]
    column_mapping = {
      'Email' => 'email',
      'First Name' => 'first_name',
      'Company Website' => 'company_website'
    }
    lead_import = create_lead_import(rows, column_mapping: column_mapping)

    ProcessLeadImportJob.perform_now(lead_import.id)

    lead_import.reload
    assert_equal 1, lead_import.blacklisted_count

    blocked_lead = Lead.find_by(email: 'safe@allowed.ch')
    assert blocked_lead.blacklisted?
  end

  test 'sends admin notification email when customer import completes' do
    rows = [
      { 'Email' => 'customer-notify@example.com', 'First Name' => 'Customer' }
    ]
    column_mapping = { 'Email' => 'email', 'First Name' => 'first_name' }
    lead_import = create_lead_import(rows, column_mapping: column_mapping, imported_by: @imported_by)

    assert_enqueued_jobs 1, only: ActionMailer::MailDeliveryJob do
      ProcessLeadImportJob.perform_now(lead_import.id)
    end
  end

  test 'does not send admin notification email when admin import completes' do
    rows = [
      { 'Email' => 'admin-notify@example.com', 'First Name' => 'Admin' }
    ]
    column_mapping = { 'Email' => 'email', 'First Name' => 'first_name' }
    lead_import = create_lead_import(rows, column_mapping: column_mapping, imported_by: @imported_by_admin)

    assert_enqueued_jobs 0, only: ActionMailer::MailDeliveryJob do
      ProcessLeadImportJob.perform_now(lead_import.id)
    end
  end
end
