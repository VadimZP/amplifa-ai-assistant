require 'test_helper'

class PlaybookCommentTest < ActiveSupport::TestCase
  # WHY: Comments must belong to a playbook (core relationship)
  # Comments without a playbook context are meaningless
  test 'requires playbook' do
    account = accounts(:customer_admin)
    comment = PlaybookComment.new(account: account, body: 'Test comment')
    assert_not comment.valid?
    assert_includes comment.errors[:playbook], 'must exist'
  end

  # WHY: Comments must have an author (audit trail)
  # We need to know who made each comment for accountability
  test 'requires account' do
    playbook = create_test_playbook
    comment = PlaybookComment.new(playbook: playbook, body: 'Test comment')
    assert_not comment.valid?
    assert_includes comment.errors[:account], 'must exist'
  end

  # WHY: Empty comments are meaningless and clutter the UI
  # We require actual content in comments
  test 'requires body' do
    playbook = create_test_playbook
    account = accounts(:customer_admin)
    comment = PlaybookComment.new(playbook: playbook, account: account)
    assert_not comment.valid?
    assert_includes comment.errors[:body], "can't be blank"
  end

  # WHY: Body must have minimum length to prevent accidental submissions
  # Maximum length prevents database issues and ensures reasonable comment size
  test 'validates body length' do
    playbook = create_test_playbook
    account = accounts(:customer_admin)

    # Too long
    comment = PlaybookComment.new(playbook: playbook, account: account,
                                  body: 'A' * (PlaybookComment::BODY_MAX_LENGTH + 1))
    assert_not comment.valid?
    assert_includes comment.errors[:body], "is too long (maximum is #{PlaybookComment::BODY_MAX_LENGTH} characters)"

    # Just right
    comment = PlaybookComment.new(playbook: playbook, account: account, body: 'A')
    assert comment.valid?

    comment = PlaybookComment.new(playbook: playbook, account: account,
                                  body: 'A' * PlaybookComment::BODY_MAX_LENGTH)
    assert comment.valid?
  end

  # WHY: comment_type must be valid for filtering and UI display
  # Invalid types would break the comment filtering logic
  test 'validates comment_type inclusion' do
    playbook = create_test_playbook
    account = accounts(:customer_admin)

    comment = PlaybookComment.new(playbook: playbook, account: account, body: 'Test', comment_type: 'invalid')
    assert_not comment.valid?
    assert_includes comment.errors[:comment_type], 'is not included in the list'

    # Valid types
    %w[general request_changes approval].each do |type|
      comment = PlaybookComment.new(playbook: playbook, account: account, body: 'Test', comment_type: type)
      assert comment.valid?, "Should be valid with comment_type: #{type}"
    end
  end

  test 'validates feedback context tab when context is present' do
    playbook = create_test_playbook
    account = accounts(:customer_admin)

    comment = PlaybookComment.new(
      playbook: playbook,
      account: account,
      body: 'Test',
      feedback_context: { tab: 'not_a_real_tab' }
    )

    assert_not comment.valid?
    assert_includes comment.errors[:feedback_context], 'must include a valid tab'
  end

  # WHY: Type check methods are used in UI to style comments differently
  # We test them to ensure proper UI rendering
  test 'type check methods return correct values' do
    playbook = create_test_playbook
    account = accounts(:customer_admin)

    comment = PlaybookComment.create!(playbook: playbook, account: account, body: 'Test', comment_type: 'general')
    assert comment.general?
    assert_not comment.request_changes?
    assert_not comment.approval?

    comment.update!(comment_type: 'request_changes')
    assert_not comment.general?
    assert comment.request_changes?
    assert_not comment.approval?

    comment.update!(comment_type: 'approval')
    assert_not comment.general?
    assert_not comment.request_changes?
    assert comment.approval?
  end

  # WHY: author_name method is used throughout UI to display comment authors
  # We test it to ensure it returns the expected format
  test 'author_name returns full_name from account' do
    playbook = create_test_playbook
    account = accounts(:customer_admin)
    comment = PlaybookComment.create!(playbook: playbook, account: account, body: 'Test')

    assert_equal account.full_name, comment.author_name
  end

  # WHY: Scopes are used for filtering comments in UI
  # We test them to ensure proper filtering and ordering
  test 'for_playbook scope returns only comments for that playbook' do
    playbook1 = create_test_playbook
    playbook2 = create_test_playbook
    account = accounts(:customer_admin)

    comment1 = PlaybookComment.create!(playbook: playbook1, account: account, body: 'Comment 1')
    comment2 = PlaybookComment.create!(playbook: playbook2, account: account, body: 'Comment 2')

    comments = PlaybookComment.for_playbook(playbook1)

    assert_includes comments, comment1
    assert_not_includes comments, comment2
  end

  # WHY: Chronological ordering is default for comment display
  # We test it to ensure comments appear in the order they were created
  test 'chronological scope orders by created_at ascending' do
    playbook = create_test_playbook
    account = accounts(:customer_admin)

    # Create comments in specific order
    comment1 = PlaybookComment.create!(playbook: playbook, account: account, body: 'First')
    sleep 0.01 # Ensure different timestamps
    comment2 = PlaybookComment.create!(playbook: playbook, account: account, body: 'Second')
    sleep 0.01
    comment3 = PlaybookComment.create!(playbook: playbook, account: account, body: 'Third')

    comments = PlaybookComment.chronological.to_a

    assert_equal [comment1, comment2, comment3], comments
  end

  # WHY: Recent ordering is used for admin dashboards showing latest activity
  # We test it to ensure newest comments appear first
  test 'recent scope orders by created_at descending' do
    playbook = create_test_playbook
    account = accounts(:customer_admin)

    comment1 = PlaybookComment.create!(playbook: playbook, account: account, body: 'First')
    sleep 0.01
    comment2 = PlaybookComment.create!(playbook: playbook, account: account, body: 'Second')
    sleep 0.01
    comment3 = PlaybookComment.create!(playbook: playbook, account: account, body: 'Third')

    comments = PlaybookComment.recent.to_a

    assert_equal [comment3, comment2, comment1], comments
  end

  # WHY: by_type scope is used to filter comments by type in UI
  # We test it to ensure proper filtering
  test 'by_type scope filters comments correctly' do
    playbook = create_test_playbook
    account = accounts(:customer_admin)

    general_comment = PlaybookComment.create!(playbook: playbook, account: account, body: 'General',
                                              comment_type: 'general')
    request_comment = PlaybookComment.create!(playbook: playbook, account: account, body: 'Request',
                                              comment_type: 'request_changes')

    general_comments = PlaybookComment.by_type('general')

    assert_includes general_comments, general_comment
    assert_not_includes general_comments, request_comment
  end

  # WHY: status_related scope is used to show only workflow-related comments
  # We test it to ensure it excludes general comments
  test 'status_related scope includes only request_changes and approval' do
    playbook = create_test_playbook
    account = accounts(:customer_admin)

    general_comment = PlaybookComment.create!(playbook: playbook, account: account, body: 'General',
                                              comment_type: 'general')
    request_comment = PlaybookComment.create!(playbook: playbook, account: account, body: 'Request',
                                              comment_type: 'request_changes')
    approval_comment = PlaybookComment.create!(playbook: playbook, account: account, body: 'Approval',
                                               comment_type: 'approval')

    status_comments = PlaybookComment.status_related

    assert_not_includes status_comments, general_comment
    assert_includes status_comments, request_comment
    assert_includes status_comments, approval_comment
  end

  private

  def create_test_playbook
    org = organizations(:acme)
    Playbook.create!(
      organization: org,
      product: { 'name' => 'Test Product', 'description' => 'Test', 'metadata' => {} },
      personae: [{ id: '1', name: 'Test', title: 'Manager', order: 1 }],
      use_cases: [{ id: '1', title: 'Test', description: 'Test', order: 1 }]
    )
  end
end
