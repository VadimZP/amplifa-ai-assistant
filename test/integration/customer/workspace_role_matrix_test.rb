# frozen_string_literal: true

require 'test_helper'

# AMP-435 §8 (plan todo 18): role-matrix permutation.
#
# The account below is customer_admin in org_a (primary) and customer_user in
# org_b. Every admin-only "can manage" signal a customer settings page exposes
# must follow the CURRENT-WORKSPACE membership role, not the legacy global
# Account#role — so it must be TRUE while org_a is active and FALSE while org_b
# is active.
#
# Surfaces already covered by sibling per-surface tests (NOT duplicated here):
#   * Dashboard      can_edit                 -> test/integration/customer/dashboard_test.rb
#   * Integrations   can_manage_integrations  -> test/integration/settings/integrations_test.rb
#   * Agents         can_manage_campaigns     -> test/integration/customer/agents_test.rb
#
# This test adds the surfaces whose can-manage PROP flip was NOT yet asserted:
#   * Webhooks       can_manage_webhooks
#   * Senders/Email  can_manage_sender_settings + can_manage_auto_forward_interested_conversations
#   * Blacklists     canManage / canAdd / canRemove
#   * Team           can_manage_team
class Customer::WorkspaceRoleMatrixTest < ActionDispatch::IntegrationTest
  private

  def assert_manage_signals(expected:, workspace:)
    get settings_webhooks_path, headers: inertia_headers
    assert_response :success
    assert_inertia_component 'Customer/Settings/Webhooks'
    assert_equal expected, inertia_props['can_manage_webhooks'],
                 "webhooks can_manage_webhooks must be #{expected} in #{workspace}"

    get settings_email_path, headers: inertia_headers
    assert_response :success
    assert_inertia_component 'Customer/Settings/Email'
    assert_equal expected, inertia_props['can_manage_sender_settings'],
                 "email can_manage_sender_settings must be #{expected} in #{workspace}"
    assert_equal expected, inertia_props['can_manage_auto_forward_interested_conversations'],
                 "email can_manage_auto_forward_interested_conversations must be #{expected} in #{workspace}"

    get settings_blacklists_path, headers: inertia_headers
    assert_response :success
    assert_inertia_component 'Customer/Settings/Blacklists/Index'
    assert_equal expected, inertia_props['canManage'],
                 "blacklists canManage must be #{expected} in #{workspace}"
    assert_equal expected, inertia_props['canAdd'],
                 "blacklists canAdd must be #{expected} in #{workspace}"
    assert_equal expected, inertia_props['canRemove'],
                 "blacklists canRemove must be #{expected} in #{workspace}"

    get settings_team_path, headers: inertia_headers
    assert_response :success
    assert_inertia_component 'Customer/Settings/Team'
    assert_equal expected, inertia_props['can_manage_team'],
                 "team can_manage_team must be #{expected} in #{workspace}"
  end
end
