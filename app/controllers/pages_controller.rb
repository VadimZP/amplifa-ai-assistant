class PagesController < ApplicationController
  skip_before_action :authenticate
  skip_after_action :verify_authorized
  skip_after_action :verify_policy_scoped

  def home
    if current_account
      redirect_to dashboard_path
    else
      redirect_to login_path
    end
  end
end
