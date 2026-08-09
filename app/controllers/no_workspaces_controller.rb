class NoWorkspacesController < ApplicationController
  skip_after_action :verify_authorized
  skip_after_action :verify_policy_scoped

  def show
    render inertia: 'Customer/NoWorkspace'
  end
end
