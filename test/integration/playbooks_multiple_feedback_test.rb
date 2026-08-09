require 'test_helper'

class PlaybooksMultipleFeedbackTest < ActionDispatch::IntegrationTest
  def setup
    @customer_admin = accounts(:customer_admin)
    @playbook = playbooks(:draft_playbook)
  end

  test 'customer can request changes multiple times without reloading' do
    sign_in_as(@customer_admin)

    assert_difference 'PlaybookComment.count', 2 do
      post request_changes_playbook_path(@playbook), params: {
        comment: 'Please expand examples'
      }
      assert_redirected_to playbook_path(@playbook)

      post request_changes_playbook_path(@playbook), params: {
        comment: 'Also add an objection-handling section'
      }
    end

    assert_redirected_to playbook_path(@playbook)

    @playbook.reload
    assert_equal 'changes_requested', @playbook.status

    request_comments = @playbook.playbook_comments.where(comment_type: 'request_changes').order(:created_at)
    assert_operator request_comments.count, :>=, 2
    assert_equal 'Please expand examples', request_comments[-2].body
    assert_equal 'Also add an objection-handling section', request_comments[-1].body
  end

  private

  def sign_in_as(account)
    password = account.amplifa_admin? ? 'password123' : 'password'
    post login_path, params: {
      email: account.email,
      password: password
    }
  end
end
