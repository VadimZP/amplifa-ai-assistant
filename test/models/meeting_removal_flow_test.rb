require 'test_helper'

class MeetingRemovalFlowTest < ActiveSupport::TestCase
  test 'decline_pending_removal! creates comment and resets status to scheduling' do
    meeting = meetings(:scheduled_discovery)
    admin = accounts(:amplifa_admin)

    meeting.mark_pending_removal!

    assert_difference 'MeetingDeclinedComment.count', 1 do
      comment = meeting.decline_pending_removal!(account: admin,
                                                 comment_body: 'Keep this meeting and continue scheduling.')

      assert_equal 'Keep this meeting and continue scheduling.', comment.body
      assert_equal admin, comment.account
    end

    assert_equal 'scheduling', meeting.reload.status
  end

  test 'removal_requestable? only allows active meeting states' do
    meeting = meetings(:scheduled_discovery)

    meeting.status = 'scheduled'
    assert meeting.removal_requestable?

    meeting.status = 'scheduling'
    assert meeting.removal_requestable?

    meeting.status = 'rescheduled'
    assert meeting.removal_requestable?

    meeting.status = 'pending_removal'
    assert_not meeting.removal_requestable?

    meeting.status = 'completed'
    assert_not meeting.removal_requestable?
  end
end
