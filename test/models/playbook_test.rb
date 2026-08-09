require 'test_helper'

class PlaybookTest < ActiveSupport::TestCase
  # WHY: Playbooks must belong to an organization (multi-tenant architecture)
  # This ensures proper data isolation between customers
  test 'requires organization' do
    playbook = Playbook.new(
      product: { 'name' => 'Test Product', 'description' => 'Test', 'metadata' => {} },
      personae: [{ id: '1', name: 'Test', title: 'Manager', order: 1 }],
      use_cases: [{ id: '1', title: 'Test', description: 'Test', order: 1 }]
    )
    assert_not playbook.valid?
    assert_includes playbook.errors[:organization], 'must exist'
  end

  # WHY: Playbooks must have product information (core business logic)
  # Each playbook is specific to one product/service, stored as JSONB
  test 'requires product' do
    # WHY: Product is required for every playbook to identify what is being sold
    org = organizations(:acme)
    playbook = Playbook.new(
      organization: org,
      personae: [{ id: '1', name: 'Test', title: 'Manager', order: 1 }],
      use_cases: [{ id: '1', title: 'Test', description: 'Test', order: 1 }]
    )
    assert_not playbook.valid?
    assert_includes playbook.errors[:product], "can't be blank"
  end

  # WHY: STATUSES constant is used by controllers to populate dropdowns
  # Without this constant, Admin::Organizations::PlaybooksController#index would crash
  test 'STATUSES constant includes all valid statuses' do
    expected_statuses = %w[draft changes_requested approved archived]
    assert_equal expected_statuses, Playbook::STATUSES
    assert Playbook::STATUSES.frozen?, 'STATUSES should be frozen'
  end

  # WHY: Status must be valid for workflow to function correctly
  # Invalid statuses would break the approval workflow UI
  test 'validates status inclusion' do
    playbook = create_valid_playbook
    playbook.status = 'invalid_status'
    assert_not playbook.valid?
    assert_includes playbook.errors[:status], 'is not included in the list'
  end

  # Invalid languages would break the UI language detection
  test 'validates language inclusion' do
    playbook = create_valid_playbook
    playbook.language = 'xx'
    assert_not playbook.valid?
    assert_includes playbook.errors[:language], 'is not included in the list'
  end

  test 'accepts expanded supported language set' do
    playbook = create_valid_playbook
    playbook.language = 'pt-BR'
    assert playbook.valid?
  end

  test 'allows long value_proposition values' do
    playbook = create_valid_playbook
    playbook.value_proposition = 'A' * 6001
    assert playbook.valid?
  end

  # WHY: Personae array cannot be empty - at least one persona is required
  # Playbook is meaningless without target personas
  test 'requires personae to be present' do
    playbook = create_valid_playbook
    playbook.personae = []
    assert_not playbook.valid?
    assert_includes playbook.errors[:personae], "can't be blank"
  end

  # WHY: Use cases array cannot be empty - at least one use case is required
  # Playbook is meaningless without use cases
  test 'requires use_cases to be present' do
    playbook = create_valid_playbook
    playbook.use_cases = []
    assert_not playbook.valid?
    assert_includes playbook.errors[:use_cases], "can't be blank"
  end

  # WHY: Persona objects must have required fields for UI to render correctly
  # Missing fields would cause UI crashes and incomplete data
  test 'validates personae structure' do
    playbook = create_valid_playbook

    # Missing 'id'
    playbook.personae = [{ name: 'Test', title: 'Manager', order: 1 }]
    assert_not playbook.valid?
    assert_includes playbook.errors[:personae], "Item 0 missing 'id'"

    # Missing 'name'
    playbook.personae = [{ id: '1', title: 'Manager', order: 1 }]
    assert_not playbook.valid?
    assert_includes playbook.errors[:personae], "Item 0 missing 'name'"

    # Missing 'title'
    playbook.personae = [{ id: '1', name: 'Test', order: 1 }]
    assert_not playbook.valid?
    assert_includes playbook.errors[:personae], "Item 0 missing 'title'"

    # Missing 'order'
    playbook.personae = [{ id: '1', name: 'Test', title: 'Manager' }]
    assert_not playbook.valid?
    assert_includes playbook.errors[:personae], "Item 0 missing 'order'"
  end

  # WHY: Use case objects must have required fields for UI to render correctly
  # Missing fields would cause UI crashes and incomplete data
  test 'validates use_cases structure' do
    playbook = create_valid_playbook

    # Missing 'id'
    playbook.use_cases = [{ title: 'Test', description: 'Desc', order: 1 }]
    assert_not playbook.valid?
    assert_includes playbook.errors[:use_cases], "Item 0 missing 'id'"

    # Missing 'title'
    playbook.use_cases = [{ id: '1', description: 'Desc', order: 1 }]
    assert_not playbook.valid?
    assert_includes playbook.errors[:use_cases], "Item 0 missing 'title'"

    # Missing 'description'
    playbook.use_cases = [{ id: '1', title: 'Test', order: 1 }]
    assert_not playbook.valid?
    assert_includes playbook.errors[:use_cases], "Item 0 missing 'description'"

    # Missing 'order'
    playbook.use_cases = [{ id: '1', title: 'Test', description: 'Desc' }]
    assert_not playbook.valid?
    assert_includes playbook.errors[:use_cases], "Item 0 missing 'order'"
  end

  # WHY: References with file uploads must have file metadata
  # This ensures proper file tracking and UI display
  test 'validates references with file_url have file_name and file_size' do
    playbook = create_valid_playbook
    playbook.references = [{
      id: '1',
      customer_name: 'Acme Corp',
      description: 'Great customer',
      order: 1,
      file_url: 'https://example.com/file.pdf'
      # Missing file_name and file_size
    }]

    assert_not playbook.valid?
    assert_includes playbook.errors[:references], 'Item 0 with file_url must have file_name'
    assert_includes playbook.errors[:references], 'Item 0 with file_url must have file_size'
  end

  # WHY: Proof points with file uploads must have file metadata
  # This ensures proper file tracking and UI display
  test 'validates proof_points with file_url have file_name and file_size' do
    playbook = create_valid_playbook
    playbook.proof_points = [{
      id: '1',
      claim: '50% increase in sales',
      description: 'Measured over 6 months',
      order: 1,
      file_url: 'https://example.com/proof.pdf'
      # Missing file_name and file_size
    }]

    assert_not playbook.valid?
    assert_includes playbook.errors[:proof_points], 'Item 0 with file_url must have file_name'
    assert_includes playbook.errors[:proof_points], 'Item 0 with file_url must have file_size'
  end

  # WHY: Approved playbooks must have approval metadata for audit trail
  # This ensures we always know who approved and when
  test 'approved status requires approved_at and approved_by_id' do
    playbook = create_valid_playbook
    playbook.status = 'approved'
    assert_not playbook.valid?
    assert_includes playbook.errors[:base], 'Approved playbooks must have approved_at and approved_by_id'

    # With both fields set, it's valid
    playbook.approved_at = Time.current
    playbook.approved_by_id = accounts(:amplifa_admin).id
    assert playbook.valid?
  end

  # WHY: State check methods are used throughout UI to show/hide actions
  # We test them to ensure correct UI behavior
  test 'state check methods return correct values' do
    playbook = create_valid_playbook

    playbook.status = 'draft'
    assert playbook.draft?
    assert_not playbook.changes_requested?
    assert_not playbook.approved?
    assert_not playbook.archived?

    playbook.status = 'changes_requested'
    assert_not playbook.draft?
    assert playbook.changes_requested?
    assert_not playbook.approved?
    assert_not playbook.archived?

    playbook.status = 'approved'
    playbook.approved_at = Time.current
    playbook.approved_by_id = accounts(:amplifa_admin).id
    assert_not playbook.draft?
    assert_not playbook.changes_requested?
    assert playbook.approved?
    assert_not playbook.archived?

    playbook.status = 'archived'
    assert_not playbook.draft?
    assert_not playbook.changes_requested?
    assert_not playbook.approved?
    assert playbook.archived?
  end

  # WHY: Permission checks control which actions users can take
  # We test them to ensure proper authorization in controllers
  test 'can_edit? only true for draft and changes_requested' do
    playbook = create_valid_playbook

    playbook.status = 'draft'
    assert playbook.can_edit?

    playbook.status = 'changes_requested'
    assert playbook.can_edit?

    playbook.status = 'approved'
    playbook.approved_at = Time.current
    playbook.approved_by_id = accounts(:amplifa_admin).id
    assert_not playbook.can_edit?

    playbook.status = 'archived'
    assert_not playbook.can_edit?
  end

  # WHY: approve! transition sets all required fields and changes status
  # We test it to ensure approval workflow works correctly
  test 'approve! sets status, approved_at, and approved_by_id' do
    playbook = create_valid_playbook!
    approver = accounts(:customer_admin)

    assert_nil playbook.approved_at
    assert_nil playbook.approved_by_id

    playbook.approve!(approver)

    assert_equal 'approved', playbook.status
    assert_not_nil playbook.approved_at
    assert_equal approver.id, playbook.approved_by_id
  end

  # WHY: request_changes! transition clears approval metadata
  # We test it to ensure workflow state is properly reset
  test 'request_changes! sets status and clears approval metadata' do
    playbook = create_valid_playbook!
    approver = accounts(:customer_admin)
    playbook.approve!(approver)

    assert_equal 'approved', playbook.status
    assert_not_nil playbook.approved_at

    playbook.request_changes!

    assert_equal 'changes_requested', playbook.status
    assert_nil playbook.approved_at
    assert_nil playbook.approved_by_id
  end

  # WHY: Scopes are used for filtering in UI lists
  # We test them to ensure proper data isolation and filtering
  test 'scopes filter playbooks correctly' do
    org1 = organizations(:acme)
    org2 = organizations(:techcorp)
    # Product is now JSONB, no longer a separate model

    playbook1 = create_valid_playbook!(organization: org1, status: 'draft')
    # For approved status, need to set metadata
    playbook2 = Playbook.create!(
      organization: org2,
      product: { 'name' => 'Analytics Suite', 'description' => 'Test', 'metadata' => {} },
      personae: [{ id: '1', name: 'Test', title: 'Manager', order: 1 }],
      use_cases: [{ id: '1', title: 'Test', description: 'Test', order: 1 }],
      status: 'approved',
      approved_at: Time.current,
      approved_by_id: accounts(:amplifa_admin).id
    )

    # for_organization scope
    assert_includes Playbook.for_organization(org1), playbook1
    assert_not_includes Playbook.for_organization(org1), playbook2

    # by_status scope
    assert_includes Playbook.by_status('draft'), playbook1
    assert_not_includes Playbook.by_status('draft'), playbook2
  end

  # WHY: Helper methods are used in UI to display counts and badges
  # We test them to ensure accurate display
  test 'helper methods return correct values' do
    playbook = create_valid_playbook!(
      personae: [
        { id: '1', name: 'Persona 1', title: 'Title 1', order: 1 },
        { id: '2', name: 'Persona 2', title: 'Title 2', order: 2 }
      ],
      use_cases: [
        { id: '1', title: 'Use Case 1', description: 'Desc 1', order: 1 }
      ],
      references: [
        { id: '1', customer_name: 'Customer 1', description: 'Desc 1', order: 1, file_url: 'http://example.com/file.pdf', file_name: 'file.pdf', file_size: 1000 }
      ],
      proof_points: [
        { id: '1', claim: 'Claim 1', description: 'Desc 1', order: 1 }
      ]
    )

    assert_equal 2, playbook.persona_count
    assert_equal 1, playbook.use_case_count
    assert_equal 1, playbook.reference_count
    assert_equal 1, playbook.proof_point_count
    assert playbook.has_file_attachments?
    assert_equal 1, playbook.file_attachment_count
  end

  private

  def create_valid_playbook(attrs = {})
    defaults = {
      organization: organizations(:acme),
      product: { 'name' => 'Test Product', 'description' => 'Test Description', 'metadata' => {} },
      personae: [{ id: '1', name: 'Test Persona', title: 'Manager', order: 1 }],
      use_cases: [{ id: '1', title: 'Test Use Case', description: 'Description', order: 1 }],
      references: [],
      proof_points: []
    }
    Playbook.new(defaults.merge(attrs))
  end

  def create_valid_playbook!(attrs = {})
    playbook = create_valid_playbook(attrs)
    playbook.save!
    playbook
  end
end
