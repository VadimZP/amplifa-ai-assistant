require 'test_helper'

class MeetingPolicyRequestRemovalTest < ActiveSupport::TestCase
  def setup
    @amplifa_admin = accounts(:amplifa_admin)
    @customer_admin = accounts(:customer_admin)
    @customer_user = accounts(:customer_user)
    @growth_lab_admin = accounts(:growth_lab_admin)
    @acme_meeting = meetings(:scheduled_discovery)
  end

  def teardown
    Current.reset
  end

  test 'request_removal? allows admin and same-organization customer accounts' do
    Current.organization = organizations(:acme)
    assert MeetingPolicy.new(@amplifa_admin, @acme_meeting).request_removal?
    assert MeetingPolicy.new(@customer_admin, @acme_meeting).request_removal?
    assert MeetingPolicy.new(@customer_user, @acme_meeting).request_removal?
  end

  test 'request_removal? denies customers outside organization' do
    assert_not MeetingPolicy.new(@growth_lab_admin, @acme_meeting).request_removal?
  end
end
