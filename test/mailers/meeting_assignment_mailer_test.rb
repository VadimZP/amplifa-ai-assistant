require 'test_helper'

class MeetingAssignmentMailerTest < ActionMailer::TestCase
  test 'assignment_notification sends meeting details to assignee' do
    meeting = meetings(:scheduled_discovery)
    assignee = accounts(:customer_user)
    assigned_by = accounts(:customer_admin)

    email = MeetingAssignmentMailer.with(
      meeting: meeting,
      assignee: assignee,
      assigned_by: assigned_by
    ).assignment_notification

    assert_emails 1 do
      email.deliver_now
    end

    assert_equal [assignee.email], email.to
    assert_includes email.subject, meeting.lead.full_name
    assert_includes email.body.encoded, assigned_by.full_name
    assert_includes email.body.encoded, meeting.agent.name
    assert_includes email.body.encoded, meeting.location
  end
end
