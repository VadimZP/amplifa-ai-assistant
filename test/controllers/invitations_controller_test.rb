require 'test_helper'

class InvitationsControllerTest < ActionDispatch::IntegrationTest
  test 'logged-in different account cannot accept invitation for another email' do
    invitation = Invitation.create!(
      organization: organizations(:beta),
      invited_by: accounts(:amplifa_admin),
      email: accounts(:customer_user).email,
      first_name: 'Wrong',
      last_name: 'Account',
      role: 'customer_user'
    )

    login_as accounts(:growth_lab_user)

    assert_no_difference 'OrganizationMembership.count' do
      post accept_invitation_path(invitation.token), params: { locale: 'en', timezone: 'UTC' }
    end

    assert_redirected_to accept_invitation_path(invitation.token)
    assert_equal 'pending', invitation.reload.status
  end

  # AMP-435 §21: accepting an invitation for an account that already has an INACTIVE
  # membership in that org reactivates the SAME membership instead of duplicating it.
  test 'accepting invitation reactivates an existing inactive membership without duplicating' do
    account = accounts(:customer_user)
    organization = organizations(:beta)
    inactive_membership = OrganizationMembership.create!(
      account: account,
      organization: organization,
      role: 'customer_user',
      status: 'inactive',
      deactivated_at: 2.days.ago
    )
    invitation = Invitation.create!(
      organization: organization,
      invited_by: accounts(:amplifa_admin),
      email: account.email,
      first_name: account.first_name,
      last_name: account.last_name,
      role: 'customer_admin'
    )

    login_as account

    assert_no_difference 'OrganizationMembership.count' do
      assert_no_difference 'OrganizationMembership.where(account: account, organization: organization).count' do
        post accept_invitation_path(invitation.token), params: { locale: 'en', timezone: 'UTC' }
      end
    end

    inactive_membership.reload
    assert_equal 'active', inactive_membership.status
    assert_nil inactive_membership.deactivated_at
    assert_equal 'customer_admin', inactive_membership.role
    assert_equal 1, OrganizationMembership.where(account: account, organization: organization).count

    invitation.reload
    assert_equal 'accepted', invitation.status
    assert_equal account, invitation.account
  end
end
