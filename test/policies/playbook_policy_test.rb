require 'test_helper'

class PlaybookPolicyTest < ActiveSupport::TestCase
  def setup
    @amplifa_admin = accounts(:amplifa_admin)
    @customer_admin = accounts(:customer_admin)
    @customer_user = accounts(:customer_user)
    @acme_playbook = playbooks(:draft_playbook)
  end

  def teardown
    Current.reset
  end

  # index? tests
  test 'index? returns true for all authenticated users' do
    # WHY: All authenticated users can list playbooks
    # (scoped to their organization via Scope class)
    assert PlaybookPolicy.new(@amplifa_admin, Playbook).index?
    assert PlaybookPolicy.new(@customer_admin, Playbook).index?
    assert PlaybookPolicy.new(@customer_user, Playbook).index?
  end

  # show? tests
  test 'show? returns true for amplifa_admin viewing any playbook' do
    # WHY: Amplifa admins need to view all playbooks across all organizations
    # to manage the platform and help customers
    policy = PlaybookPolicy.new(@amplifa_admin, @acme_playbook)
    assert policy.show?, 'Amplifa admin should be able to view any playbook'
  end

  test 'show? returns true for customer viewing own org playbook' do
    Current.organization = organizations(:acme)
    # WHY: Customers should be able to view playbooks that belong to their organization
    policy = PlaybookPolicy.new(@customer_admin, @acme_playbook)
    assert policy.show?, "Customer should be able to view their org's playbook"
  end

  test 'show? returns false for customer viewing other org playbook' do
    # WHY: Customers should not be able to view playbooks from other organizations
    # to maintain data privacy and security

    # Create a playbook for techcorp (different org)
    techcorp = organizations(:techcorp)
    # Product is now JSONB within playbook
    techcorp_playbook = Playbook.create!(
      organization: techcorp,
      product: { 'name' => 'Analytics Suite', 'description' => 'Test', 'metadata' => {} },
      status: 'draft',
      language: 'en',
      personae: [{ id: '1', name: 'Test', title: 'Manager', order: 1, pain_points: ['test'] }],
      use_cases: [{ id: '1', title: 'Test', description: 'Test case', order: 1 }]
    )

    policy = PlaybookPolicy.new(@customer_admin, techcorp_playbook)
    assert_not policy.show?, "Customer should not be able to view other org's playbook"
  end

  # create? tests
  test 'create? returns true for amplifa_admin' do
    # WHY: Only Amplifa admins should be able to create playbooks
    # either manually or through AI generation
    policy = PlaybookPolicy.new(@amplifa_admin, Playbook)
    assert policy.create?, 'Amplifa admin should be able to create playbooks'
  end

  test 'create? returns false for customer_admin' do
    # WHY: Customer admins should not create playbooks directly
    # Playbooks are created by Amplifa admins
    policy = PlaybookPolicy.new(@customer_admin, Playbook)
    assert_not policy.create?, 'Customer admin should not be able to create playbooks'
  end

  test 'create? returns false for customer_user' do
    # WHY: Customer users should not create playbooks
    policy = PlaybookPolicy.new(@customer_user, Playbook)
    assert_not policy.create?, 'Customer user should not be able to create playbooks'
  end

  # update? tests
  test 'update? returns true for amplifa_admin on any playbook' do
    # WHY: Amplifa admins can always edit playbooks regardless of status
    policy = PlaybookPolicy.new(@amplifa_admin, @acme_playbook)
    assert policy.update?, 'Amplifa admin should be able to update playbooks'
  end

  test 'update? returns true for customer on draft playbook in their org' do
    Current.organization = organizations(:acme)
    # WHY: Customers can edit draft playbooks in their organization
    @acme_playbook.update!(status: 'draft')
    policy = PlaybookPolicy.new(@customer_admin, @acme_playbook)
    assert policy.update?, 'Customer should be able to update draft playbook'
  end

  test 'update? returns true for customer on changes_requested playbook' do
    Current.organization = organizations(:acme)
    # WHY: Customers can edit playbooks that have changes requested
    @acme_playbook.update!(status: 'changes_requested')
    policy = PlaybookPolicy.new(@customer_admin, @acme_playbook)
    assert policy.update?, 'Customer should be able to update changes_requested playbook'
  end

  test 'update? returns false for customer on approved playbook' do
    # WHY: Customers cannot edit approved playbooks to maintain integrity
    @acme_playbook.update!(status: 'approved', approved_at: Time.current, approved_by: @customer_admin)
    policy = PlaybookPolicy.new(@customer_admin, @acme_playbook)
    assert_not policy.update?, 'Customer should not be able to update approved playbook'
  end

  test 'update? returns false for customer on archived playbook' do
    # WHY: Customers cannot edit archived playbooks
    @acme_playbook.update!(status: 'archived')
    policy = PlaybookPolicy.new(@customer_admin, @acme_playbook)
    assert_not policy.update?, 'Customer should not be able to update archived playbook'
  end

  # destroy? tests
  test 'destroy? returns true for amplifa_admin' do
    # WHY: Only Amplifa admins should be able to delete playbooks
    policy = PlaybookPolicy.new(@amplifa_admin, @acme_playbook)
    assert policy.destroy?, 'Amplifa admin should be able to delete playbooks'
  end

  test 'destroy? returns false for customer_admin' do
    # WHY: Customer admins should not be able to delete playbooks
    policy = PlaybookPolicy.new(@customer_admin, @acme_playbook)
    assert_not policy.destroy?, 'Customer admin should not be able to delete playbooks'
  end

  test 'destroy? returns false for customer_user' do
    # WHY: Customer users should not be able to delete playbooks
    policy = PlaybookPolicy.new(@customer_user, @acme_playbook)
    assert_not policy.destroy?, 'Customer user should not be able to delete playbooks'
  end

  # generate? tests
  test 'generate? returns true for amplifa_admin' do
    # WHY: Only Amplifa admins should be able to trigger AI generation
    policy = PlaybookPolicy.new(@amplifa_admin, Playbook)
    assert policy.generate?, 'Amplifa admin should be able to generate playbooks'
  end

  test 'generate? returns false for customer_admin' do
    # WHY: Customers cannot trigger AI generation directly
    policy = PlaybookPolicy.new(@customer_admin, Playbook)
    assert_not policy.generate?, 'Customer admin should not be able to generate playbooks'
  end

  # approve? tests
  test 'approve? returns true for customer on draft playbook in their org' do
    Current.organization = organizations(:acme)
    # WHY: Only customers can approve their own playbooks
    # Admins cannot approve (customers must approve)
    @acme_playbook.update!(status: 'draft')
    policy = PlaybookPolicy.new(@customer_admin, @acme_playbook)
    assert policy.approve?, 'Customer should be able to approve draft playbook'
  end

  test 'approve? returns true for customer on changes_requested playbook' do
    Current.organization = organizations(:acme)
    # WHY: Customers can approve playbooks that had changes requested
    @acme_playbook.update!(status: 'changes_requested')
    policy = PlaybookPolicy.new(@customer_admin, @acme_playbook)
    assert policy.approve?, 'Customer should be able to approve changes_requested playbook'
  end

  test 'approve? returns false for amplifa_admin' do
    # WHY: Amplifa admins cannot approve playbooks - only customers can approve
    @acme_playbook.update!(status: 'draft')
    policy = PlaybookPolicy.new(@amplifa_admin, @acme_playbook)
    assert_not policy.approve?, 'Amplifa admin should not be able to approve playbooks'
  end

  test 'approve? returns false for customer on approved playbook' do
    # WHY: Cannot approve an already approved playbook
    @acme_playbook.update!(status: 'approved', approved_at: Time.current, approved_by: @customer_admin)
    policy = PlaybookPolicy.new(@customer_admin, @acme_playbook)
    assert_not policy.approve?, 'Customer should not be able to re-approve approved playbook'
  end

  test 'approve? returns false for customer on archived playbook' do
    # WHY: Cannot approve archived playbooks
    @acme_playbook.update!(status: 'archived')
    policy = PlaybookPolicy.new(@customer_admin, @acme_playbook)
    assert_not policy.approve?, 'Customer should not be able to approve archived playbook'
  end

  # request_changes? tests
  test 'request_changes? returns true for customer on draft playbook' do
    Current.organization = organizations(:acme)
    # WHY: Customers can request changes on draft playbooks
    @acme_playbook.update!(status: 'draft')
    policy = PlaybookPolicy.new(@customer_admin, @acme_playbook)
    assert policy.request_changes?, 'Customer should be able to request changes on draft'
  end

  test 'request_changes? returns true for customer on approved playbook' do
    Current.organization = organizations(:acme)
    # WHY: Customers can request changes even on approved playbooks
    # if they discover issues later
    @acme_playbook.update!(status: 'approved', approved_at: Time.current, approved_by: @customer_admin)
    policy = PlaybookPolicy.new(@customer_admin, @acme_playbook)
    assert policy.request_changes?, 'Customer should be able to request changes on approved'
  end

  test 'request_changes? returns false for amplifa_admin' do
    # WHY: Only customers can request changes - admins directly edit
    @acme_playbook.update!(status: 'draft')
    policy = PlaybookPolicy.new(@amplifa_admin, @acme_playbook)
    assert_not policy.request_changes?, 'Amplifa admin should not request changes'
  end

  test 'request_changes? returns true for customer on changes_requested playbook' do
    Current.organization = organizations(:acme)
    @acme_playbook.update!(status: 'changes_requested')
    policy = PlaybookPolicy.new(@customer_admin, @acme_playbook)
    assert policy.request_changes?, 'Customer should be able to submit additional feedback'
  end

  # move_to_draft? tests
  test 'move_to_draft? returns true for amplifa_admin' do
    # WHY: Only Amplifa admins can move playbooks back to draft after making edits
    policy = PlaybookPolicy.new(@amplifa_admin, @acme_playbook)
    assert policy.move_to_draft?, 'Amplifa admin should be able to move to draft'
  end

  test 'move_to_draft? returns false for customer_admin' do
    # WHY: Customers cannot move playbooks to draft - only admins
    policy = PlaybookPolicy.new(@customer_admin, @acme_playbook)
    assert_not policy.move_to_draft?, 'Customer admin should not be able to move to draft'
  end

  # archive? tests
  test 'archive? returns true for amplifa_admin' do
    # WHY: Amplifa admins can archive any playbook
    policy = PlaybookPolicy.new(@amplifa_admin, @acme_playbook)
    assert policy.archive?, 'Amplifa admin should be able to archive playbooks'
  end

  test 'archive? returns true for customer_admin in their org' do
    # WHY: Customer admins can archive playbooks in their organization
    Current.organization = organizations(:acme)
    Current.organization_membership = organization_memberships(:customer_admin_acme)
    policy = PlaybookPolicy.new(@customer_admin, @acme_playbook)
    assert policy.archive?, "Customer admin should be able to archive their org's playbook"
  end

  test 'archive? returns false for customer_user' do
    # WHY: Regular customer users cannot archive playbooks
    policy = PlaybookPolicy.new(@customer_user, @acme_playbook)
    assert_not policy.archive?, 'Customer user should not be able to archive playbooks'
  end

  # upload_file? tests
  test 'upload_file? follows same rules as update?' do
    Current.organization = organizations(:acme)
    # WHY: File upload permissions should match editing permissions

    # Admin can always upload
    policy = PlaybookPolicy.new(@amplifa_admin, @acme_playbook)
    assert policy.upload_file?, 'Amplifa admin should be able to upload files'

    # Customer can upload on draft
    @acme_playbook.update!(status: 'draft')
    policy = PlaybookPolicy.new(@customer_admin, @acme_playbook)
    assert policy.upload_file?, 'Customer should be able to upload files on draft'

    # Customer cannot upload on approved
    @acme_playbook.update!(status: 'approved', approved_at: Time.current, approved_by: @customer_admin)
    policy = PlaybookPolicy.new(@customer_admin, @acme_playbook)
    assert_not policy.upload_file?, 'Customer should not be able to upload files on approved'
  end

  # Scope tests
  test 'Scope returns all playbooks for amplifa_admin' do
    # WHY: Amplifa admins need to see all playbooks across all organizations
    # for platform management and customer support
    scope = PlaybookPolicy::Scope.new(@amplifa_admin, Playbook).resolve
    assert_equal Playbook.count, scope.count, 'Amplifa admin should see all playbooks'
  end

  test 'Scope returns only own org playbooks for customer_admin' do
    Current.organization = organizations(:acme)
    # WHY: Customer admins should only see playbooks from their own organization
    # for privacy and security
    scope = PlaybookPolicy::Scope.new(@customer_admin, Playbook).resolve
    expected_playbooks = Playbook.where(organization: @customer_admin.organization)
    assert_equal expected_playbooks.count, scope.count
    assert_equal expected_playbooks.pluck(:id).sort, scope.pluck(:id).sort
  end

  test 'Scope returns only own org playbooks for customer_user' do
    Current.organization = organizations(:acme)
    # WHY: Customer users should only see playbooks from their own organization
    scope = PlaybookPolicy::Scope.new(@customer_user, Playbook).resolve
    expected_playbooks = Playbook.where(organization: @customer_user.organization)
    assert_equal expected_playbooks.count, scope.count
    assert_equal expected_playbooks.pluck(:id).sort, scope.pluck(:id).sort
  end
end
