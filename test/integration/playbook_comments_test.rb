require 'test_helper'

class PlaybookCommentsTest < ActionDispatch::IntegrationTest
  # WHY: We're testing the playbook commenting system which allows both
  # customers and admins to discuss playbooks during the review process.
  # Comments are critical for communication between customers and admins.

  def setup
    @customer_admin = accounts(:customer_admin)
    @customer_user = accounts(:customer_user)
    @amplifa_admin = accounts(:amplifa_admin)

    @org = organizations(:acme)
    @playbook = playbooks(:draft_playbook)

    @other_org = organizations(:beta)
    @other_playbook = playbooks(:other_org_playbook)
  end

  # ========================================
  # CREATE ACTION TESTS
  # ========================================

  test 'customer admin can create comment on playbook' do
    # WHY: Customers should be able to add comments for general discussion
    # or to provide feedback to admins
    sign_in_as(@customer_admin)

    assert_difference 'PlaybookComment.count', 1 do
      post "/playbooks/#{@playbook.id}/comments", params: {
        playbook_comment: {
          body: 'This looks great overall, but can we add more technical details?'
        }
      }
    end

    assert_redirected_to playbook_path(@playbook)
    assert_match(/comment added/i, flash[:notice])

    comment = PlaybookComment.last
    assert_equal @playbook.id, comment.playbook_id
    assert_equal @customer_admin.id, comment.account_id
    assert_equal 'This looks great overall, but can we add more technical details?', comment.body
    assert_equal 'general', comment.comment_type
  end

  test 'customer user can create comment on playbook' do
    # WHY: Regular customer users should also be able to comment
    sign_in_as(@customer_user)

    assert_difference 'PlaybookComment.count', 1 do
      post playbook_playbook_comments_path(@playbook.id), params: {
        playbook_comment: {
          body: 'Great work!'
        }
      }
    end

    assert_redirected_to playbook_path(@playbook)
  end

  test 'amplifa admin can create comment on any playbook' do
    # WHY: Admins should be able to comment on all playbooks to provide
    # updates or respond to customer feedback
    sign_in_as(@amplifa_admin)

    assert_difference 'PlaybookComment.count', 1 do
      post playbook_playbook_comments_path(@playbook.id), params: {
        playbook_comment: {
          body: 'Updated based on your feedback'
        }
      }
    end

    assert_redirected_to playbook_path(@playbook)
  end

  test 'create comment requires body' do
    # WHY: Empty comments provide no value and should be rejected
    sign_in_as(@customer_admin)

    assert_no_difference 'PlaybookComment.count' do
      post playbook_playbook_comments_path(@playbook.id), params: {
        playbook_comment: {
          body: ''
        }
      }
    end

    assert_redirected_to playbook_path(@playbook)
    assert_match(/can't be blank|too short/i, flash[:alert])
  end

  test 'create comment with excessively long body fails validation' do
    # WHY: Comments should have a reasonable length limit (8000 chars)
    # to prevent abuse and ensure readability
    sign_in_as(@customer_admin)

    long_text = 'a' * (PlaybookComment::BODY_MAX_LENGTH + 1)

    assert_no_difference 'PlaybookComment.count' do
      post playbook_playbook_comments_path(@playbook.id), params: {
        playbook_comment: {
          body: long_text
        }
      }
    end

    assert_redirected_to playbook_path(@playbook)
    assert_match(/too long/i, flash[:alert])
  end

  test "customer cannot comment on other organization's playbook" do
    # WHY: Critical security test - customers should only be able to
    # comment on playbooks belonging to their organization
    sign_in_as(@customer_admin)

    # WHY: Attempting to comment on other org's playbook gets unauthorized redirect
    post playbook_playbook_comments_path(@other_playbook.id), params: {
      playbook_comment: {
        body: 'This is not my playbook'
      }
    }

    assert_redirected_to root_path
    follow_redirect!
    assert_match(/not authorized/i, flash[:alert])
  end

  test 'unauthenticated user cannot create comment' do
    # WHY: All commenting requires authentication
    post playbook_playbook_comments_path(@playbook.id), params: {
      playbook_comment: {
        body: 'Anonymous comment'
      }
    }

    assert_response :redirect
    assert_redirected_to login_path
  end

  test 'creating comment sets correct default comment_type' do
    # WHY: Comments created through the general comment form should
    # default to 'general' type (not 'approval' or 'request_changes')
    sign_in_as(@customer_admin)

    post playbook_playbook_comments_path(@playbook.id), params: {
      playbook_comment: {
        body: 'General feedback'
      }
    }

    comment = PlaybookComment.last
    assert_equal 'general', comment.comment_type,
                 "Comment type should default to 'general'"
  end

  test 'creating comment stores feedback context' do
    sign_in_as(@customer_admin)
    message = generated_messages(:john_step_one_draft)
    lead = message.agent_lead.lead
    agent = message.agent_lead.agent

    assert_difference 'PlaybookComment.count', 1 do
      post playbook_playbook_comments_path(@playbook.id), params: {
        playbook_comment: {
          body: 'This sample message needs more detail',
          feedback_context: {
            tab: 'samples',
            lead_id: lead.id,
            lead_name: lead.display_name,
            message_id: message.id,
            step_label: message.sequence_step.display_name,
            step_position: message.sequence_step.position,
            agent_id: agent.id,
            agent_name: agent.name
          }
        }
      }
    end

    comment = PlaybookComment.last
    assert_equal 'samples', comment.feedback_context['tab']
    assert_equal lead.id, comment.feedback_context['lead_id']
    assert_equal message.id, comment.feedback_context['message_id']
    assert_equal agent.id, comment.feedback_context['agent_id']
  end

  # ========================================
  # EMAIL NOTIFICATION TESTS (DEFERRED)
  # ========================================

  # TODO: These tests are commented out because PlaybookMailer is not yet implemented
  # They should be uncommented and verified once Phase 9 (Mailers) is complete

  # test "creating comment sends email to admins when author is customer" do
  #   # WHY: When a customer comments, admins should be notified via email
  #   sign_in_as(@customer_admin)
  #
  #   assert_emails 1 do
  #     post playbook_playbook_comments_path(@playbook.id), params: {
  #       playbook_comment: {
  #         body: "Question for the admin team"
  #       }
  #     }
  #   end
  # end
  #
  # test "creating comment sends email to customers when author is admin" do
  #   # WHY: When an admin comments, all customer users should be notified
  #   sign_in_as(@amplifa_admin)
  #
  #   assert_emails 1 do
  #     post playbook_playbook_comments_path(@playbook.id), params: {
  #       playbook_comment: {
  #         body: "Response from admin"
  #       }
  #     }
  #   end
  # end

  # ========================================
  # AUTHORIZATION TESTS
  # ========================================

  test 'playbook comment policy allows customers to comment on own org playbooks' do
    # WHY: Verify the Pundit policy correctly authorizes commenting
    sign_in_as(@customer_admin)
    # AMP-435 §8: mirror the per-request workspace set_current_attributes resolves.
    Current.organization = @org

    comment = @playbook.playbook_comments.build(
      account: @customer_admin,
      body: 'Test'
    )

    assert Pundit.policy(@customer_admin, comment).create?,
           "Customer should be authorized to create comment on own org's playbook"
  end

  test 'playbook comment policy denies customers commenting on other org playbooks' do
    # WHY: Verify the Pundit policy correctly denies unauthorized access
    sign_in_as(@customer_admin)

    comment = @other_playbook.playbook_comments.build(
      account: @customer_admin,
      body: 'Test'
    )

    refute Pundit.policy(@customer_admin, comment).create?,
           "Customer should NOT be authorized to create comment on other org's playbook"
  end

  test 'playbook comment policy allows admins to comment on any playbook' do
    # WHY: Verify admins have global access to comment on any playbook
    sign_in_as(@amplifa_admin)

    comment = @playbook.playbook_comments.build(
      account: @amplifa_admin,
      body: 'Admin comment'
    )

    assert Pundit.policy(@amplifa_admin, comment).create?,
           'Admin should be authorized to create comment on any playbook'
  end

  private

  def sign_in_as(account)
    # WHY: Helper method to sign in as different users for testing
    # WHY: Amplifa admin uses different password in fixtures (password123 vs password)
    password = account.amplifa_admin? ? 'password123' : 'password'
    post login_path, params: {
      email: account.email,
      password: password
    }
  end
end
