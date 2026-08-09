class TeamController < ApplicationController
  def index
    # WHY: Authorize using TeamPolicy to ensure only authenticated users can access
    authorize :team, :index?

    if current_account.amplifa_admin?
      # WHY: Amplifa admins see other amplifa admins (internal staff team)
      # They should NOT see customer users from customer organizations
      team_members = Account
        .where(role: 'amplifa_admin')
        .order(created_at: :desc)

      # WHY: Skip policy_scope since amplifa admins don't belong to an organization
      # and we're manually filtering to show only amplifa_admins
      skip_policy_scope
    else
      # WHY: Customer users see members from their own organization only
      # Use policy_scope to automatically filter to current user's organization
      # and exclude Amplifa admins from the customer team list
      team_members = policy_scope(Account)
        .where.not(role: 'amplifa_admin')
        .order(created_at: :desc)
    end

    render inertia: 'Team/Index', props: {
      team_members: team_members.as_json(
        only: [:id, :first_name, :last_name, :email, :role, :created_at],
        methods: [:full_name, :customer_admin?, :customer_user?]
      )
    }
  end
end
