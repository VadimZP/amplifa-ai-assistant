require 'test_helper'

class PlaybookRequestChangesTruncationTest < ActionDispatch::IntegrationTest
  def setup
    @customer_admin = accounts(:customer_admin)
    @playbook = playbooks(:draft_playbook)
  end

  test 'request changes truncates oversized feedback and saves it' do
    login_as(@customer_admin)

    long_comment = 'a' * (PlaybookComment::BODY_MAX_LENGTH + 1)

    assert_difference 'PlaybookComment.count', 1 do
      assert_difference 'AdminActivity.count', 1 do
        post request_changes_playbook_path(@playbook), params: {
          comment: long_comment
        }
      end
    end

    assert_redirected_to playbook_path(@playbook)
    assert_match(/changes requested/i, flash[:notice])

    @playbook.reload
    assert_equal 'changes_requested', @playbook.status
    assert_equal 'a' * PlaybookComment::BODY_MAX_LENGTH, @playbook.playbook_comments.last.body
  end
end
