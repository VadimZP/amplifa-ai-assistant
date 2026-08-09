# frozen_string_literal: true

require 'test_helper'

class Admin::Organizations::UsersTest < ActionDispatch::IntegrationTest
  setup do
    @admin = accounts(:amplifa_admin)
    @customer_admin = accounts(:customer_admin)
    @organization = organizations(:acme)
    @user = accounts(:customer_user)
  end

  test 'admin organization user show returns account payload used by frontend' do
    login_as(@admin)

    get admin_organization_user_path(@organization, @user), headers: inertia_headers
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal 'Admin/Organizations/Users/Show', body['component']
    assert_equal @user.id, body.dig('props', 'account', 'id')
    assert_equal @user.status, body.dig('props', 'account', 'status')
  end

  test 'admin organization users index uses membership role for filtering and display' do
    login_as(@admin)
    @user.update!(role: 'customer_admin')
    @user.organization_memberships.find_by!(organization: @organization).update!(role: 'customer_user')

    get admin_organization_users_path(@organization, role: 'customer_user'), headers: inertia_headers

    assert_response :success
    listed_user = inertia_props['users'].find { |user| user['id'] == @user.id }
    assert_not_nil listed_user
    assert_equal 'customer_user', listed_user['role']
  end

  test 'admin can send reset password email for organization user from edit' do
    login_as(@admin)

    clear_enqueued_jobs

    assert_difference 'AdminActivity.count', 1 do
      assert_enqueued_emails 1 do
        post send_reset_password_email_admin_organization_user_path(@organization, @user),
             headers: inertia_headers
      end
    end

    assert_redirected_to edit_admin_organization_user_path(@organization, @user)
    assert_equal 'organization_user_password_reset_email_sent', AdminActivity.last.action
  end

  test 'admin can set organization user password directly from edit' do
    login_as(@admin)

    original_password_hash = @user.reload.password_hash

    assert_difference 'AdminActivity.count', 1 do
      post set_password_admin_organization_user_path(@organization, @user), params: {
        password: {
          new_password: 'NewPassword123!',
          new_password_confirmation: 'NewPassword123!'
        }
      }, headers: inertia_headers
    end

    assert_redirected_to edit_admin_organization_user_path(@organization, @user)

    updated_user = @user.reload
    refute_equal original_password_hash, updated_user.password_hash
    assert BCrypt::Password.new(updated_user.password_hash) == 'NewPassword123!'
    assert_equal 'organization_user_password_set_by_admin', AdminActivity.last.action
  end

  test 'invalid organization user password submission re-renders edit with password errors' do
    login_as(@admin)

    post set_password_admin_organization_user_path(@organization, @user), params: {
      password: {
        new_password: 'short',
        new_password_confirmation: 'different'
      }
    }, headers: inertia_headers

    assert_response :unprocessable_entity
    assert_inertia_component 'Admin/Organizations/Users/Edit'

    props = inertia_props
    assert_equal [I18n.t('admin.users.password.new_password_too_short')], props['password_errors']['new_password']
    assert_equal [I18n.t('admin.users.password.confirmation_mismatch')],
                 props['password_errors']['new_password_confirmation']
  end

  test 'admin can create organization user with matching membership' do
    login_as(@admin)

    assert_difference ['Account.count', 'OrganizationMembership.count'], 1 do
      post admin_organization_users_path(@organization), params: {
        account: {
          email: 'org-created-user@acme.com',
          first_name: 'Org',
          last_name: 'Created',
          role: 'customer_admin',
          password: 'SecurePass123!'
        }
      }, headers: inertia_headers
    end

    created = Account.find_by!(email: 'org-created-user@acme.com')
    membership = created.organization_memberships.find_by!(organization: @organization)
    assert_redirected_to admin_organization_user_path(@organization, created)
    assert_equal 'customer_admin', created.role
    assert_equal @organization.id, created.organization_id
    assert_equal 'customer_admin', membership.role
    assert membership.active?
  end

  test 'admin can update organization user with frontend user payload' do
    login_as(@admin)

    patch admin_organization_user_path(@organization, @user), params: {
      user: {
        email: @user.email,
        first_name: 'Updated',
        last_name: @user.last_name,
        role: 'customer_admin'
      }
    }, headers: inertia_headers

    assert_redirected_to admin_organization_user_path(@organization, @user)

    @user.reload
    assert_equal 'Updated', @user.first_name
    assert_equal 'customer_user', @user.role
    assert_equal 'customer_admin', @user.organization_memberships.find_by!(organization: @organization).role
  end

  test 'admin can update organization user with account payload' do
    login_as(@admin)

    patch admin_organization_user_path(@organization, @user), params: {
      account: {
        email: @user.email,
        first_name: 'Account',
        last_name: @user.last_name,
        role: 'customer_admin'
      }
    }, headers: inertia_headers

    assert_redirected_to admin_organization_user_path(@organization, @user)

    @user.reload
    assert_equal 'Account', @user.first_name
    assert_equal 'customer_user', @user.role
    assert_equal 'customer_admin', @user.organization_memberships.find_by!(organization: @organization).role
  end

  test 'org-scoped role edit on the primary org updates membership only and leaves account role unchanged' do
    login_as(@admin)

    org_a = Organization.create!(name: "Primary Org A #{SecureRandom.hex(4)}", status: 'active')
    org_b = Organization.create!(name: "Secondary Org B #{SecureRandom.hex(4)}", status: 'active')

    # Account whose PRIMARY org is org_a (account.organization_id == org_a.id),
    # starting as customer_user globally. after_create :ensure_primary_organization_membership
    # auto-creates the ACTIVE customer_user membership in org_a; we add a separate
    # membership in org_b so we can prove the edit is isolated to org_a's membership.
    account = Account.create!(
      email: "primary-org-edit-#{SecureRandom.hex(4)}@example.com",
      first_name: 'Primary',
      last_name: 'Edit',
      role: 'customer_user',
      organization: org_a,
      status: :verified,
      password_hash: RodauthApp.rodauth.allocate.password_hash('password')
    )

    membership_a = account.organization_memberships.find_by!(organization: org_a)
    membership_b = account.organization_memberships.create!(
      organization: org_b, role: 'customer_user', status: 'active'
    )

    # Guard: the edited org is the account's PRIMARY org (the buggy branch's condition).
    assert_equal org_a.id, account.organization_id
    assert_equal 'customer_user', membership_a.role

    patch admin_organization_user_path(org_a, account), params: {
      user: {
        email: account.email,
        first_name: 'PrimaryUpdated',
        last_name: account.last_name,
        role: 'customer_admin'
      }
    }, headers: inertia_headers

    assert_redirected_to admin_organization_user_path(org_a, account)

    # (a) the edited org_a membership role changed to the new value
    assert_equal 'customer_admin', membership_a.reload.role
    # (b) the GLOBAL Account#role is UNCHANGED, even though org_a is the primary org
    assert_equal 'customer_user', Account.find(account.id).role
    # (c) the unrelated org_b membership role is untouched
    assert_equal 'customer_user', membership_b.reload.role
    # non-role account attributes (email/first/last name) still flow through
    assert_equal 'PrimaryUpdated', account.reload.first_name
  end

  test 'organization user update rejects amplifa admin promotion' do
    login_as(@admin)

    patch admin_organization_user_path(@organization, @user), params: {
      user: {
        email: @user.email,
        first_name: @user.first_name,
        last_name: @user.last_name,
        role: 'amplifa_admin'
      }
    }, headers: inertia_headers

    assert_response :unprocessable_entity
    assert_inertia_component 'Admin/Organizations/Users/Edit'
    assert_equal [I18n.t('admin.users.organization_scope_amplifa_admin_forbidden')], inertia_props.dig('errors', 'role')

    @user.reload
    assert_equal 'customer_user', @user.role
    assert_equal @organization, @user.organization
  end

  test 'customer admin cannot access organization users admin routes' do
    login_as(@customer_admin)

    post send_reset_password_email_admin_organization_user_path(@organization, @user), headers: inertia_headers
    assert_response :redirect
    assert_redirected_to root_path
  end

  # AMP-435 §5: a user created via /admin/organizations/:id/users can authenticate
  # and resolves the creating organization as their current workspace.
  test 'organization-created user can log in and resolves the creating organization as workspace' do
    login_as(@admin)

    post admin_organization_users_path(@organization), params: {
      account: {
        email: 'org-workspace-login@acme.com',
        first_name: 'OrgWorkspace',
        last_name: 'Login',
        role: 'customer_user',
        password: 'SecurePass123!'
      }
    }, headers: inertia_headers
    created = Account.find_by!(email: 'org-workspace-login@acme.com')
    assert_redirected_to admin_organization_user_path(@organization, created)

    post logout_path
    post login_path, params: { email: created.email, password: 'SecurePass123!' }
    assert_redirected_to dashboard_path
    assert_equal @organization.id, session[:current_organization_id]

    get dashboard_path, headers: inertia_headers
    assert_response :success
    assert_equal @organization.id, inertia_props.dig('auth', 'current_organization', 'id')
  end
end
