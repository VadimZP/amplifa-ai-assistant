class Admin::UsersController < Admin::BaseController
  SORTABLE_FIELDS = %w[name email organization role].freeze
  SORT_DIRECTIONS = %w[asc desc].freeze

  before_action :set_account, only: %i[show edit update destroy send_reset_password_email set_password add_organization_membership update_organization_membership remove_organization_membership]

  def new
    organizations = Organization.active.order(:name).as_json(only: %i[id name])

    render inertia: 'Admin/Users/New', props: {
      organizations: organizations,
      roles: Account::ROLES
    }
  end

  def create
    # Validate password confirmation
    if params[:password] != params[:password_confirmation]
      return redirect_to new_admin_user_path, alert: 'Password and confirmation do not match'
    end

    account = Account.new(account_params.except(:password, :password_confirmation))
    # Auto-verify accounts created by admins
    account.status = :verified

    if account.save
      # Set password using Rodauth's password hash
      require 'bcrypt'
      password_hash = BCrypt::Password.create(params[:password])
      account.update_column(:password_hash, password_hash)

      # Log admin activity
      AdminActivity.create!(
        account_id: current_account.id,
        organization_id: account.organization_id,
        action: 'create_user',
        details: {
          email: account.email,
          role: account.role,
          organization_id: account.organization_id
        },
        ip_address: request.remote_ip,
        user_agent: request.user_agent
      )

      redirect_to admin_users_path, notice: 'User created successfully'
    else
      redirect_to new_admin_user_path, alert: account.errors.full_messages.join(', ')
    end
  end

  def index
    sort = SORTABLE_FIELDS.include?(params[:sort]) ? params[:sort] : 'organization'
    direction = SORT_DIRECTIONS.include?(params[:direction]) ? params[:direction] : 'asc'

    accounts = Account.includes(:organization, organization_memberships: :organization)
    accounts = apply_filters(accounts)
    accounts = apply_sort(accounts, sort, direction)
    accounts = accounts.map { |account| serialize_index_account(account) }

    render inertia: 'Admin/Users/Index', props: {
      accounts: accounts,
      organizations: Organization.active.order(:name).as_json(only: %i[id name]),
      roles: Account::ROLES,
      filters: user_filters,
      sort: sort,
      direction: direction
    }
  end

  def show
    # WHY: Serialize user data with organization information for display
    account_json = @account.as_json(
      only: %i[id email first_name last_name role status deactivated_at created_at],
      include: {
        organization: { only: %i[id name website] }
      },
      methods: [:full_name]
    )

    # WHY: Find activities performed BY this user (actions they took)
    # This is important for admin users to see what actions they've performed
    activities_by_user = AdminActivity.includes(:account, :organization)
                                      .where(account_id: @account.id)
                                      .order(created_at: :desc)
                                      .limit(20)
                                      .as_json(
                                        only: %i[id action details ip_address user_agent created_at
                                                 organization_id],
                                        include: {
                                          account: {
                                            only: %i[id email first_name last_name],
                                            methods: [:full_name]
                                          },
                                          organization: {
                                            only: %i[id name]
                                          }
                                        }
                                      )

    # WHY: Add account name to each activity for easier template access
    activities_by_user.each do |activity|
      if activity['account']
        activity['account']['name'] = "#{activity['account']['first_name']} #{activity['account']['last_name']}"
      end
    end

    # WHY: Find activities performed ON this user (actions taken on them)
    # We look for activities where details contain user_id, target_account_id, or matching email
    # This shows user creation, impersonation, updates, etc.
    activities_on_user = AdminActivity.includes(:account, :organization)
                                      .where(
                                        "details->>'user_id' = ? OR details->>'target_account_id' = ? OR details->>'email' = ?",
                                        @account.id.to_s,
                                        @account.id.to_s,
                                        @account.email
                                      )
                                      .order(created_at: :desc)
                                      .limit(20)
                                      .as_json(
                                        only: %i[id action details ip_address user_agent created_at
                                                 organization_id],
                                        include: {
                                          account: {
                                            only: %i[id email first_name last_name],
                                            methods: [:full_name]
                                          },
                                          organization: {
                                            only: %i[id name]
                                          }
                                        }
                                      )

    # WHY: Add account name to each activity for easier template access
    activities_on_user.each do |activity|
      if activity['account']
        activity['account']['name'] = "#{activity['account']['first_name']} #{activity['account']['last_name']}"
      end
    end

    render inertia: 'Admin/Users/Show', props: {
      account: account_json,
      activities_by_user: activities_by_user,
      activities_on_user: activities_on_user,
      can_destroy: policy(@account).destroy?
    }
  end

  def edit
    render_edit
  end

  def update
    previous_platform_admin = @account.amplifa_admin?
    previous_two_factor_required = @account.two_factor_authentication_required?
    attributes = if params.key?(:platform_admin)
                   platform_access_account_params
                 else
                   legacy_account_params
                 end
    return unless attributes

    if @account.update(attributes)
      notice = platform_access_notice(previous_platform_admin, previous_two_factor_required)
      redirect_to update_success_redirect_path, notice: notice
    else
      redirect_to edit_admin_user_path(@account), alert: @account.errors.full_messages.join(', ')
    end
  end

  def destroy
    unless policy(@account).destroy?
      log_admin_activity('user_delete_blocked', {
                           account_id: @account.id,
                           email: @account.email,
                           reason: delete_block_reason(@account)
                         })

      redirect_to admin_user_path(@account), alert: 'This user cannot be deleted.'
      return
    end

    account_id = @account.id
    email = @account.email

    if @account.deactivate!
      log_admin_activity('user_deactivated', {
                           account_id: account_id,
                           email: email
                         })

      redirect_to admin_users_path, notice: 'User deactivated successfully'
    else
      redirect_to admin_user_path(@account), alert: 'Failed to delete user'
    end
  end

  def send_reset_password_email
    rodauth_auth = RodauthApp.rodauth.allocate
    rodauth_auth.account_from_id(@account.id)

    if !rodauth_auth.send(:open_account?) || rodauth_auth.reset_password_email_recently_sent?
      redirect_to edit_admin_user_path(@account), alert: t('admin.users.password.reset_email_failed')
      return
    end

    rodauth_auth.send(:generate_reset_password_key_value)
    rodauth_auth.send(:transaction) do
      rodauth_auth.create_reset_password_key
      rodauth_auth.send_reset_password_email
    end

    log_admin_activity('user_password_reset_email_sent', {
                         account_id: @account.id,
                         email: @account.email
                       })

    redirect_to edit_admin_user_path(@account), notice: t('admin.users.password.reset_email_sent')
  end

  def set_password
    errors = password_validation_errors

    if errors.any?
      render_edit(password_errors: errors, status: :unprocessable_entity)
      return
    end

    @account.update_columns(
      password_hash: RodauthApp.rodauth.allocate.password_hash(password_params[:new_password])
    )

    log_admin_activity('user_password_set_by_admin', {
                         account_id: @account.id,
                         email: @account.email
                       })

    redirect_to edit_admin_user_path(@account), notice: t('admin.users.password.set_success')
  end

  def add_organization_membership
    organization = Organization.active.find_by(id: organization_membership_params[:organization_id])

    unless organization
      redirect_to edit_admin_user_path(@account), alert: t('admin.users.memberships.organization_not_found')
      return
    end

    membership = @account.organization_memberships.find_or_initialize_by(organization: organization)

    if membership.persisted? && membership.active?
      redirect_to edit_admin_user_path(@account), alert: t('admin.users.memberships.already_assigned')
      return
    end

    membership.assign_attributes(
      role: organization_membership_params[:role],
      status: 'active',
      deactivated_at: nil
    )

    if membership.save
      log_admin_activity('user_organization_membership_added', {
                           account_id: @account.id,
                           email: @account.email,
                           organization_id: organization.id,
                           role: membership.role
                         })
      redirect_to edit_admin_user_path(@account), notice: t('admin.users.memberships.add_success')
    else
      redirect_to edit_admin_user_path(@account), alert: membership.errors.full_messages.join(', ')
    end
  end

  def update_organization_membership
    membership = @account.organization_memberships.find(params[:membership_id])

    ActiveRecord::Base.transaction do
      membership.update!(role: organization_membership_params[:role])
      sync_primary_account_role!(membership)
    end

    log_admin_activity('user_organization_membership_updated', {
                         account_id: @account.id,
                         email: @account.email,
                         organization_id: membership.organization_id,
                         role: membership.role
                       })
    redirect_to edit_admin_user_path(@account), notice: t('admin.users.memberships.update_success')
  rescue ActiveRecord::RecordInvalid => e
    redirect_to edit_admin_user_path(@account), alert: e.record.errors.full_messages.join(', ')
  end

  def remove_organization_membership
    membership = @account.organization_memberships.find(params[:membership_id])
    replacement = replacement_membership_for(membership)

    if removing_last_primary_membership?(membership, replacement)
      redirect_to edit_admin_user_path(@account), alert: t('admin.users.memberships.last_membership_required')
      return
    end

    ActiveRecord::Base.transaction do
      membership.update!(status: 'inactive', deactivated_at: Time.current)
      move_primary_account_membership!(replacement) if replacement && membership.organization_id == @account.organization_id
    end

    log_admin_activity('user_organization_membership_removed', {
                         account_id: @account.id,
                         email: @account.email,
                         organization_id: membership.organization_id
                       })
    redirect_to edit_admin_user_path(@account), notice: t('admin.users.memberships.remove_success')
  end

  private

  def set_account
    @account = Account.find(params[:id])
  end

  def account_params
    params.permit(:email, :first_name, :last_name, :role, :organization_id, :status, :password, :password_confirmation,
                  :two_factor_authentication_required)
  end

  def legacy_account_params
    account_params.tap do |attributes|
      attributes[:organization_id] = nil if attributes[:role] == 'amplifa_admin'
    end
  end

  def platform_access_account_params
    attributes = params.permit(:email, :first_name, :last_name, :status, :two_factor_authentication_required)
    platform_admin = ActiveModel::Type::Boolean.new.cast(params[:platform_admin])

    if platform_admin
      attributes[:role] = 'amplifa_admin'
      attributes[:organization_id] = nil
      return attributes
    end

    return attributes unless @account.amplifa_admin?

    membership = @account.active_organization_memberships.includes(:organization).order(:created_at).first
    unless membership
      redirect_to edit_admin_user_path(@account), alert: t('admin.users.platform_access.demote_requires_membership')
      return nil
    end

    attributes[:role] = membership.role
    attributes[:organization_id] = membership.organization_id
    attributes
  end

  def password_params
    params.require(:password).permit(:new_password, :new_password_confirmation)
  end

  def organization_membership_params
    params.require(:organization_membership).permit(:organization_id, :role)
  end

  def sync_primary_account_role!(membership)
    return if @account.amplifa_admin?
    return unless @account.organization_id == membership.organization_id

    @account.update!(role: membership.role)
  end

  def replacement_membership_for(membership)
    @account.active_organization_memberships.where.not(id: membership.id).order(:created_at).first
  end

  def removing_last_primary_membership?(membership, replacement)
    !@account.amplifa_admin? && @account.organization_id == membership.organization_id && replacement.nil?
  end

  def move_primary_account_membership!(membership)
    @account.update!(role: membership.role, organization_id: membership.organization_id)
  end

  def platform_access_notice(previous_platform_admin, previous_two_factor_required)
    return 'Account updated successfully' unless params.key?(:platform_admin)

    if previous_platform_admin != @account.amplifa_admin?
      return t(@account.amplifa_admin? ? 'admin.users.platform_access.amplifa_admin_enabled' : 'admin.users.platform_access.amplifa_admin_disabled')
    end

    if previous_two_factor_required != @account.two_factor_authentication_required?
      return t(@account.two_factor_authentication_required? ? 'admin.users.platform_access.two_factor_enabled' : 'admin.users.platform_access.two_factor_disabled')
    end

    'Account updated successfully'
  end

  def update_success_redirect_path
    if ActiveModel::Type::Boolean.new.cast(params[:platform_access_autosave])
      edit_admin_user_path(@account)
    else
      admin_users_path
    end
  end

  def password_validation_errors
    errors = {}

    if password_params[:new_password].blank?
      errors[:new_password] = [t('admin.users.password.new_password_required')]
    elsif password_params[:new_password].length < 8
      errors[:new_password] = [t('admin.users.password.new_password_too_short')]
    end

    if password_params[:new_password_confirmation].blank?
      errors[:new_password_confirmation] = [t('admin.users.password.confirmation_required')]
    elsif password_params[:new_password_confirmation] != password_params[:new_password]
      errors[:new_password_confirmation] = [t('admin.users.password.confirmation_mismatch')]
    end

    errors
  end

  def render_edit(password_errors: nil, status: :ok)
    organizations = Organization.active.order(:name).as_json(only: %i[id name])
    organization_memberships = @account.organization_memberships
                                       .active
                                       .includes(:organization)
                                       .order('organizations.name')
                                       .as_json(
                                         only: %i[id role status organization_id],
                                         include: { organization: { only: %i[id name] } }
                                       )
    assigned_organization_ids = organization_memberships.map { |membership| membership['organization_id'] }

    render inertia: 'Admin/Users/Edit', props: {
      account: @account.as_json(
        only: %i[id email first_name last_name role organization_id status deactivated_at
                 two_factor_authentication_required],
        include: {
          organization: { only: %i[id name] }
        }
      ),
      organizations: organizations,
      organization_memberships: organization_memberships,
      assignable_organizations: organizations.reject { |organization| assigned_organization_ids.include?(organization['id']) },
      membership_roles: OrganizationMembership::ROLES,
      roles: Account::ROLES,
      statuses: Account.statuses.keys,
      password_errors: password_errors
    }, status: status
  end

  def log_admin_activity(action, details)
    AdminActivity.create!(
      account_id: current_account.id,
      organization_id: @account.organization_id,
      action: action,
      details: details,
      ip_address: request.remote_ip,
      user_agent: request.user_agent
    )
  end

  def delete_block_reason(account)
    return 'already_deactivated' if account.deactivated_at.present?
    return 'self_delete' if account.id == current_account.id
    return 'protected_amplifa_admin' if account.protected_from_admin_deletion?

    'not_authorized'
  end

  def serialize_index_account(account)
    account.as_json(
      only: %i[id email first_name last_name role status deactivated_at created_at],
      include: {
        organization: { only: %i[id name] }
      },
      methods: %i[active? full_name]
    ).merge(
      organization_memberships: account.active_organization_memberships
                                       .includes(:organization)
                                       .order('organizations.name')
                                       .as_json(
                                         only: %i[id role status organization_id],
                                         include: { organization: { only: %i[id name] } }
                                       )
    )
  end

  def user_filters
    {
      search: params[:search].to_s,
      role: params[:role].presence || 'all',
      status: params[:status_filter].presence || 'all',
      organization_id: params[:organization_id].presence || 'all'
    }
  end

  def apply_filters(scope)
    filters = user_filters

    if filters[:search].present?
      search = "%#{filters[:search].strip.downcase}%"
      scope = scope.where(
        "LOWER(accounts.email) LIKE :search OR LOWER(accounts.first_name) LIKE :search OR LOWER(accounts.last_name) LIKE :search OR LOWER(CONCAT(accounts.first_name, ' ', accounts.last_name)) LIKE :search",
        search: search
      )
    end

    scope = scope.where(role: filters[:role]) if Account::ROLES.include?(filters[:role])

    scope = case filters[:status]
            when 'active'
              scope.where(deactivated_at: nil)
            when 'deactivated'
              scope.where.not(deactivated_at: nil)
            else
              scope
            end

    if filters[:organization_id] != 'all'
      organization_id = filters[:organization_id].to_i
      scope = scope.where(
        'accounts.organization_id = :organization_id OR accounts.id IN (SELECT account_id FROM organization_memberships WHERE organization_id = :organization_id)',
        organization_id: organization_id
      )
    end

    scope
  end

  def apply_sort(scope, sort, direction)
    case sort
    when 'name'
      scope.order("accounts.first_name #{direction}, accounts.last_name #{direction}, accounts.id #{direction}")
    when 'email'
      scope.order("accounts.email #{direction}, accounts.id #{direction}")
    when 'organization'
      scope.left_joins(:organization).order("organizations.name #{direction} NULLS LAST, accounts.role #{direction}, accounts.first_name #{direction}, accounts.last_name #{direction}, accounts.id #{direction}")
    when 'role'
      scope.order("accounts.role #{direction}, accounts.id #{direction}")
    else
      scope.order(:first_name, :last_name, :id)
    end
  end
end
