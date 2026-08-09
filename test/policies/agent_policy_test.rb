require 'test_helper'

class AgentPolicyTest < ActiveSupport::TestCase
  def setup
    @amplifa_admin = accounts(:amplifa_admin)
    @customer_admin = accounts(:customer_admin)
    @customer_user = accounts(:customer_user)
    @growth_lab_admin = accounts(:growth_lab_admin)
    @draft_agent = agents(:draft_agent)
    @active_agent = agents(:active_agent)
    @other_org_agent = agents(:other_org_agent)
  end

  def teardown
    Current.reset
  end

  test 'scope uses selected organization instead of legacy account organization' do
    membership = OrganizationMembership.create!(
      account: @customer_admin,
      organization: @other_org_agent.organization,
      role: 'customer_user',
      status: 'active'
    )
    Current.account = @customer_admin
    Current.organization = @other_org_agent.organization
    Current.organization_membership = membership

    scope = AgentPolicy::Scope.new(@customer_admin, Agent).resolve

    assert_includes scope, @other_org_agent
    assert_not_includes scope, @draft_agent
  end

  test 'customer admin actions use selected membership role' do
    membership = OrganizationMembership.create!(
      account: @customer_admin,
      organization: @other_org_agent.organization,
      role: 'customer_user',
      status: 'active'
    )
    Current.account = @customer_admin
    Current.organization = @other_org_agent.organization
    Current.organization_membership = membership

    assert_not AgentPolicy.new(@customer_admin, @other_org_agent).pause_campaign?
  end

  # index? tests
  test 'index? returns true for all authenticated users' do
    # WHY: All users can list agents, scoped by organization via Scope
    assert AgentPolicy.new(@amplifa_admin, Agent).index?
    assert AgentPolicy.new(@customer_admin, Agent).index?
    assert AgentPolicy.new(@customer_user, Agent).index?
  end

  # show? tests
  test 'show? returns true for amplifa_admin on any agent' do
    # WHY: Amplifa admins need full visibility for platform management
    assert AgentPolicy.new(@amplifa_admin, @draft_agent).show?
    assert AgentPolicy.new(@amplifa_admin, @other_org_agent).show?
  end

  test 'show? returns false for deleted agent' do
    deleted_agent = Agent.create!(
      organization: organizations(:acme),
      created_by: accounts(:customer_admin),
      name: "Deleted Policy #{SecureRandom.hex(4)}",
      status: 'draft'
    )
    deleted_agent.mark_deleted!

    assert_not AgentPolicy.new(@amplifa_admin, deleted_agent).show?
    assert_not AgentPolicy.new(@customer_admin, deleted_agent).show?
  end

  test 'customer member actions return false for deleted agent' do
    deleted_agent = Agent.create!(
      organization: organizations(:acme),
      created_by: accounts(:customer_admin),
      name: "Deleted Member Actions #{SecureRandom.hex(4)}",
      status: 'draft',
      samples_generated_at: 1.hour.ago
    )
    deleted_agent.mark_deleted!

    policy = AgentPolicy.new(@customer_admin, deleted_agent)
    assert_not policy.review_samples?
    assert_not policy.approve_samples?
    assert_not policy.request_changes?
    assert_not policy.pause_campaign?
    assert_not policy.resume_campaign?
  end

  test 'show? returns true for customer viewing own org agent' do
    Current.organization = organizations(:acme)
    # WHY: Customers can view agents belonging to their organization
    assert AgentPolicy.new(@customer_admin, @draft_agent).show?
    assert AgentPolicy.new(@customer_user, @active_agent).show?
  end

  test 'show? returns false for customer viewing other org agent' do
    # WHY: Customers should not access agents from other organizations
    assert_not AgentPolicy.new(@customer_admin, @other_org_agent).show?
    assert_not AgentPolicy.new(@customer_user, @other_org_agent).show?
  end

  # create? tests
  test 'create? returns true for amplifa_admin' do
    # WHY: Only admins can create agents
    assert AgentPolicy.new(@amplifa_admin, Agent.new).create?
  end

  test 'create? returns false for customer_admin' do
    # WHY: Customers cannot create agents - admin-only operation
    assert_not AgentPolicy.new(@customer_admin, Agent.new).create?
  end

  test 'create? returns false for customer_user' do
    # WHY: Customers cannot create agents
    assert_not AgentPolicy.new(@customer_user, Agent.new).create?
  end

  # update? tests
  test 'update? returns true for amplifa_admin' do
    # WHY: Only admins can update agents
    assert AgentPolicy.new(@amplifa_admin, @draft_agent).update?
  end

  test 'update? returns false for customer_admin' do
    # WHY: Customers have read-only access to agents
    assert_not AgentPolicy.new(@customer_admin, @draft_agent).update?
  end

  test 'update? returns false for customer_user' do
    # WHY: Customers cannot update agents
    assert_not AgentPolicy.new(@customer_user, @draft_agent).update?
  end

  # destroy? tests
  test 'destroy? returns true for amplifa_admin' do
    # WHY: Only admins can delete agents
    assert AgentPolicy.new(@amplifa_admin, @draft_agent).destroy?
  end

  test 'destroy? returns false for customer_admin' do
    # WHY: Customers cannot delete agents
    assert_not AgentPolicy.new(@customer_admin, @draft_agent).destroy?
  end

  test 'destroy? returns false for customer_user' do
    # WHY: Customers cannot delete agents
    assert_not AgentPolicy.new(@customer_user, @draft_agent).destroy?
  end

  # import_leads? tests
  test 'import_leads? returns true for amplifa_admin' do
    # WHY: Only admins can import leads for an agent
    assert AgentPolicy.new(@amplifa_admin, @draft_agent).import_leads?
  end

  test 'import_leads? returns false for customer_admin' do
    # WHY: Customers cannot import leads - admin-only operation
    assert_not AgentPolicy.new(@customer_admin, @draft_agent).import_leads?
  end

  test 'import_leads? returns false for customer_user' do
    # WHY: Customers cannot import leads
    assert_not AgentPolicy.new(@customer_user, @draft_agent).import_leads?
  end

  # assign_mailboxes? tests
  test 'assign_mailboxes? returns true for amplifa_admin' do
    # WHY: Only admins can assign mailboxes to agents
    assert AgentPolicy.new(@amplifa_admin, @draft_agent).assign_mailboxes?
  end

  test 'assign_mailboxes? returns false for customer_admin' do
    # WHY: Customers cannot assign mailboxes - admin-only operation
    assert_not AgentPolicy.new(@customer_admin, @draft_agent).assign_mailboxes?
  end

  test 'assign_mailboxes? returns false for customer_user' do
    # WHY: Customers cannot assign mailboxes
    assert_not AgentPolicy.new(@customer_user, @draft_agent).assign_mailboxes?
  end

  # Scope tests
  test 'Scope returns all agents for amplifa_admin' do
    # WHY: Admins need visibility across all organizations
    deleted_agent = Agent.create!(
      organization: organizations(:acme),
      created_by: accounts(:customer_admin),
      name: "Deleted Scope #{SecureRandom.hex(4)}",
      status: 'draft'
    )
    deleted_agent.mark_deleted!

    scope = AgentPolicy::Scope.new(@amplifa_admin, Agent).resolve
    assert_equal Agent.not_deleted.count, scope.count
    assert_not_includes scope, deleted_agent
  end

  test 'Scope returns only own org agents for customer_admin' do
    Current.organization = organizations(:acme)
    # WHY: Customer admins should only see their organization's agents
    scope = AgentPolicy::Scope.new(@customer_admin, Agent).resolve
    expected_agents = Agent.not_deleted.where(organization: @customer_admin.organization)
    assert_equal expected_agents.count, scope.count
    scope.each do |agent|
      assert_equal @customer_admin.organization_id, agent.organization_id
    end
  end

  test 'Scope returns only own org agents for customer_user' do
    Current.organization = organizations(:acme)
    # WHY: Customer users should only see their organization's agents
    scope = AgentPolicy::Scope.new(@customer_user, Agent).resolve
    scope.each do |agent|
      assert_equal @customer_user.organization_id, agent.organization_id
    end
  end

  # review_samples? tests
  test 'review_samples? returns true for customer with samples generated' do
    Current.organization = organizations(:acme)
    # WHY: Customers can review samples for their org's agents when samples exist
    @draft_agent.update!(samples_generated_at: 1.hour.ago)
    assert AgentPolicy.new(@customer_admin, @draft_agent).review_samples?
    assert AgentPolicy.new(@customer_user, @draft_agent).review_samples?
  end

  test 'review_samples? returns false for customer when no samples generated' do
    # WHY: Customers cannot review samples until they are generated
    @draft_agent.update!(samples_generated_at: nil)
    assert_not AgentPolicy.new(@customer_admin, @draft_agent).review_samples?
  end

  test 'review_samples? returns false for amplifa_admin' do
    # WHY: Admins should use the admin interface, not customer interface
    @draft_agent.update!(samples_generated_at: 1.hour.ago)
    assert_not AgentPolicy.new(@amplifa_admin, @draft_agent).review_samples?
  end

  test 'review_samples? returns false for other org customer' do
    # WHY: Customers can only review their own organization's agents
    @other_org_agent.update!(samples_generated_at: 1.hour.ago)
    assert_not AgentPolicy.new(@customer_admin, @other_org_agent).review_samples?
  end

  # approve_samples? tests
  test 'approve_samples? returns true for customer when samples generated but not approved' do
    Current.organization = organizations(:acme)
    # WHY: Customers can approve samples that are generated and pending approval
    @draft_agent.update!(samples_generated_at: 1.hour.ago, samples_approved_at: nil)
    assert AgentPolicy.new(@customer_admin, @draft_agent).approve_samples?
  end

  test 'approve_samples? returns false for customer when samples already approved' do
    # WHY: Cannot approve already approved samples
    @draft_agent.update!(samples_generated_at: 1.hour.ago, samples_approved_at: 30.minutes.ago)
    assert_not AgentPolicy.new(@customer_admin, @draft_agent).approve_samples?
  end

  test 'approve_samples? returns false when no samples generated' do
    # WHY: Cannot approve samples that don't exist
    @draft_agent.update!(samples_generated_at: nil, samples_approved_at: nil)
    assert_not AgentPolicy.new(@customer_admin, @draft_agent).approve_samples?
  end

  test 'approve_samples? returns false for amplifa_admin' do
    # WHY: Admins should use admin interface for sample management
    @draft_agent.update!(samples_generated_at: 1.hour.ago, samples_approved_at: nil)
    assert_not AgentPolicy.new(@amplifa_admin, @draft_agent).approve_samples?
  end

  # request_changes? tests
  test 'request_changes? returns true for customer when samples are generated' do
    Current.organization = organizations(:acme)
    # WHY: Customers can request changes when samples exist
    @draft_agent.update!(samples_generated_at: 1.hour.ago)
    assert AgentPolicy.new(@customer_admin, @draft_agent).request_changes?
  end

  test 'request_changes? returns false when no samples generated' do
    # WHY: Cannot request changes on non-existent samples
    @draft_agent.update!(samples_generated_at: nil)
    assert_not AgentPolicy.new(@customer_admin, @draft_agent).request_changes?
  end

  test 'request_changes? returns false for amplifa_admin' do
    # WHY: Admins should use admin interface
    @draft_agent.update!(samples_generated_at: 1.hour.ago)
    assert_not AgentPolicy.new(@amplifa_admin, @draft_agent).request_changes?
  end

  test 'request_changes? returns false for other org customer' do
    # WHY: Customers can only request changes for their own org's agents
    @other_org_agent.update!(samples_generated_at: 1.hour.ago)
    assert_not AgentPolicy.new(@customer_admin, @other_org_agent).request_changes?
  end

  test 'pause_campaign? returns true for customer_admin in own organization' do
    Current.organization = organizations(:acme)
    Current.organization_membership = organization_memberships(:customer_admin_acme)
    assert AgentPolicy.new(@customer_admin, @active_agent).pause_campaign?
  end

  test 'pause_campaign? returns false for customer_user' do
    assert_not AgentPolicy.new(@customer_user, @active_agent).pause_campaign?
  end

  test 'pause_campaign? returns false for customer_admin in other organization' do
    assert_not AgentPolicy.new(@customer_admin, @other_org_agent).pause_campaign?
  end

  test 'resume_campaign? returns true for customer_admin in own organization' do
    Current.organization = organizations(:acme)
    Current.organization_membership = organization_memberships(:customer_admin_acme)
    assert AgentPolicy.new(@customer_admin, @active_agent).resume_campaign?
  end

  test 'resume_campaign? returns false for customer_user' do
    assert_not AgentPolicy.new(@customer_user, @active_agent).resume_campaign?
  end

  test 'resume_campaign? returns false for customer_admin in other organization' do
    assert_not AgentPolicy.new(@customer_admin, @other_org_agent).resume_campaign?
  end
end
