require "test_helper"

class AgentLeadPolicyTest < ActiveSupport::TestCase
  def setup
    @amplifa_admin = accounts(:amplifa_admin)
    @customer_admin = accounts(:customer_admin)
    @customer_user = accounts(:customer_user)
    @growth_lab_admin = accounts(:growth_lab_admin)
    @acme_agent_lead = agent_leads(:john_in_draft)
    @beta_agent_lead = agent_leads(:beta_lead_in_beta_agent)
  end

  def teardown
    Current.reset
  end

  # index? tests
  test "index? returns true for all authenticated users" do
    # WHY: All users can list agent_leads, scoped by organization via Scope
    assert AgentLeadPolicy.new(@amplifa_admin, AgentLead).index?
    assert AgentLeadPolicy.new(@customer_admin, AgentLead).index?
    assert AgentLeadPolicy.new(@customer_user, AgentLead).index?
  end

  # show? tests
  test "show? returns true for amplifa_admin on any agent_lead" do
    # WHY: Amplifa admins need full access for platform management
    assert AgentLeadPolicy.new(@amplifa_admin, @acme_agent_lead).show?
    assert AgentLeadPolicy.new(@amplifa_admin, @beta_agent_lead).show?
  end

  test "show? returns true for customer viewing own org agent_lead" do
    Current.organization = organizations(:acme)
    # WHY: Customers can view agent_leads that belong to their organization
    assert AgentLeadPolicy.new(@customer_admin, @acme_agent_lead).show?
    assert AgentLeadPolicy.new(@customer_user, @acme_agent_lead).show?
  end

  test "show? returns false for customer viewing other org agent_lead" do
    # WHY: Customers should not see agent_leads from other organizations
    assert_not AgentLeadPolicy.new(@customer_admin, @beta_agent_lead).show?
  end

  test "show? returns false for customer viewing deleted agent_lead" do
    Current.organization = organizations(:acme)
    @acme_agent_lead.agent.mark_deleted!

    assert_not AgentLeadPolicy.new(@customer_admin, @acme_agent_lead).show?
  end

  # create? tests
  test "create? returns true for amplifa_admin" do
    # WHY: Only admins can create agent_lead assignments
    assert AgentLeadPolicy.new(@amplifa_admin, AgentLead.new).create?
  end

  test "create? returns false for customer_admin" do
    # WHY: Customers cannot create agent_leads - read-only access
    assert_not AgentLeadPolicy.new(@customer_admin, AgentLead.new).create?
  end

  test "create? returns false for customer_user" do
    # WHY: Customers cannot create agent_leads
    assert_not AgentLeadPolicy.new(@customer_user, AgentLead.new).create?
  end

  # update? tests
  test "update? returns true for amplifa_admin" do
    # WHY: Only admins can update agent_lead records
    assert AgentLeadPolicy.new(@amplifa_admin, @acme_agent_lead).update?
  end

  test "update? returns false for customers" do
    # WHY: Customers have read-only access to agent_leads
    assert_not AgentLeadPolicy.new(@customer_admin, @acme_agent_lead).update?
    assert_not AgentLeadPolicy.new(@customer_user, @acme_agent_lead).update?
  end

  # destroy? tests
  test "destroy? returns true for amplifa_admin" do
    # WHY: Only admins can delete agent_lead assignments
    assert AgentLeadPolicy.new(@amplifa_admin, @acme_agent_lead).destroy?
  end

  test "destroy? returns false for customers" do
    # WHY: Customers cannot delete agent_leads
    assert_not AgentLeadPolicy.new(@customer_admin, @acme_agent_lead).destroy?
    assert_not AgentLeadPolicy.new(@customer_user, @acme_agent_lead).destroy?
  end

  # mark_meeting? tests
  test "mark_meeting? returns true for amplifa_admin" do
    # WHY: Only admins can mark meetings for manual tracking during dogfooding
    assert AgentLeadPolicy.new(@amplifa_admin, @acme_agent_lead).mark_meeting?
  end

  test "mark_meeting? returns false for customers" do
    # WHY: Customers cannot mark meetings (admin-only for now)
    assert_not AgentLeadPolicy.new(@customer_admin, @acme_agent_lead).mark_meeting?
    assert_not AgentLeadPolicy.new(@customer_user, @acme_agent_lead).mark_meeting?
  end

  # unmark_meeting? tests
  test "unmark_meeting? returns true for amplifa_admin" do
    # WHY: Only admins can unmark meetings in case of errors
    assert AgentLeadPolicy.new(@amplifa_admin, @acme_agent_lead).unmark_meeting?
  end

  test "unmark_meeting? returns false for customers" do
    # WHY: Customers cannot unmark meetings
    assert_not AgentLeadPolicy.new(@customer_admin, @acme_agent_lead).unmark_meeting?
    assert_not AgentLeadPolicy.new(@customer_user, @acme_agent_lead).unmark_meeting?
  end

  # Scope tests
  test "Scope returns all agent_leads for amplifa_admin" do
    # WHY: Admins need visibility across all organizations
    scope = AgentLeadPolicy::Scope.new(@amplifa_admin, AgentLead).resolve
    assert_equal AgentLead.count, scope.count
  end

  test "Scope returns only own org agent_leads for customer" do
    Current.organization = organizations(:acme)
    # WHY: Customers should only see agent_leads from their organization
    scope = AgentLeadPolicy::Scope.new(@customer_admin, AgentLead).resolve
    scope.each do |agent_lead|
      assert_equal @customer_admin.organization_id, agent_lead.agent.organization_id
      assert_not agent_lead.agent.deleted?
    end
  end

  test "Scope excludes deleted agent_leads for customer" do
    Current.organization = organizations(:acme)
    @acme_agent_lead.agent.mark_deleted!

    scope = AgentLeadPolicy::Scope.new(@customer_admin, AgentLead).resolve

    assert_not_includes scope, @acme_agent_lead
  end
end
