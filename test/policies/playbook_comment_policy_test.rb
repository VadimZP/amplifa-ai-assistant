require "test_helper"

class PlaybookCommentPolicyTest < ActiveSupport::TestCase
  def setup
    @amplifa_admin = accounts(:amplifa_admin)
    @customer_admin = accounts(:customer_admin)
    @customer_user = accounts(:customer_user)
    @acme_playbook = playbooks(:draft_playbook)

    # Create test comments
    @admin_comment = PlaybookComment.create!(
      playbook: @acme_playbook,
      account: @amplifa_admin,
      body: "Admin comment",
      comment_type: 'general'
    )

    @customer_comment = PlaybookComment.create!(
      playbook: @acme_playbook,
      account: @customer_admin,
      body: "Customer comment",
      comment_type: 'general'
    )
  end

  def teardown
    Current.reset
  end

  # index? tests
  test "index? returns true for amplifa_admin viewing any playbook comments" do
    # WHY: Amplifa admins can view comments on any playbook
    # to manage the platform and support customers
    policy = PlaybookCommentPolicy.new(@amplifa_admin, @admin_comment)
    assert policy.index?, "Amplifa admin should be able to view comments"
  end

  test "index? returns true for customer viewing own org playbook comments" do
    Current.organization = organizations(:acme)
    # WHY: Customers can view comments on playbooks in their organization
    # to participate in the review process
    policy = PlaybookCommentPolicy.new(@customer_admin, @customer_comment)
    assert policy.index?, "Customer should be able to view their org's comments"
  end

  test "index? returns false for customer viewing other org playbook comments" do
    # WHY: Customers should not see comments on playbooks from other organizations
    # to maintain privacy

    # Create a playbook for techcorp
    techcorp = organizations(:techcorp)
    # Product is now JSONB within playbook
    techcorp_playbook = Playbook.create!(
      organization: techcorp,
      product: { "name" => "Analytics Suite", "description" => "Test", "metadata" => {} },
      status: 'draft',
      language: 'en',
      personae: [{id: "1", name: "Test", title: "Manager", order: 1, pain_points: ["test"]}],
      use_cases: [{id: "1", title: "Test", description: "Test case", order: 1}]
    )

    techcorp_comment = PlaybookComment.create!(
      playbook: techcorp_playbook,
      account: @amplifa_admin,
      body: "Techcorp comment",
      comment_type: 'general'
    )

    policy = PlaybookCommentPolicy.new(@customer_admin, techcorp_comment)
    assert_not policy.index?, "Customer should not view other org's comments"
  end

  # show? tests
  test "show? returns true for amplifa_admin" do
    # WHY: Admins can view any comment
    policy = PlaybookCommentPolicy.new(@amplifa_admin, @customer_comment)
    assert policy.show?, "Amplifa admin should be able to view comments"
  end

  test "show? returns true for customer viewing own org comment" do
    Current.organization = organizations(:acme)
    # WHY: Customers can view comments on their organization's playbooks
    policy = PlaybookCommentPolicy.new(@customer_admin, @customer_comment)
    assert policy.show?, "Customer should be able to view their org's comments"
  end

  # create? tests
  test "create? returns true for amplifa_admin on any playbook" do
    # WHY: Admins can comment on any playbook to provide guidance
    new_comment = PlaybookComment.new(playbook: @acme_playbook, account: @amplifa_admin)
    policy = PlaybookCommentPolicy.new(@amplifa_admin, new_comment)
    assert policy.create?, "Amplifa admin should be able to create comments"
  end

  test "create? returns true for customer on own org playbook" do
    Current.organization = organizations(:acme)
    # WHY: Anyone in the organization can comment to participate in discussion
    new_comment = PlaybookComment.new(playbook: @acme_playbook, account: @customer_admin)
    policy = PlaybookCommentPolicy.new(@customer_admin, new_comment)
    assert policy.create?, "Customer should be able to create comments on their org's playbook"
  end

  test "create? returns true for customer_user on own org playbook" do
    Current.organization = organizations(:acme)
    # WHY: Regular users can also comment to provide feedback
    new_comment = PlaybookComment.new(playbook: @acme_playbook, account: @customer_user)
    policy = PlaybookCommentPolicy.new(@customer_user, new_comment)
    assert policy.create?, "Customer user should be able to create comments"
  end

  test "create? returns false for customer on other org playbook" do
    # WHY: Customers cannot comment on other organizations' playbooks

    # Create a playbook for techcorp
    techcorp = organizations(:techcorp)
    # Product is now JSONB within playbook
    techcorp_playbook = Playbook.create!(
      organization: techcorp,
      product: { "name" => "Analytics Suite", "description" => "Test", "metadata" => {} },
      status: 'draft',
      language: 'en',
      personae: [{id: "1", name: "Test", title: "Manager", order: 1, pain_points: ["test"]}],
      use_cases: [{id: "1", title: "Test", description: "Test case", order: 1}]
    )

    new_comment = PlaybookComment.new(playbook: techcorp_playbook, account: @customer_admin)
    policy = PlaybookCommentPolicy.new(@customer_admin, new_comment)
    assert_not policy.create?, "Customer should not comment on other org's playbook"
  end

  # update? tests
  test "update? returns true for comment author" do
    # WHY: Only the comment author can edit their own comments
    policy = PlaybookCommentPolicy.new(@customer_admin, @customer_comment)
    assert policy.update?, "Comment author should be able to edit their comment"
  end

  test "update? returns false for different user" do
    # WHY: Users cannot edit comments written by others
    policy = PlaybookCommentPolicy.new(@customer_user, @customer_comment)
    assert_not policy.update?, "Different user should not edit others' comments"
  end

  test "update? returns false for admin editing customer comment" do
    # WHY: Even admins cannot edit comments written by customers
    # to preserve authenticity of the discussion
    policy = PlaybookCommentPolicy.new(@amplifa_admin, @customer_comment)
    assert_not policy.update?, "Admin should not edit customer comments"
  end

  # destroy? tests
  test "destroy? returns true for comment author" do
    # WHY: Comment authors can delete their own comments
    policy = PlaybookCommentPolicy.new(@customer_admin, @customer_comment)
    assert policy.destroy?, "Comment author should be able to delete their comment"
  end

  test "destroy? returns true for amplifa_admin on any comment" do
    # WHY: Admins can delete any comment for moderation purposes
    policy = PlaybookCommentPolicy.new(@amplifa_admin, @customer_comment)
    assert policy.destroy?, "Amplifa admin should be able to delete any comment"
  end

  test "destroy? returns false for different customer" do
    # WHY: Customers cannot delete comments written by others
    policy = PlaybookCommentPolicy.new(@customer_user, @customer_comment)
    assert_not policy.destroy?, "Different user should not delete others' comments"
  end

  # Scope tests
  test "Scope returns all comments for amplifa_admin" do
    # WHY: Admins can see all comments across all playbooks
    scope = PlaybookCommentPolicy::Scope.new(@amplifa_admin, PlaybookComment).resolve
    assert_equal PlaybookComment.count, scope.count, "Amplifa admin should see all comments"
  end

  test "Scope returns only own org comments for customer" do
    Current.organization = organizations(:acme)
    # WHY: Customers should only see comments on playbooks in their organization

    # Create a comment for techcorp
    techcorp = organizations(:techcorp)
    # Product is now JSONB within playbook
    techcorp_playbook = Playbook.create!(
      organization: techcorp,
      product: { "name" => "Analytics Suite", "description" => "Test", "metadata" => {} },
      status: 'draft',
      language: 'en',
      personae: [{id: "1", name: "Test", title: "Manager", order: 1, pain_points: ["test"]}],
      use_cases: [{id: "1", title: "Test", description: "Test case", order: 1}]
    )

    PlaybookComment.create!(
      playbook: techcorp_playbook,
      account: @amplifa_admin,
      body: "Techcorp comment",
      comment_type: 'general'
    )

    scope = PlaybookCommentPolicy::Scope.new(@customer_admin, PlaybookComment).resolve

    # Should only see comments on acme playbooks
    acme_org = @customer_admin.organization
    expected_comments = PlaybookComment.joins(:playbook).where(playbooks: { organization_id: acme_org.id })

    assert_equal expected_comments.count, scope.count
    assert_equal expected_comments.pluck(:id).sort, scope.pluck(:id).sort
  end
end
