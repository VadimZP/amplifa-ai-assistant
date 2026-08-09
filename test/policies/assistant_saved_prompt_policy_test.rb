require 'test_helper'

class AssistantSavedPromptPolicyTest < ActiveSupport::TestCase
  def setup
    @customer_admin = accounts(:customer_admin)
    @customer_user = accounts(:customer_user)
    @growth_lab_admin = accounts(:growth_lab_admin)
    @acme = organizations(:acme)
    @growth_lab = organizations(:growth_lab)

    @owned_prompt = AssistantSavedPrompt.create!(
      account: @customer_admin,
      organization: @acme,
      title: 'Inbox triage',
      prompt: 'Which conversations need my reply?'
    )
    @foreign_prompt = AssistantSavedPrompt.create!(
      account: @growth_lab_admin,
      organization: @growth_lab,
      title: 'Growth stats',
      prompt: 'How are my campaigns doing?'
    )
  end

  def teardown
    Current.reset
  end

  def act_as_acme_admin
    Current.account = @customer_admin
    Current.organization = @acme
    Current.organization_membership = organization_memberships(:customer_admin_acme)
  end

  test 'index? returns true for a customer with an active membership' do
    act_as_acme_admin
    assert AssistantSavedPromptPolicy.new(@customer_admin, AssistantSavedPrompt).index?
  end

  test 'create? returns true for a customer and false for amplifa_admin' do
    act_as_acme_admin
    assert AssistantSavedPromptPolicy.new(@customer_admin, AssistantSavedPrompt).create?
    assert_not AssistantSavedPromptPolicy.new(accounts(:amplifa_admin), AssistantSavedPrompt).create?
  end

  test 'show? returns true for the owner in the matching organization' do
    act_as_acme_admin
    assert AssistantSavedPromptPolicy.new(@customer_admin, @owned_prompt).show?
  end

  test 'show? returns false for a colleague in the same organization' do
    act_as_acme_admin
    assert_not AssistantSavedPromptPolicy.new(@customer_admin, create_prompt_for(@customer_user)).show?
  end

  test 'show? returns false for a prompt in another organization' do
    act_as_acme_admin
    assert_not AssistantSavedPromptPolicy.new(@customer_admin, @foreign_prompt).show?
  end

  test 'scope returns only the current account prompts in the active organization' do
    act_as_acme_admin
    colleague_prompt = create_prompt_for(@customer_user)

    ids = AssistantSavedPromptPolicy::Scope.new(@customer_admin, AssistantSavedPrompt.all).resolve.pluck(:id)

    assert_includes ids, @owned_prompt.id
    assert_not_includes ids, colleague_prompt.id
    assert_not_includes ids, @foreign_prompt.id
  end

  private

  def create_prompt_for(account)
    AssistantSavedPrompt.create!(
      account: account,
      organization: @acme,
      title: 'Colleague prompt',
      prompt: 'Show me my meetings'
    )
  end
end
