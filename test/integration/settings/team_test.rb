require 'test_helper'

class Settings::TeamTest < ActionDispatch::IntegrationTest
  setup do
    @customer_admin = accounts(:customer_admin)
    @customer_user = accounts(:customer_user)
    @growth_lab_user = accounts(:growth_lab_user)
  end

  test 'team settings page includes organization team members and pending invitations' do
    old_unexpired_invitation = Invitation.create!(
      organization: organizations(:acme),
      invited_by: @customer_admin,
      email: 'old-unexpired@acme.com',
      first_name: 'Old',
      last_name: 'Unexpired',
      role: 'customer_user',
      sent_at: 4.days.ago,
      expires_at: 2.days.from_now
    )

    login_as(@customer_user)

    get settings_team_path, headers: inertia_headers

    assert_response :success
    assert_inertia_component 'Customer/Settings/Team'

    member_emails = inertia_props['team_members'].map { |member| member['email'] }
    invitation_emails = inertia_props['pending_invitations'].map { |invitation| invitation['email'] }

    assert_includes member_emails, 'org_admin@acme.com'
    assert_includes member_emails, 'user@acme.com'
    assert_not_includes member_emails, 'user@growthlab.com'

    assert_includes invitation_emails, 'pending@acme.com'
    assert_includes invitation_emails, old_unexpired_invitation.email
    assert_not_includes invitation_emails, 'expired@acme.com'
    assert_not_includes invitation_emails, 'pending@beta.com'
  end

  test 'customer admin can create team invitation from settings' do
    login_as(@customer_admin)

    assert_difference('Invitation.count', 1) do
      assert_enqueued_with(job: ActionMailer::MailDeliveryJob, queue: 'mailers') do
        post '/settings/team/invitations', params: {
          invitation: {
            email: 'new-team-member@acme.com',
            first_name: 'New',
            last_name: 'Teammate',
            role: 'customer_user'
          }
        }
      end
    end

    assert_response :redirect
    assert_redirected_to settings_team_path

    invitation = Invitation.find_by!(email: 'new-team-member@acme.com')
    assert_equal organizations(:acme).id, invitation.organization_id
    assert_equal @customer_admin.id, invitation.invited_by_id
    assert_equal 'pending', invitation.status
  end

  test 'customer user cannot create team invitation from settings' do
    login_as(@customer_user)

    assert_no_difference('Invitation.count') do
      post '/settings/team/invitations', params: {
        invitation: {
          email: 'blocked-invite@acme.com',
          first_name: 'Blocked',
          last_name: 'Invite',
          role: 'customer_user'
        }
      }
    end

    assert_response :redirect
    assert_equal 'You are not authorized to perform this action.', flash[:alert]
  end

  test 'customer admin can cancel pending team invitation from settings' do
    login_as(@customer_admin)
    invitation = invitations(:pending_acme)

    delete settings_team_invitation_path(invitation)

    assert_response :redirect
    assert_redirected_to settings_team_path

    invitation.reload
    assert_equal 'cancelled', invitation.status
  end

  test 'customer admin cannot cancel invitation from another organization' do
    login_as(@customer_admin)
    invitation = invitations(:pending_beta)

    delete settings_team_invitation_path(invitation)

    assert_response :redirect
    assert_redirected_to settings_team_path
    assert_equal 'Invitation not found.', flash[:alert]

    invitation.reload
    assert_equal 'pending', invitation.status
  end

  test 'customer admin can deactivate customer user from settings' do
    login_as(@customer_admin)
    target = accounts(:customer_user)
    target.update!(deactivated_at: nil)

    patch settings_team_deactivate_member_path(target)

    assert_response :redirect
    assert_redirected_to settings_team_path

    target.reload
    membership = target.organization_memberships.find_by!(organization: organizations(:acme))
    assert_nil target.deactivated_at
    assert_equal 'inactive', membership.status
    assert_not_nil membership.deactivated_at
  end

  test 'customer admin cannot deactivate another customer admin from settings' do
    login_as(@customer_admin)
    target = accounts(:customer_admin)
    another_admin = Account.create!(
      email: 'second-admin@acme.com',
      first_name: 'Second',
      last_name: 'Admin',
      password_hash: RodauthApp.rodauth.allocate.password_hash('password'),
      status: 'verified',
      role: 'customer_admin',
      organization: organizations(:acme)
    )

    patch settings_team_deactivate_member_path(another_admin)

    assert_response :redirect
    assert_redirected_to settings_team_path
    assert_equal 'Customer admins cannot deactivate other customer admins.', flash[:alert]

    another_admin.reload
    assert_nil another_admin.deactivated_at

    target.reload
    assert_nil target.deactivated_at
  end

  test 'customer admin cannot deactivate team member from another organization' do
    login_as(@customer_admin)

    patch settings_team_deactivate_member_path(@growth_lab_user)

    assert_response :redirect
    assert_redirected_to settings_team_path
    assert_equal 'Team member not found.', flash[:alert]

    @growth_lab_user.reload
    assert_nil @growth_lab_user.deactivated_at
  end
end
