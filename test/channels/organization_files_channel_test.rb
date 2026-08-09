# frozen_string_literal: true

require 'test_helper'

class OrganizationFilesChannelTest < ActionCable::Channel::TestCase
  test 'rejects organization stream for customer accounts' do
    stub_connection current_account: accounts(:customer_user)

    subscribe organization_id: organizations(:acme).id

    assert subscription.rejected?
  end

  test 'allows organization stream for amplifa admins' do
    organization = organizations(:acme)
    stub_connection current_account: accounts(:amplifa_admin)

    subscribe organization_id: organization.id

    assert subscription.confirmed?
    assert_has_stream_for organization
  end

  test 'allows playbook stream for same organization customers' do
    playbook = playbooks(:approved_playbook)
    stub_connection current_account: accounts(:customer_user)

    subscribe playbook_id: playbook.id

    assert subscription.confirmed?
    assert_has_stream OrganizationFilesChannel.broadcasting_for(OrganizationFilesChannel.playbook_stream_name(playbook))
  end

  test 'rejects playbook stream for customers from other organizations' do
    playbook = playbooks(:approved_playbook)
    stub_connection current_account: accounts(:beta_user)

    subscribe playbook_id: playbook.id

    assert subscription.rejected?
  end
end
