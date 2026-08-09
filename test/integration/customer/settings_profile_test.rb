require 'test_helper'
class SettingsProfileTest < ActionDispatch::IntegrationTest
  test 'customer user can access profile settings page' do
    customer_user = accounts(:customer_user)
    login_as(customer_user)

    get settings_profile_path, headers: inertia_headers

    assert_response :success
    assert_inertia_component 'Customer/Settings/Profile'
    assert_equal customer_user.email, inertia_props['account']['email']
    assert_includes inertia_props['locale_options'], 'en'
    assert_includes inertia_props['locale_options'], 'pt-BR'
  end

  test 'customer user can update profile account fields' do
    customer_user = accounts(:customer_user)
    login_as(customer_user)

    patch settings_profile_path, params: {
      account: {
        first_name: 'Updated',
        last_name: 'Name',
        timezone: 'Europe/London',
        locale: 'de'
      }
    }

    assert_response :redirect
    assert_redirected_to settings_profile_path

    customer_user.reload
    assert_equal 'Updated', customer_user.first_name
    assert_equal 'Name', customer_user.last_name
    assert_equal 'Europe/London', customer_user.timezone
    assert_equal 'de', customer_user.locale
  end

  test 'customer user can update password with valid current password' do
    customer_user = accounts(:customer_user)
    login_as(customer_user)

    patch settings_profile_password_path, params: {
      account: {
        current_password: 'password',
        new_password: 'newpassword123',
        new_password_confirmation: 'newpassword123'
      }
    }

    assert_response :redirect
    assert_redirected_to settings_profile_path

    customer_user.reload
    rodauth = RodauthApp.rodauth.allocate
    rodauth.account_from_login(customer_user.email)
    assert rodauth.password_match?('newpassword123')
  end

  test 'password update with wrong current password returns validation errors' do
    customer_user = accounts(:customer_user)
    login_as(customer_user)

    patch settings_profile_password_path, params: {
      account: {
        current_password: 'wrong-password',
        new_password: 'newpassword123',
        new_password_confirmation: 'newpassword123'
      }
    }, headers: inertia_headers

    assert_response :unprocessable_entity
    assert_inertia_component 'Customer/Settings/Profile'
    assert inertia_props['password_errors']['current_password']
  end

  test 'password update with mismatched confirmation returns validation errors' do
    customer_user = accounts(:customer_user)
    login_as(customer_user)

    patch settings_profile_password_path, params: {
      account: {
        current_password: 'password',
        new_password: 'newpassword123',
        new_password_confirmation: 'different-password'
      }
    }, headers: inertia_headers

    assert_response :unprocessable_entity
    assert_inertia_component 'Customer/Settings/Profile'
    assert inertia_props['password_errors']['new_password_confirmation']

    customer_user.reload
    rodauth = RodauthApp.rodauth.allocate
    rodauth.account_from_login(customer_user.email)
    assert rodauth.password_match?('password')
  end
end
