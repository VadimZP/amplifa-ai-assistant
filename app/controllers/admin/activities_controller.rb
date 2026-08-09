class Admin::ActivitiesController < Admin::BaseController

  def index
    # WHY: Use policy scope to ensure only amplifa admins can see activities
    authorize AdminActivity
    activities = policy_scope(AdminActivity)

    # WHY: Apply organization filter if provided
    if params[:organization_id].present?
      activities = activities.where(organization_id: params[:organization_id])
    end

    # WHY: Apply action type filter if provided
    # Note: Cannot use params[:action] as it's a Rails reserved parameter containing the controller action name
    if params[:action_type].present?
      activities = activities.where(action: params[:action_type])
    end

    # WHY: Apply date range filter if provided
    if params[:start_date].present?
      start_date = Date.parse(params[:start_date])
      activities = activities.where('DATE(created_at) >= ?', start_date)
    end

    if params[:end_date].present?
      end_date = Date.parse(params[:end_date])
      activities = activities.where('DATE(created_at) <= ?', end_date)
    end

    # WHY: Default to last 7 days if no date filter provided
    if params[:start_date].blank? && params[:end_date].blank?
      activities = activities.where('created_at >= ?', 7.days.ago)
    end

    # WHY: Always order by newest first for audit trail
    activities = activities.includes(:account, :organization)
                          .order(created_at: :desc)

    # WHY: Paginate with 50 per page to prevent performance issues
    page = params[:page]&.to_i || 1
    per_page = 50
    total = activities.count
    activities = activities.limit(per_page).offset((page - 1) * per_page)

    # WHY: Serialize activities with account and organization data for display
    activities_json = activities.as_json(
      only: [:id, :action, :details, :ip_address, :user_agent, :created_at, :organization_id],
      include: {
        account: {
          only: [:id, :email, :first_name, :last_name],
          methods: [:full_name]
        },
        organization: {
          only: [:id, :name]
        }
      }
    )

    # WHY: Add 'name' field to account for easier template access (same as show action)
    activities_json.each do |activity|
      if activity['account']
        activity['account']['name'] = activity['account']['full_name']
      end
    end

    # WHY: Provide filter options for dropdowns without additional requests
    organizations = Organization.order(:name).as_json(only: [:id, :name])

    # WHY: Get unique action types from existing activities for filter dropdown
    action_types = AdminActivity.distinct.pluck(:action).sort

    render inertia: 'Admin/Activities/Index', props: {
      activities: activities_json,
      organizations: organizations,
      action_types: action_types,
      pagination: {
        page: page,
        per_page: per_page,
        total: total,
        total_pages: (total.to_f / per_page).ceil
      },
      filters: {
        organization_id: params[:organization_id],
        action_type: params[:action_type],
        start_date: params[:start_date],
        end_date: params[:end_date]
      }
    }
  end

  def show
    # WHY: Use policy to ensure only amplifa admins can view activity details
    activity = AdminActivity.includes(:account, :organization).find(params[:id])
    authorize activity

    # WHY: Serialize activity with full details including account and organization
    activity_json = activity.as_json(
      only: [:id, :action, :details, :ip_address, :user_agent, :created_at],
      include: {
        account: {
          only: [:id, :email, :first_name, :last_name, :role],
          methods: [:full_name]
        },
        organization: {
          only: [:id, :name, :website]
        }
      }
    )

    # WHY: Add 'name' field to account for easier template access
    if activity_json['account']
      activity_json['account']['name'] = activity.account.full_name
    end

    render inertia: 'Admin/Activities/Show', props: {
      activity: activity_json
    }
  end

end
