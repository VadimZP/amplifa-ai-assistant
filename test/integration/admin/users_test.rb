require 'test_helper'

class Admin::UsersTest < ActionDispatch::IntegrationTest
  # WHY: This helper is needed to log in users before testing admin functions
  # because user management is only available to authenticated admins
  def login_as(account)
    # amplifa_admin uses password123, customers use password
    password = account.amplifa_admin? ? 'password123' : 'password'

    post login_path, params: {
      email: account.email,
      password: password
    }
    assert_response :redirect
    follow_redirect!
  end

  test 'amplifa admin can view users index' do
    # WHY: The users list is a core admin feature for managing customer accounts.
    # Amplifa admins should be able to see all users across all organizations.
    admin = accounts(:amplifa_admin)
    login_as(admin)

    get admin_users_path, headers: inertia_headers
    assert_response :success

    # WHY: Response should contain users data in Inertia props
    body = JSON.parse(response.body)
    assert_equal 'Admin/Users/Index', body['component']
    assert body['props']['accounts'].is_a?(Array)
    assert body['props']['organizations'].is_a?(Array)
    assert body['props']['filters'].is_a?(Hash)
  end

  # AMP-435 §9/B7 guard: admin pickers use Organization.active (deactivated-only),
  # so archived orgs must stay listed even though workspaces now hide them.
  test 'archived organizations remain selectable in the admin user org-pickers' do
    admin = accounts(:amplifa_admin)
    archived_organization = Organization.create!(name: "Archived Picker Co #{SecureRandom.hex(4)}", status: 'active')
    archived_organization.archive!
    login_as(admin)

    get new_admin_user_path, headers: inertia_headers
    assert_response :success
    new_ids = inertia_props['organizations'].map { |organization| organization['id'] }
    assert_includes new_ids, archived_organization.id

    get admin_users_path, headers: inertia_headers
    assert_response :success
    index_ids = inertia_props['organizations'].map { |organization| organization['id'] }
    assert_includes index_ids, archived_organization.id
  end

  test 'users index includes multiple organization memberships for organization column' do
    admin = accounts(:amplifa_admin)
    user = accounts(:customer_user)
    extra_org = organizations(:growth_lab)
    OrganizationMembership.find_or_create_by!(account: user, organization: extra_org) do |membership|
      membership.role = 'customer_user'
      membership.status = 'active'
    end
    login_as(admin)

    get admin_users_path, headers: inertia_headers

    assert_response :success
    indexed_user = inertia_props['accounts'].find { |account| account['id'] == user.id }
    organization_names = indexed_user['organization_memberships'].map { |membership| membership.dig('organization', 'name') }
    assert_includes organization_names, organizations(:acme).name
    assert_includes organization_names, extra_org.name
  end

  test 'users index filters by search role status and organization membership' do
    admin = accounts(:amplifa_admin)
    user = accounts(:customer_user)
    extra_org = organizations(:growth_lab)
    OrganizationMembership.find_or_create_by!(account: user, organization: extra_org) do |membership|
      membership.role = 'customer_user'
      membership.status = 'active'
    end
    login_as(admin)

    get admin_users_path, params: {
      search: user.email,
      role: 'customer_user',
      status_filter: 'active',
      organization_id: extra_org.id
    }, headers: inertia_headers

    assert_response :success
    accounts = inertia_props['accounts']
    assert_equal [user.id], accounts.map { |account| account['id'] }
    assert_equal user.email, inertia_props.dig('filters', 'search')
    assert_equal 'customer_user', inertia_props.dig('filters', 'role')
    assert_equal 'active', inertia_props.dig('filters', 'status')
    assert_equal extra_org.id.to_s, inertia_props.dig('filters', 'organization_id')
  end

  test 'amplifa admin can access new user form' do
    # WHY: Admins need to be able to create new users to onboard customer organizations
    admin = accounts(:amplifa_admin)
    login_as(admin)

    get new_admin_user_path, headers: inertia_headers
    assert_response :success

    # WHY: Form should include organization options and role options
    body = JSON.parse(response.body)
    assert_equal 'Admin/Users/New', body['component']
    assert body['props']['organizations'].is_a?(Array)
    assert body['props']['roles'].is_a?(Array)
  end

  test 'amplifa admin can create customer user with valid params' do
    # WHY: User creation is fundamental to the platform. Admins must be able to
    # create customer users with proper validation and security (auto-verified accounts).
    # This test verifies the fix for the params access bug (params at root level, not nested).
    admin = accounts(:amplifa_admin)
    login_as(admin)

    org = organizations(:acme)

    assert_difference ['Account.count', 'OrganizationMembership.count'], 1 do
      post admin_users_path, params: {
        email: 'newuser@acme.com',
        first_name: 'New',
        last_name: 'User',
        password: 'SecurePass123!',
        password_confirmation: 'SecurePass123!',
        role: 'customer_user',
        organization_id: org.id
      }
    end

    # WHY: After successful creation, admin should be redirected to users index
    assert_redirected_to admin_users_path
    follow_redirect!
    assert_match(/User created successfully/, flash[:notice])

    # WHY: Verify the user was created with correct attributes
    new_user = Account.find_by(email: 'newuser@acme.com')
    assert_not_nil new_user
    assert_equal 'New', new_user.first_name
    assert_equal 'User', new_user.last_name
    assert_equal 'customer_user', new_user.role
    assert_equal org.id, new_user.organization_id
    membership = new_user.organization_memberships.find_by!(organization: org)
    assert_equal 'customer_user', membership.role
    assert membership.active?

    # WHY: Admin-created accounts should be auto-verified (no email verification required)
    assert_equal 'verified', new_user.status

    # WHY: Password should be properly hashed and allow login
    assert_not_nil new_user.password_hash
  end

  test 'amplifa admin can create customer admin with organization' do
    # WHY: Customer organizations need admin users who can manage their org's data
    admin = accounts(:amplifa_admin)
    login_as(admin)

    org = organizations(:acme)

    assert_difference ['Account.count', 'OrganizationMembership.count'], 1 do
      post admin_users_path, params: {
        email: 'newadmin@acme.com',
        first_name: 'New',
        last_name: 'Admin',
        password: 'SecurePass123!',
        password_confirmation: 'SecurePass123!',
        role: 'customer_admin',
        organization_id: org.id
      }
    end

    assert_redirected_to admin_users_path

    new_admin = Account.find_by(email: 'newadmin@acme.com')
    assert_equal 'customer_admin', new_admin.role
    assert_equal 'customer_admin', new_admin.organization_memberships.find_by!(organization: org).role
  end

  test 'amplifa admin can create another amplifa admin without organization' do
    # WHY: Amplifa needs the ability to add new admin staff members.
    # Amplifa admins don't belong to any customer organization.
    admin = accounts(:amplifa_admin)
    login_as(admin)

    assert_difference 'Account.count', 1 do
      post admin_users_path, params: {
        email: 'newstaff@amplifa.com',
        first_name: 'New',
        last_name: 'Staff',
        password: 'SecurePass123!',
        password_confirmation: 'SecurePass123!',
        role: 'amplifa_admin',
        organization_id: '' # Empty for amplifa_admin
      }
    end

    assert_redirected_to admin_users_path

    new_staff = Account.find_by(email: 'newstaff@amplifa.com')
    assert_equal 'amplifa_admin', new_staff.role
    assert_nil new_staff.organization_id
  end

  test "user creation fails if passwords don't match" do
    # WHY: Password confirmation prevents typos that would lock users out.
    # This is a critical security validation.
    admin = accounts(:amplifa_admin)
    login_as(admin)

    org = organizations(:acme)

    assert_no_difference 'Account.count' do
      post admin_users_path, params: {
        email: 'test@acme.com',
        first_name: 'Test',
        last_name: 'User',
        password: 'SecurePass123!',
        password_confirmation: 'DifferentPass123!',
        role: 'customer_user',
        organization_id: org.id
      }
    end

    # WHY: Should redirect back to new form with error message
    assert_redirected_to new_admin_user_path
    follow_redirect!
    assert_match(/Password and confirmation do not match/, flash[:alert])
  end

  test 'user creation logs admin activity' do
    # WHY: All admin actions must be logged for audit trail and compliance.
    # This ensures accountability and helps track who created which users.
    admin = accounts(:amplifa_admin)
    login_as(admin)

    org = organizations(:acme)

    assert_difference 'AdminActivity.count', 1 do
      post admin_users_path, params: {
        email: 'tracked@acme.com',
        first_name: 'Tracked',
        last_name: 'User',
        password: 'SecurePass123!',
        password_confirmation: 'SecurePass123!',
        role: 'customer_user',
        organization_id: org.id
      }
    end

    # WHY: Activity log should contain details about the user creation
    activity = AdminActivity.last
    assert_equal admin.id, activity.account_id
    assert_equal org.id, activity.organization_id
    assert_equal 'create_user', activity.action
    assert_equal 'tracked@acme.com', activity.details['email']
    assert_equal 'customer_user', activity.details['role']
  end

  test 'customer user cannot access admin users pages' do
    # WHY: Customer users should not have access to user management.
    # Only Amplifa admins can manage users.
    customer = accounts(:customer_user)
    login_as(customer)

    get admin_users_path
    # WHY: Should be redirected away with access denied
    assert_redirected_to root_path
    follow_redirect!
    assert_match(/Access denied/, flash[:alert])
  end

  test 'amplifa admin can view user details' do
    # WHY: Admins need to see detailed information about users for support
    # and user management purposes. This includes all user profile information
    # and related data.
    admin = accounts(:amplifa_admin)
    login_as(admin)

    user = accounts(:customer_user)
    get admin_user_path(user), headers: inertia_headers
    assert_response :success

    # WHY: Response should render the show page with user data
    body = JSON.parse(response.body)
    assert_equal 'Admin/Users/Show', body['component']

    # WHY: Should include complete user information
    user_data = body['props']['account']
    assert_equal user.id, user_data['id']
    assert_equal user.email, user_data['email']
    assert_equal user.full_name, user_data['full_name']
    assert_equal user.role, user_data['role']
    assert_equal user.status, user_data['status']
    assert_not_nil user_data['created_at']
    assert_equal true, body['props']['can_destroy']

    # WHY: Should include organization data if user belongs to an org
    if user.organization
      assert_not_nil user_data['organization']
      assert_equal user.organization.id, user_data['organization']['id']
      assert_equal user.organization.name, user_data['organization']['name']
    end
  end

  test 'edit user includes two factor setting for amplifa admins' do
    admin = accounts(:amplifa_admin)
    target_admin = Account.create!(
      email: 'target-admin@amplifa.ai',
      first_name: 'Target',
      last_name: 'Admin',
      password_hash: RodauthApp.rodauth.allocate.password_hash('password123'),
      role: 'amplifa_admin',
      status: :verified,
      two_factor_authentication_required: true
    )
    login_as(admin)

    get edit_admin_user_path(target_admin), headers: inertia_headers

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 'Admin/Users/Edit', body['component']
    assert_equal true, body.dig('props', 'account', 'two_factor_authentication_required')
  end

  test 'edit user includes organization memberships and assignable organizations' do
    admin = accounts(:amplifa_admin)
    user = accounts(:customer_user)
    login_as(admin)

    get edit_admin_user_path(user), headers: inertia_headers

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 'Admin/Users/Edit', body['component']
    assert body.dig('props', 'organization_memberships').is_a?(Array)
    assert body.dig('props', 'assignable_organizations').is_a?(Array)
    assert_includes body.dig('props', 'membership_roles'), 'customer_admin'
    assert_includes body.dig('props', 'membership_roles'), 'customer_user'
  end

  test 'amplifa admin can add organization membership from user edit' do
    admin = accounts(:amplifa_admin)
    user = accounts(:customer_user)
    organization = organizations(:growth_lab)
    login_as(admin)

    assert_difference 'OrganizationMembership.where(account: user, organization: organization).count', 1 do
      assert_difference 'AdminActivity.count', 1 do
        post add_organization_membership_admin_user_path(user), params: {
          organization_membership: {
            organization_id: organization.id,
            role: 'customer_admin'
          }
        }
      end
    end

    membership = OrganizationMembership.find_by!(account: user, organization: organization)
    assert_equal 'customer_admin', membership.role
    assert membership.active?
    assert_redirected_to edit_admin_user_path(user)
    assert_equal 'user_organization_membership_added', AdminActivity.last.action
  end

  test 'adding duplicate organization membership is rejected' do
    admin = accounts(:amplifa_admin)
    user = accounts(:customer_user)
    organization = organizations(:acme)
    login_as(admin)

    assert_no_difference 'OrganizationMembership.count' do
      post add_organization_membership_admin_user_path(user), params: {
        organization_membership: {
          organization_id: organization.id,
          role: 'customer_user'
        }
      }
    end

    assert_redirected_to edit_admin_user_path(user)
    assert_equal I18n.t('admin.users.memberships.already_assigned'), flash[:alert]
  end

  test 'amplifa admin can update organization membership role from user edit' do
    admin = accounts(:amplifa_admin)
    user = accounts(:customer_user)
    membership = user.organization_memberships.find_by!(organization: organizations(:acme))
    login_as(admin)

    patch organization_membership_admin_user_path(user, membership), params: {
      organization_membership: {
        role: 'customer_admin'
      }
    }

    assert_redirected_to edit_admin_user_path(user)
    membership.reload
    user.reload
    assert_equal 'customer_admin', membership.role
    assert_equal 'customer_admin', user.role
    assert_equal 'user_organization_membership_updated', AdminActivity.last.action
  end

  test 'amplifa admin can remove non-primary organization membership from user edit' do
    admin = accounts(:amplifa_admin)
    user = accounts(:customer_user)
    membership = OrganizationMembership.create!(
      account: user,
      organization: organizations(:growth_lab),
      role: 'customer_user',
      status: 'active'
    )
    login_as(admin)

    delete organization_membership_admin_user_path(user, membership)

    assert_redirected_to edit_admin_user_path(user)
    membership.reload
    assert_equal 'inactive', membership.status
    assert_not_nil membership.deactivated_at
    assert_equal 'user_organization_membership_removed', AdminActivity.last.action
  end

  test 'removing primary membership moves account fallback to next membership' do
    admin = accounts(:amplifa_admin)
    user = accounts(:customer_user)
    primary_membership = user.organization_memberships.find_by!(organization: organizations(:acme))
    replacement = OrganizationMembership.create!(
      account: user,
      organization: organizations(:growth_lab),
      role: 'customer_admin',
      status: 'active'
    )
    login_as(admin)

    delete organization_membership_admin_user_path(user, primary_membership)

    assert_redirected_to edit_admin_user_path(user)
    user.reload
    assert_equal replacement.organization_id, user.organization_id
    assert_equal replacement.role, user.role
  end

  test 'amplifa admin can update two factor setting for amplifa admin users' do
    admin = accounts(:amplifa_admin)
    admin.update!(two_factor_authentication_required: false)
    login_as(admin)

    patch admin_user_path(admin), params: {
      email: admin.email,
      first_name: admin.first_name,
      last_name: admin.last_name,
      platform_admin: '1',
      status: admin.status,
      two_factor_authentication_required: '1'
    }

    assert_redirected_to admin_users_path
    assert_equal true, admin.reload.two_factor_authentication_required?
    assert admin.requires_email_two_factor_authentication?
  end

  test 'amplifa admin can grant platform access with checkbox payload' do
    admin = accounts(:amplifa_admin)
    user = accounts(:customer_user)
    login_as(admin)

    patch admin_user_path(user), params: {
      email: user.email,
      first_name: user.first_name,
      last_name: user.last_name,
      platform_admin: '1',
      status: user.status,
      two_factor_authentication_required: '1'
    }

    assert_redirected_to admin_users_path
    user.reload
    assert_equal 'amplifa_admin', user.role
    assert_nil user.organization_id
    assert user.two_factor_authentication_required?
  end

  test 'platform access autosave stays on edit page with platform access notice' do
    admin = accounts(:amplifa_admin)
    user = accounts(:customer_user)
    login_as(admin)

    patch admin_user_path(user), params: {
      platform_admin: '1',
      two_factor_authentication_required: '1',
      platform_access_autosave: '1'
    }

    assert_redirected_to edit_admin_user_path(user)
    assert_equal I18n.t('admin.users.platform_access.amplifa_admin_enabled'), flash[:notice]
    user.reload
    assert_equal 'amplifa_admin', user.role
    assert user.two_factor_authentication_required?
  end

  test 'amplifa admin can remove platform access when user has active membership' do
    admin = accounts(:amplifa_admin)
    target = Account.create!(
      email: 'demote-admin@amplifa.ai',
      first_name: 'Demote',
      last_name: 'Admin',
      password_hash: RodauthApp.rodauth.allocate.password_hash('password123'),
      role: 'amplifa_admin',
      status: :verified
    )
    membership = OrganizationMembership.create!(
      account: target,
      organization: organizations(:acme),
      role: 'customer_admin',
      status: 'active'
    )
    login_as(admin)

    patch admin_user_path(target), params: {
      email: target.email,
      first_name: target.first_name,
      last_name: target.last_name,
      platform_admin: '0',
      status: target.status,
      two_factor_authentication_required: '0'
    }

    assert_redirected_to admin_users_path
    target.reload
    assert_equal membership.role, target.role
    assert_equal membership.organization_id, target.organization_id
  end

  test 'removing platform access requires an active membership' do
    admin = accounts(:amplifa_admin)
    target = Account.create!(
      email: 'no-membership-admin@amplifa.ai',
      first_name: 'NoMembership',
      last_name: 'Admin',
      password_hash: RodauthApp.rodauth.allocate.password_hash('password123'),
      role: 'amplifa_admin',
      status: :verified
    )
    login_as(admin)

    patch admin_user_path(target), params: {
      email: target.email,
      first_name: target.first_name,
      last_name: target.last_name,
      platform_admin: '0',
      status: target.status,
      two_factor_authentication_required: '0'
    }

    assert_redirected_to edit_admin_user_path(target)
    assert_equal I18n.t('admin.users.platform_access.demote_requires_membership'), flash[:alert]
    assert_equal 'amplifa_admin', target.reload.role
  end

  test 'amplifa admin can add organization membership to platform admin user' do
    admin = accounts(:amplifa_admin)
    target = Account.create!(
      email: 'admin-with-membership@amplifa.ai',
      first_name: 'Admin',
      last_name: 'Membership',
      password_hash: RodauthApp.rodauth.allocate.password_hash('password123'),
      role: 'amplifa_admin',
      status: :verified
    )
    organization = organizations(:acme)
    login_as(admin)

    assert_difference 'OrganizationMembership.where(account: target, organization: organization).count', 1 do
      post add_organization_membership_admin_user_path(target), params: {
        organization_membership: {
          organization_id: organization.id,
          role: 'customer_user'
        }
      }
    end

    assert_redirected_to edit_admin_user_path(target)
  end

  test 'user show page includes activities performed BY the user' do
    # WHY: When viewing an admin user's details, we need to see what actions
    # they've performed (e.g., what users they created, what orgs they modified)
    # for audit and accountability purposes.
    admin = accounts(:amplifa_admin)
    login_as(admin)

    # WHY: Create some activities performed by the user we're viewing
    target_admin = admin # View the admin's own page
    activity1 = AdminActivity.create!(
      account: target_admin,
      action: 'create_user',
      details: { email: 'test@example.com' },
      created_at: 1.day.ago
    )
    activity2 = AdminActivity.create!(
      account: target_admin,
      action: 'update_organization',
      organization: organizations(:acme),
      details: { changes: { status: %w[onboarding active] } },
      created_at: 2.days.ago
    )

    get admin_user_path(target_admin), headers: inertia_headers
    assert_response :success

    body = JSON.parse(response.body)
    activities_by_user = body['props']['activities_by_user']

    # WHY: Should include activities performed BY this user
    assert activities_by_user.is_a?(Array)
    activity_ids = activities_by_user.map { |a| a['id'] }
    assert_includes activity_ids, activity1.id, 'Should include activities performed by user'
    assert_includes activity_ids, activity2.id, 'Should include activities performed by user'
  end

  test 'user show page includes activities performed ON the user' do
    # WHY: When viewing any user's details, we need to see what actions were
    # performed on them (e.g., when they were created, who created them, any updates)
    # for audit trail and support purposes.
    admin = accounts(:amplifa_admin)
    login_as(admin)

    customer = accounts(:customer_user)

    # WHY: Create activities that reference this user in the details
    activity1 = AdminActivity.create!(
      account: admin,
      organization: customer.organization,
      action: 'create_user',
      details: {
        email: customer.email,
        user_id: customer.id,
        role: customer.role
      },
      created_at: 3.days.ago
    )

    activity2 = AdminActivity.create!(
      account: admin,
      action: 'impersonate_user',
      organization: customer.organization,
      details: {
        target_account_id: customer.id,
        target_email: customer.email
      },
      created_at: 1.day.ago
    )

    get admin_user_path(customer), headers: inertia_headers
    assert_response :success

    body = JSON.parse(response.body)
    activities_on_user = body['props']['activities_on_user']

    # WHY: Should include activities performed ON this user
    assert activities_on_user.is_a?(Array)
    activity_ids = activities_on_user.map { |a| a['id'] }
    assert_includes activity_ids, activity1.id, 'Should include user creation activity'
    assert_includes activity_ids, activity2.id, 'Should include impersonation activity'
  end

  test 'user show page does not include unrelated activities' do
    # WHY: The activity lists should only show activities directly related to the user,
    # not the entire activity log, to maintain clarity and performance.
    admin = accounts(:amplifa_admin)
    login_as(admin)

    customer = accounts(:customer_user)
    other_customer = accounts(:customer_admin)

    # WHY: Create an activity about a different user
    unrelated_activity = AdminActivity.create!(
      account: admin,
      action: 'update_user',
      details: {
        user_id: other_customer.id,
        email: other_customer.email,
        changes: { role: %w[customer_user customer_admin] }
      }
    )

    get admin_user_path(customer), headers: inertia_headers
    assert_response :success

    body = JSON.parse(response.body)

    # WHY: Should not include activities about other users
    all_activity_ids = (body['props']['activities_by_user'] + body['props']['activities_on_user']).map { |a| a['id'] }
    refute_includes all_activity_ids, unrelated_activity.id, 'Should not include unrelated activities'
  end

  test 'customer admin cannot view user details' do
    # WHY: Customer admins should not have access to the admin user management
    # interface, including user detail pages.
    customer_admin = accounts(:customer_admin)
    login_as(customer_admin)

    user = accounts(:customer_user)
    get admin_user_path(user), headers: inertia_headers

    # WHY: Admin::BaseController redirects non-admins with access denied message
    assert_response :redirect
    assert_redirected_to root_path
    assert_equal 'Access denied', flash[:alert]
  end

  test 'user show page includes both activity types for admin users' do
    # WHY: For admin users who both perform actions and have actions performed on them,
    # we need to see both types of activities separately to understand their full history.
    admin = accounts(:amplifa_admin)
    login_as(admin)

    # WHY: Create activity BY the admin
    activity_by = AdminActivity.create!(
      account: admin,
      action: 'create_organization',
      details: { name: 'Test Corp' }
    )

    # WHY: Create activity ON the admin (e.g., another admin updated them)
    other_admin = Account.amplifa_admins.where.not(id: admin.id).first ||
                  Account.create!(
                    email: 'other@amplifa.com',
                    first_name: 'Other',
                    last_name: 'Admin',
                    role: 'amplifa_admin',
                    status: :verified
                  )

    activity_on = AdminActivity.create!(
      account: other_admin,
      action: 'update_user',
      details: {
        user_id: admin.id,
        email: admin.email,
        changes: { first_name: %w[Old New] }
      }
    )

    get admin_user_path(admin), headers: inertia_headers
    assert_response :success

    body = JSON.parse(response.body)

    # WHY: Should have both activity types
    by_user_ids = body['props']['activities_by_user'].map { |a| a['id'] }
    on_user_ids = body['props']['activities_on_user'].map { |a| a['id'] }

    assert_includes by_user_ids, activity_by.id, 'Should include activities BY admin'
    assert_includes on_user_ids, activity_on.id, 'Should include activities ON admin'
  end

  test 'user show page includes necessary activity data for display' do
    # WHY: The frontend needs complete activity data (account name, organization name, etc.)
    # to display the activity log without additional requests.
    admin = accounts(:amplifa_admin)
    login_as(admin)

    org = organizations(:acme)
    activity = AdminActivity.create!(
      account: admin,
      organization: org,
      action: 'test_action',
      details: { test: 'data' },
      ip_address: '192.168.1.1',
      created_at: 1.hour.ago
    )

    get admin_user_path(admin), headers: inertia_headers
    assert_response :success

    body = JSON.parse(response.body)
    activities = body['props']['activities_by_user']

    # WHY: Find the activity we created
    activity_data = activities.find { |a| a['id'] == activity.id }
    assert_not_nil activity_data, 'Should include the created activity'

    # WHY: Should have all required fields for display
    assert activity_data['action'], 'Should have action'
    assert activity_data['details'], 'Should have details'
    assert activity_data['created_at'], 'Should have timestamp'
    assert activity_data['account'], 'Should have account info'
    assert activity_data['account']['name'], 'Should have account name'

    # WHY: Organization may be present
    if activity_data['organization_id']
      assert activity_data['organization'], 'Should have organization if org_id present'
      assert activity_data['organization']['name'], 'Should have organization name'
    end
  end

  test 'amplifa admin can deactivate a non-protected user' do
    admin = accounts(:amplifa_admin)
    login_as(admin)

    user = Account.create!(
      email: 'delete-me@acme.com',
      first_name: 'Delete',
      last_name: 'Me',
      password_hash: RodauthApp.rodauth.allocate.password_hash('password'),
      role: 'customer_user',
      status: :verified,
      organization: organizations(:acme)
    )

    assert_no_difference 'Account.count' do
      delete admin_user_path(user)
    end

    assert_redirected_to admin_users_path
    follow_redirect!
    assert_match(/User deactivated successfully/, flash[:notice])

    user.reload
    assert_not_nil user.deactivated_at
    assert_equal 'closed', user.status
  end

  test 'amplifa admin can deactivate a referenced user without deleting records' do
    admin = accounts(:amplifa_admin)
    login_as(admin)

    user = Account.create!(
      email: 'referenced@acme.com',
      first_name: 'Referenced',
      last_name: 'User',
      password_hash: RodauthApp.rodauth.allocate.password_hash('password'),
      role: 'customer_user',
      status: :verified,
      organization: organizations(:acme)
    )

    invitation = Invitation.create!(
      organization: organizations(:acme),
      invited_by: user,
      email: 'invitee@acme.com',
      first_name: 'Invitee',
      last_name: 'Person',
      role: 'customer_user',
      status: 'pending'
    )

    assert_no_difference 'Account.count' do
      assert_no_difference 'Invitation.count' do
        delete admin_user_path(user)
      end
    end

    assert_redirected_to admin_users_path

    user.reload
    invitation.reload
    assert_not_nil user.deactivated_at
    assert_equal 'closed', user.status
    assert_equal user.id, invitation.invited_by_id
  end

  # AMP-435 §3a: an INACTIVE membership must not count as an active membership,
  # so demotion is still blocked when the platform admin has no ACTIVE memberships.
  test 'removing platform access is blocked when the only membership is inactive' do
    admin = accounts(:amplifa_admin)
    target = Account.create!(
      email: 'inactive-only-admin@amplifa.ai',
      first_name: 'Inactive',
      last_name: 'Only',
      password_hash: RodauthApp.rodauth.allocate.password_hash('password123'),
      role: 'amplifa_admin',
      status: :verified
    )
    OrganizationMembership.create!(
      account: target,
      organization: organizations(:acme),
      role: 'customer_admin',
      status: 'inactive',
      deactivated_at: 1.day.ago
    )
    login_as(admin)

    patch admin_user_path(target), params: {
      email: target.email,
      first_name: target.first_name,
      last_name: target.last_name,
      platform_admin: '0',
      status: target.status,
      two_factor_authentication_required: '0'
    }

    assert_redirected_to edit_admin_user_path(target)
    assert_equal I18n.t('admin.users.platform_access.demote_requires_membership'), flash[:alert]
    target.reload
    assert_equal 'amplifa_admin', target.role
    assert_nil target.organization_id
  end

  # AMP-435 §3b: demotion adopts the FIRST active membership (earliest created_at),
  # not any later one, when the user has multiple active memberships.
  test 'removing platform access adopts the first active membership role and organization' do
    admin = accounts(:amplifa_admin)
    first_org = organizations(:acme)
    second_org = organizations(:growth_lab)
    target = Account.create!(
      email: 'demote-first-membership@amplifa.ai',
      first_name: 'Demote',
      last_name: 'First',
      password_hash: RodauthApp.rodauth.allocate.password_hash('password123'),
      role: 'amplifa_admin',
      status: :verified
    )
    # Two ACTIVE memberships with distinct roles; explicit created_at makes the
    # "first active membership" deterministic (first_membership is earliest).
    first_membership = OrganizationMembership.create!(
      account: target, organization: first_org,
      role: 'customer_admin', status: 'active', created_at: 2.days.ago
    )
    second_membership = OrganizationMembership.create!(
      account: target, organization: second_org,
      role: 'customer_user', status: 'active', created_at: 1.day.ago
    )
    login_as(admin)

    patch admin_user_path(target), params: {
      email: target.email,
      first_name: target.first_name,
      last_name: target.last_name,
      platform_admin: '0',
      status: target.status,
      two_factor_authentication_required: '0'
    }

    assert_redirected_to admin_users_path
    target.reload
    assert_equal first_membership.role, target.role
    assert_equal first_membership.organization_id, target.organization_id
    refute_equal second_membership.organization_id, target.organization_id
    refute_equal second_membership.role, target.role
  end

  # AMP-435 §4: navigating the index without filter params (the "clear filters"
  # state) resets filter props to defaults and returns the full account set.
  test 'users index without filter params resets to defaults and the full account set' do
    admin = accounts(:amplifa_admin)
    user = accounts(:customer_user)
    login_as(admin)

    get admin_users_path, params: {
      search: user.email,
      role: 'customer_user',
      status_filter: 'active',
      organization_id: organizations(:acme).id
    }, headers: inertia_headers
    assert_response :success
    filtered_ids = inertia_props['accounts'].map { |account| account['id'] }
    assert_equal [user.id], filtered_ids

    get admin_users_path, headers: inertia_headers
    assert_response :success
    assert_equal '', inertia_props.dig('filters', 'search')
    assert_equal 'all', inertia_props.dig('filters', 'role')
    assert_equal 'all', inertia_props.dig('filters', 'status')
    assert_equal 'all', inertia_props.dig('filters', 'organization_id')

    cleared_ids = inertia_props['accounts'].map { |account| account['id'] }
    assert_includes cleared_ids, admin.id
    assert_operator cleared_ids.length, :>, filtered_ids.length
  end

  # AMP-435 §4: the index search matches first name, last name, and full name.
  test 'users index search matches first name last name and full name' do
    admin = accounts(:amplifa_admin)
    login_as(admin)
    target = Account.create!(
      email: 'name-search-target@acme.com',
      first_name: 'Zaphod',
      last_name: 'Beeblebrox',
      password_hash: RodauthApp.rodauth.allocate.password_hash('password'),
      role: 'customer_user',
      status: :verified,
      organization: organizations(:acme)
    )

    get admin_users_path, params: { search: 'Zaphod' }, headers: inertia_headers
    assert_includes inertia_props['accounts'].map { |account| account['id'] }, target.id,
                    'first-name search should match'

    get admin_users_path, params: { search: 'Beeblebrox' }, headers: inertia_headers
    assert_includes inertia_props['accounts'].map { |account| account['id'] }, target.id,
                    'last-name search should match'

    get admin_users_path, params: { search: 'Zaphod Beeblebrox' }, headers: inertia_headers
    full_name_ids = inertia_props['accounts'].map { |account| account['id'] }
    assert_equal [target.id], full_name_ids, 'full-name search should match exactly one user'

    get admin_users_path, params: { search: 'Nonexistent Someone' }, headers: inertia_headers
    refute_includes inertia_props['accounts'].map { |account| account['id'] }, target.id,
                    'non-matching search should exclude the user'
  end

  # AMP-435 §5: a user created via /admin/users can authenticate and resolves the
  # creating organization as their current workspace.
  test 'user created via admin users can log in and resolves the creating organization as workspace' do
    admin = accounts(:amplifa_admin)
    org = organizations(:acme)
    login_as(admin)

    post admin_users_path, params: {
      email: 'workspace-login@acme.com',
      first_name: 'Workspace',
      last_name: 'Login',
      password: 'SecurePass123!',
      password_confirmation: 'SecurePass123!',
      role: 'customer_user',
      organization_id: org.id
    }
    assert_redirected_to admin_users_path
    created = Account.find_by!(email: 'workspace-login@acme.com')

    post logout_path
    post login_path, params: { email: created.email, password: 'SecurePass123!' }
    assert_redirected_to dashboard_path
    assert_equal org.id, session[:current_organization_id]

    get dashboard_path, headers: inertia_headers
    assert_response :success
    assert_equal org.id, inertia_props.dig('auth', 'current_organization', 'id')
  end

  private

  def inertia_headers
    {
      'HTTP_X_INERTIA' => 'true',
      'HTTP_X_INERTIA_VERSION' => ViteRuby.digest,
      'HTTP_ACCEPT' => 'text/html, application/xhtml+xml',
      'HTTP_X_REQUESTED_WITH' => 'XMLHttpRequest'
    }
  end
end
