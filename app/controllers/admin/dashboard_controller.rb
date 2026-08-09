class Admin::DashboardController < Admin::BaseController
  def index
    render inertia: 'Admin/Dashboard', props: {
      stats: {
        organizations_count: Organization.count,
        accounts_count: Account.count,
        admin_activities_count: AdminActivity.count
      }
    }
  end
end
