require 'test_helper'

class PlaybookRequestChangesPolicyTest < ActiveSupport::TestCase
  def setup
    @customer_admin = accounts(:customer_admin)
    @playbook = playbooks(:draft_playbook)
  end

  def teardown
    Current.reset
  end

  test 'request_changes? returns true for customer on changes_requested playbook' do
    Current.organization = organizations(:acme)
    @playbook.update!(status: 'changes_requested')

    policy = PlaybookPolicy.new(@customer_admin, @playbook)

    assert policy.request_changes?
  end
end
