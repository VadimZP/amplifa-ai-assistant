# frozen_string_literal: true

require 'test_helper'
require 'csv'

class Settings::BlacklistsTest < ActionDispatch::IntegrationTest
  # WHY: Test the Settings::BlacklistsController which allows customers
  # to view and manage their organization's blacklist entries.
  # Customer admins can create and delete entries, regular users have read-only access.

  setup do
    # WHY: Load fixtures for testing different user roles and blacklist entries
    @customer_admin = accounts(:customer_admin)
    @customer_user = accounts(:customer_user)
    @amplifa_admin = accounts(:amplifa_admin)
    @acme_org = organizations(:acme)
    @acme_email_blacklist = blacklists(:acme_email_blacklist)
    @acme_domain_blacklist = blacklists(:acme_domain_blacklist)
    @global_email = blacklists(:global_email)
  end

  # =========================================================================
  # INDEX ACTION TESTS
  # =========================================================================

  test 'customer admin can view blacklist index' do
    # WHY: Customer admins need to see their organization's blacklist entries
    # to manage who they don't want to contact
    login_as(@customer_admin)

    get settings_blacklists_path, headers: inertia_headers
    assert_response :success

    # WHY: Verify correct Inertia component is rendered
    assert_inertia_component 'Customer/Settings/Blacklists/Index'

    # WHY: Verify blacklist data is returned
    props = inertia_props
    assert props['email_blacklists'].is_a?(Array)
    assert props['domain_blacklists'].is_a?(Array)
    assert props['pagination'].present?
    assert props['pagination']['emails'].present?
    assert props['pagination']['domains'].present?

    # WHY: Customer admin should have permission to create/delete entries
    assert_equal true, props['canManage']
  end

  test 'customer user can view blacklist index (read-only)' do
    # WHY: Customer users should be able to see blacklist entries for transparency
    # but should not have create/delete permissions (read-only access)
    login_as(@customer_user)

    get settings_blacklists_path, headers: inertia_headers
    assert_response :success

    # WHY: Verify correct component and read-only permissions
    assert_inertia_component 'Customer/Settings/Blacklists/Index'
    props = inertia_props
    assert_equal false, props['canManage'], 'Customer user should not have manage permission'
    assert_equal false, props['canAdd'], 'Customer user should not be able to add entries'
    assert_equal false, props['canRemove'], 'Customer user should not be able to remove entries'
  end

  test "index shows only organization's blacklist entries (not global)" do
    # WHY: Customer blacklist view should only show their organization's entries.
    # Global entries should NOT appear in customer view to avoid confusion -
    # customers don't need to see system-wide blocks, only their own.
    login_as(@customer_admin)

    get settings_blacklists_path, headers: inertia_headers
    assert_response :success

    props = inertia_props
    blacklists = combined_blacklists(props)

    # WHY: Verify we have ACME's organization-specific entries
    values = blacklists.map { |b| b['value'] }
    assert_includes values, @acme_email_blacklist.value
    assert_includes values, @acme_domain_blacklist.value

    # WHY: Global entries should NOT appear in customer view
    global_entries = blacklists.select { |b| b['is_global'] == true }
    assert_empty global_entries, 'Global entries should NOT appear in customer blacklist view'

    # WHY: All entries shown should be deletable by the customer admin
    # since we only show org-specific entries now
    blacklists.each do |entry|
      assert_equal true, entry['can_delete'], 'Org entries should be deletable by admin'
      assert_equal false, entry['is_global'], 'No global entries should be in customer view'
    end
  end

  test 'index includes value_type field for display' do
    # WHY: The index view needs value_type to show if it's an email or domain
    login_as(@customer_admin)

    get settings_blacklists_path, headers: inertia_headers
    assert_response :success

    props = inertia_props
    blacklists = combined_blacklists(props)

    # WHY: Verify value_type is present in the response
    blacklists.each do |entry|
      assert entry.key?('value_type'), 'Entry should have value_type'
      assert_includes %w[email domain], entry['value_type']
    end
  end

  test 'index paginates blacklist entries at 25 per section' do
    login_as(@customer_admin)

    30.times do |i|
      Blacklist.create!(
        organization: @acme_org,
        created_by: @customer_admin,
        source: 'import',
        value: "bulk-domain-#{i}.example",
        value_type: 'domain'
      )
    end

    expected_count = Blacklist.where(organization_id: @acme_org.id, value_type: 'domain').count

    get settings_blacklists_path, headers: inertia_headers
    assert_response :success

    props = inertia_props
    domain_values = props['domain_blacklists'].map { |entry| entry['value'] }

    assert_equal 25, props['domain_blacklists'].length
    assert_includes domain_values, 'bulk-domain-29.example'
    assert_not_includes domain_values, 'bulk-domain-0.example'

    assert_equal expected_count, props.dig('pagination', 'domains', 'total_count')
    assert_equal 25, props.dig('pagination', 'domains', 'per_page')
    assert_operator props.dig('pagination', 'domains', 'total_pages'), :>, 1
  end

  test 'index supports email search filter' do
    login_as(@customer_admin)

    expected_email_total = Blacklist.where(organization_id: @acme_org.id, value_type: 'email').count

    get settings_blacklists_path(email_search: 'competitor'), headers: inertia_headers
    assert_response :success

    props = inertia_props
    email_values = props['email_blacklists'].map { |entry| entry['value'] }

    assert_equal 'competitor', props.dig('filters', 'email_search')
    assert_equal 1, email_values.length
    assert_equal 'competitor@rival.com', email_values.first
    assert_equal 1, props.dig('pagination', 'emails', 'total_count')
    assert_equal expected_email_total, props.dig('totals', 'emails')
  end

  test 'index supports domain pagination via domain_page param' do
    login_as(@customer_admin)

    30.times do |i|
      Blacklist.create!(
        organization: @acme_org,
        created_by: @customer_admin,
        source: 'import',
        value: "paginated-domain-#{i}.example",
        value_type: 'domain'
      )
    end

    get settings_blacklists_path(domain_page: 2), headers: inertia_headers
    assert_response :success

    props = inertia_props
    assert_equal 2, props.dig('pagination', 'domains', 'current_page')
    assert_operator props['domain_blacklists'].length, :>, 0
  end

  # =========================================================================
  # CREATE ACTION TESTS
  # =========================================================================

  test 'customer admin can create email blacklist entry' do
    # WHY: Customer admins need to add emails to their blacklist
    # to prevent unwanted outreach to specific contacts
    login_as(@customer_admin)

    assert_difference 'Blacklist.count', 1 do
      post settings_blacklists_path, params: {
        blacklist: {
          value: 'newblock@example.com',
          value_type: 'email'
        }
      }
    end

    # WHY: Should redirect to index after successful creation
    assert_response :redirect
    assert_redirected_to settings_blacklists_path
    assert_match(/created|added/i, flash[:notice])

    # WHY: Verify the created entry has correct attributes
    new_entry = Blacklist.last
    assert_equal 'newblock@example.com', new_entry.value
    assert_equal 'email', new_entry.value_type
    assert_equal 'manual', new_entry.source
    assert_equal @acme_org.id, new_entry.organization_id
    assert_equal @customer_admin.id, new_entry.created_by_id
  end

  test 'customer admin can create domain blacklist entry' do
    # WHY: Customer admins need to add domains to their blacklist
    # to prevent outreach to all contacts at a specific company
    login_as(@customer_admin)

    assert_difference 'Blacklist.count', 1 do
      post settings_blacklists_path, params: {
        blacklist: {
          value: 'blockedcompany.com',
          value_type: 'domain'
        }
      }
    end

    # WHY: Verify the domain entry was created correctly
    new_entry = Blacklist.last
    assert_equal 'blockedcompany.com', new_entry.value
    assert_equal 'domain', new_entry.value_type
  end

  test 'customer user cannot create blacklist entry' do
    login_as(@customer_user)

    assert_no_difference 'Blacklist.count' do
      post settings_blacklists_path, params: {
        blacklist: {
          value: 'allowedforuser@test.com',
          value_type: 'email'
        }
      }
    end

    assert_response :redirect
    assert_redirected_to settings_blacklists_path
    assert_equal I18n.t('pundit.not_authorized'), flash[:alert]
  end

  test 'create with invalid email shows validation errors' do
    # WHY: Validation errors should be returned to the user
    # so they can correct their input
    login_as(@customer_admin)

    assert_no_difference 'Blacklist.count' do
      post settings_blacklists_path, params: {
        blacklist: {
          value: 'not-a-valid-email',
          value_type: 'email'
        }
      }, headers: inertia_headers
    end

    # WHY: Should re-render form with errors
    assert_response :success
    props = inertia_props
    assert props['errors'].present?
  end

  test 'create with duplicate value shows validation errors' do
    # WHY: Duplicate entries within an organization should be rejected
    login_as(@customer_admin)

    assert_no_difference 'Blacklist.count' do
      post settings_blacklists_path, params: {
        blacklist: {
          value: @acme_email_blacklist.value,
          value_type: 'email'
        }
      }, headers: inertia_headers
    end

    # WHY: Should show uniqueness validation error
    assert_response :success
    props = inertia_props
    assert props['errors'].present?
  end

  # =========================================================================
  # IMPORT ACTION TESTS
  # =========================================================================

  test 'customer admin can import blacklist entries from text' do
    # WHY: Customers need to bulk import blacklist entries
    # from CSV or text input
    login_as(@customer_admin)

    input = "import1@test.com\nimport2@test.com\nimportdomain.com"

    assert_difference 'Blacklist.count', 3 do
      post import_settings_blacklists_path, params: {
        input: input
      }
    end

    # WHY: Should redirect with success message showing counts
    assert_response :redirect
    assert_redirected_to settings_blacklists_path
    assert flash[:notice].present?
  end

  test 'customer user cannot import blacklist entries' do
    login_as(@customer_user)

    input = 'shouldfail@test.com'

    assert_no_difference 'Blacklist.count' do
      post import_settings_blacklists_path, params: {
        input: input
      }
    end

    assert_response :redirect
    assert_equal I18n.t('pundit.not_authorized'), flash[:alert]
  end

  test 'customer admin can export organization blacklist CSV' do
    login_as(@customer_admin)

    get export_settings_blacklists_path
    assert_response :success
    assert_equal 'text/csv', response.media_type
    assert_match(/attachment/, response.headers['Content-Disposition'])

    rows = CSV.parse(response.body, headers: true)
    values = rows.map { |row| row['value'] }

    assert_equal %w[value type reason], rows.headers
    assert_includes values, @acme_email_blacklist.value
    assert_includes values, @acme_domain_blacklist.value
    assert_not_includes values, @global_email.value
    assert_not_includes values, blacklists(:beta_unsubscribe).value

    email_row = rows.find { |row| row['value'] == @acme_email_blacklist.value }
    assert_not_nil email_row
    assert_equal 'email', email_row['type']
    assert_equal @acme_email_blacklist.reason, email_row['reason']
  end

  test 'customer user can export read only organization blacklist CSV' do
    login_as(@customer_user)

    get export_settings_blacklists_path
    assert_response :success

    rows = CSV.parse(response.body, headers: true)
    assert_equal %w[value type reason], rows.headers
  end

  # =========================================================================
  # DESTROY ACTION TESTS
  # =========================================================================

  test "customer admin can delete their organization's blacklist entry" do
    # WHY: Customer admins need to remove entries from their blacklist
    # when they want to re-enable outreach to someone
    login_as(@customer_admin)

    assert_difference 'Blacklist.count', -1 do
      delete settings_blacklist_path(@acme_email_blacklist)
    end

    # WHY: Should redirect to index after successful deletion
    assert_response :redirect
    assert_redirected_to settings_blacklists_path
    assert_match(/removed|deleted/i, flash[:notice])
  end

  test 'customer user cannot delete blacklist entry' do
    login_as(@customer_user)

    assert_no_difference 'Blacklist.count' do
      delete settings_blacklist_path(@acme_email_blacklist)
    end

    assert_response :redirect
    assert_equal I18n.t('pundit.not_authorized'), flash[:alert]
  end

  test 'customer admin cannot delete global blacklist entry' do
    # WHY: Global entries are managed by Amplifa admins only
    # Customers should not be able to delete them
    login_as(@customer_admin)

    assert_no_difference 'Blacklist.count' do
      delete settings_blacklist_path(@global_email)
    end

    # WHY: Should redirect with error - cannot delete global entry
    assert_response :redirect
    assert flash[:alert].present?
  end

  test "customer admin cannot delete another organization's blacklist entry" do
    # WHY: Multi-tenancy security - users should not be able to delete
    # entries from other organizations
    login_as(@customer_admin)

    # Get a blacklist entry from a different organization
    beta_entry = blacklists(:beta_unsubscribe)

    assert_no_difference 'Blacklist.count' do
      delete settings_blacklist_path(beta_entry)
    end

    # WHY: Should return error - entry not found or not authorized
    assert_response :redirect
    assert flash[:alert].present?
  end

  # =========================================================================
  # ADMIN REDIRECT TESTS
  # =========================================================================

  # =========================================================================
  # AUTHENTICATION TESTS
  # =========================================================================

  test 'unauthenticated user is redirected from index' do
    # WHY: Blacklist data is sensitive and requires authentication
    get settings_blacklists_path

    # WHY: Should redirect to login (Rodauth handles this)
    assert_response :redirect
  end

  test 'unauthenticated user cannot create blacklist entry' do
    # WHY: Creating blacklist entries requires authentication
    assert_no_difference 'Blacklist.count' do
      post settings_blacklists_path, params: {
        blacklist: {
          value: 'unauthenticated@test.com',
          value_type: 'email'
        }
      }
    end

    assert_response :redirect
  end

  # =========================================================================
  # ACTIVITY LOGGING TESTS
  # =========================================================================

  test 'creating blacklist entry logs admin activity' do
    # WHY: Blacklist changes should be logged for audit trail
    login_as(@customer_admin)

    assert_difference 'AdminActivity.count', 1 do
      post settings_blacklists_path, params: {
        blacklist: {
          value: 'activity-test@example.com',
          value_type: 'email'
        }
      }
    end

    # WHY: Verify the activity was logged correctly
    activity = AdminActivity.last
    assert_equal @customer_admin.id, activity.account_id
    assert_equal @acme_org.id, activity.organization_id
    assert_equal 'blacklist_create', activity.action
    assert_equal 'activity-test@example.com', activity.details['value']
  end

  test 'deleting blacklist entry logs admin activity' do
    # WHY: Blacklist deletions should also be logged for audit trail
    login_as(@customer_admin)

    assert_difference 'AdminActivity.count', 1 do
      delete settings_blacklist_path(@acme_email_blacklist)
    end

    # WHY: Verify the activity was logged correctly
    activity = AdminActivity.last
    assert_equal @customer_admin.id, activity.account_id
    assert_equal 'blacklist_delete', activity.action
  end

  private

  def combined_blacklists(props)
    props.fetch('email_blacklists', []) + props.fetch('domain_blacklists', [])
  end
end
