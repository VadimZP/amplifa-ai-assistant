# frozen_string_literal: true

require 'test_helper'

class Admin::UsersPasswordActionsTest < ActionDispatch::IntegrationTest
  test 'amplifa admin can send reset password email from user edit' do
    admin = accounts(:amplifa_admin)
    login_as(admin)

    user = accounts(:customer_user)
    clear_enqueued_jobs

    assert_difference 'AdminActivity.count', 1 do
      assert_enqueued_emails 1 do
        post send_reset_password_email_admin_user_path(user), headers: inertia_headers
      end
    end

    assert_redirected_to edit_admin_user_path(user)
    assert_equal 'user_password_reset_email_sent', AdminActivity.last.action
  end

  test 'amplifa admin can set user password directly from user edit' do
    admin = accounts(:amplifa_admin)
    login_as(admin)

    user = accounts(:customer_user)
    original_password_hash = user.reload.password_hash

    assert_difference 'AdminActivity.count', 1 do
      post set_password_admin_user_path(user), params: {
        password: {
          new_password: 'NewPassword123!',
          new_password_confirmation: 'NewPassword123!'
        }
      }, headers: inertia_headers
    end

    assert_redirected_to edit_admin_user_path(user)
    updated_user = user.reload
    refute_equal original_password_hash, updated_user.password_hash
    assert BCrypt::Password.new(updated_user.password_hash) == 'NewPassword123!'
    assert_equal 'user_password_set_by_admin', AdminActivity.last.action
  end

  test 'customer user cannot trigger global admin password actions' do
    customer = accounts(:customer_user)
    login_as(customer)

    user = accounts(:customer_admin)
    post send_reset_password_email_admin_user_path(user), headers: inertia_headers

    assert_response :redirect
    assert_redirected_to root_path
    assert_equal 'Access denied', flash[:alert]
  end
end
