# frozen_string_literal: true

require 'test_helper'

# rubocop:disable Metrics/ClassLength, Metrics/BlockLength
class PlaybookLeadImportsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @customer_admin = accounts(:customer_admin)
    @customer_user = accounts(:customer_user)
    @playbook = playbooks(:approved_playbook)
  end

  test 'customer admin can view playbook import leads page' do
    login_as(@customer_admin)

    get import_leads_playbook_path(@playbook), headers: inertia_headers
    assert_response :success
    assert_inertia_component 'Playbooks/ImportLeads'

    props = inertia_props
    assert_equal @playbook.id, props['playbook']['id']
    assert props['lead_imports'].is_a?(Array)
  end

  test 'import leads list only includes imports created by current user for playbook agents' do
    login_as(@customer_admin)

    @playbook.agents.destroy_all
    shared_agent = @playbook.organization.agents.create!(
      name: 'Playbook Import Agent',
      playbook: @playbook,
      status: 'draft',
      locale: @playbook.language || 'en',
      created_by: @customer_admin,
      llm_model: Agent::DEFAULT_LLM_MODEL
    )

    own_import = LeadImport.create!(
      organization: @playbook.organization,
      agent: shared_agent,
      imported_by: @customer_admin,
      original_filename: 'my-file.csv',
      column_mapping: { 'Email' => 'email' },
      status: 'pending'
    )

    LeadImport.create!(
      organization: @playbook.organization,
      agent: shared_agent,
      imported_by: @customer_user,
      original_filename: 'other-user-file.csv',
      column_mapping: { 'Email' => 'email' },
      status: 'pending'
    )

    get import_leads_playbook_path(@playbook), headers: inertia_headers
    assert_response :success

    props = inertia_props
    import_ids = props['lead_imports'].map { |item| item['id'] }

    assert_includes import_ids, own_import.id
    assert_equal 1, import_ids.size
  end

  test 'import leads page shows current user and admin lead list files for current playbook' do
    login_as(@customer_admin)

    own_file = create_organization_file(@playbook, @customer_admin, 'own-playbook-file.csv')
    other_playbook_file = create_organization_file(playbooks(:draft_playbook), @customer_admin, 'other-playbook-file.csv')
    other_user_file = create_organization_file(@playbook, @customer_user, 'other-user-file.csv')

    admin_all_playbooks_file = @playbook.organization.organization_files.new(
      applies_to_all_playbooks: true,
      uploaded_by: accounts(:amplifa_admin),
      original_filename: 'admin-all-playbooks-file.csv',
      file_size_bytes: 64,
      content_type: 'text/csv'
    )
    admin_all_playbooks_file.file.attach(io: StringIO.new("Company\nAdmin\n"),
                                         filename: 'admin-all-playbooks-file.csv', content_type: 'text/csv')
    admin_all_playbooks_file.save!

    get import_leads_playbook_path(@playbook), headers: inertia_headers
    assert_response :success

    files = inertia_props['lead_list_files']
    file_ids = files.map { |file| file['id'] }
    assert_includes file_ids, own_file.id
    assert_includes file_ids, admin_all_playbooks_file.id
    assert_not_includes file_ids, other_playbook_file.id
    assert_not_includes file_ids, other_user_file.id
  end

  test 'creating import uses first playbook agent when one exists' do
    login_as(@customer_admin)

    @playbook.agents.destroy_all
    first_agent = @playbook.organization.agents.create!(
      name: 'First Agent',
      playbook: @playbook,
      status: 'draft',
      locale: @playbook.language || 'en',
      created_by: @customer_admin,
      llm_model: Agent::DEFAULT_LLM_MODEL
    )
    @playbook.organization.agents.create!(
      name: 'Second Agent',
      playbook: @playbook,
      status: 'draft',
      locale: @playbook.language || 'en',
      created_by: @customer_admin,
      llm_model: Agent::DEFAULT_LLM_MODEL
    )

    csv_file = Rack::Test::UploadedFile.new(
      StringIO.new("Email,First Name\njohn@example.com,John\n"),
      'text/csv',
      original_filename: 'customers.csv'
    )

    assert_enqueued_with(job: ProcessLeadImportJob) do
      assert_difference 'LeadImport.count', 1 do
        post import_leads_playbook_path(@playbook), params: {
          lead_import: {
            csv_file: csv_file,
            column_mapping: { 'Email' => 'email', 'First Name' => 'first_name' }.to_json
          }
        }
      end
    end

    assert_response :created
    lead_import = LeadImport.last
    assert_equal @customer_admin.id, lead_import.imported_by_id
    assert_equal first_agent.id, lead_import.agent_id
  end

  test 'creating import creates draft agent from playbook when missing' do
    login_as(@customer_admin)
    @playbook.agents.destroy_all

    csv_file = Rack::Test::UploadedFile.new(
      StringIO.new("Email\nagent-create@example.com\n"),
      'text/csv',
      original_filename: 'create-agent.csv'
    )

    assert_difference 'Agent.count', 1 do
      assert_difference 'LeadImport.count', 1 do
        post import_leads_playbook_path(@playbook), params: {
          lead_import: {
            csv_file: csv_file,
            column_mapping: { 'Email' => 'email' }.to_json
          }
        }
      end
    end

    assert_response :created
    created_agent = Agent.order(:id).last
    created_import = LeadImport.order(:id).last

    assert_equal @playbook.id, created_agent.playbook_id
    assert_equal 'draft', created_agent.status
    assert_equal @customer_admin.id, created_agent.created_by_id
    assert_equal created_agent.id, created_import.agent_id

    activity = AdminActivity.order(:id).last
    assert_equal 'agent_created_from_playbook', activity.action
    assert_equal true, activity.details['initiated_by_customer']
  end

  test 'creating import strips blank skip mappings before saving' do
    login_as(@customer_admin)

    csv_file = Rack::Test::UploadedFile.new(
      StringIO.new("Email,Company Table Data\nskip@example.com,ignored\n"),
      'text/csv',
      original_filename: 'skip-columns.csv'
    )

    post import_leads_playbook_path(@playbook), params: {
      lead_import: {
        csv_file: csv_file,
        column_mapping: { 'Email' => 'email', 'Company Table Data' => '' }.to_json
      }
    }

    assert_response :created

    lead_import = LeadImport.last
    assert_equal({ 'Email' => 'email' }, lead_import.column_mapping)
  end

  private

  def create_organization_file(playbook, uploaded_by, filename)
    organization_file = playbook.organization.organization_files.new(
      uploaded_by: uploaded_by,
      original_filename: filename,
      file_size_bytes: 64,
      content_type: 'text/csv'
    )
    organization_file.file.attach(io: StringIO.new("Company\nAcme\n"), filename: filename, content_type: 'text/csv')
    organization_file.save!
    organization_file.playbooks << playbook
    organization_file
  end

  def login_as(account)
    password = account.email.include?('amplifa') ? 'password123' : 'password'
    post login_path, params: { email: account.email, password: password }
  end

  def with_stubbed_file_summary(summary, &block)
    generator = Object.new
    generator.define_singleton_method(:generate) { |_| summary }
    FileSummaryGenerator.stub(:new, generator, &block)
  end
end
# rubocop:enable Metrics/ClassLength, Metrics/BlockLength
