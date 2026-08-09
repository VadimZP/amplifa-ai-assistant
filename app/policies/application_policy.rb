class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user = user  # This will be an Account object
    @record = record
  end

  # WHY: Amplifa admins have full access to all resources.
  # Subclass policies can add additional access rules using `super || ...`
  def index?
    amplifa_admin?
  end

  def show?
    amplifa_admin?
  end

  def create?
    amplifa_admin?
  end

  def new?
    create?
  end

  def update?
    amplifa_admin?
  end

  def edit?
    update?
  end

  def destroy?
    amplifa_admin?
  end

  private

  # WHY: Helper method to check if user is an Amplifa admin.
  # Handles nil user gracefully for unauthenticated requests.
  def amplifa_admin?
    user&.amplifa_admin?
  end

  def current_organization_id
    Current.organization&.id
  end

  def current_membership
    membership = Current.organization_membership
    return membership if membership&.account_id == user&.id

    nil
  end

  def customer_account?
    return false unless user

    current_membership.present?
  end

  def customer_admin?
    return false unless user
    return current_membership.customer_admin? if current_membership

    false # was: user.customer_admin? — no active workspace membership => no admin rights
  end

  def customer_user?
    return false unless user
    return current_membership.customer_user? if current_membership

    false # was: user.customer_user? — no active workspace membership => no customer-user rights
  end

  def same_current_organization?(record_organization_id)
    current_organization_id.present? && current_organization_id == record_organization_id
  end

  class Scope
    def initialize(user, scope)
      @user = user  # This will be an Account object
      @scope = scope
    end

    # WHY: Amplifa admins can see all records.
    # Subclass scopes should call super first, then apply org-specific filtering.
    def resolve
      return scope.all if user&.amplifa_admin?
      raise NotImplementedError, "You must define #resolve in #{self.class}"
    end

    private

    attr_reader :user, :scope

    def current_organization_id
      Current.organization&.id
    end

    def current_membership
      membership = Current.organization_membership
      return membership if membership&.account_id == user&.id

      nil
    end

    def customer_account?
      return false unless user

      current_membership.present?
    end

    def customer_admin?
      return false unless user
      return current_membership.customer_admin? if current_membership

      false # was: user.customer_admin? — no active workspace membership => no admin rights
    end
  end
end
