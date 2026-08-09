# frozen_string_literal: true

require 'test_helper'

class AssistantPromptTest < ActiveSupport::TestCase
  setup do
    @organization = organizations(:acme)
    @account = accounts(:customer_admin)
  end

  test 'system prompt includes tool-first master rules' do
    prompt = AssistantPrompt.system_prompt(organization: @organization, account: @account)

    assert_includes prompt, 'Tool-first rule (mandatory)'
    assert_includes prompt, 'only source of truth'
    assert_includes prompt, 'first action in this turn MUST be'
    assert_includes prompt, 'a tool call, not a text reply'
    assert_includes prompt, 'Never claim a lead, conversation, meeting, or agent does not exist'
    assert_includes prompt, 'Never invent IDs, counts, statuses'
  end

  test 'system prompt includes intent routing for workspace domains' do
    prompt = AssistantPrompt.system_prompt(organization: @organization, account: @account)

    assert_includes prompt, 'Intent routing'
    assert_includes prompt, 'conversation_list or conversation_stats'
    assert_includes prompt, 'lead_search'
    assert_includes prompt, 'agent_list or agent_stats'
    assert_includes prompt, 'meeting_list'
    assert_includes prompt, 'conversation_update_interest_status'
  end

  test 'system prompt includes named-person lookup playbook' do
    prompt = AssistantPrompt.system_prompt(organization: @organization, account: @account)

    assert_includes prompt, 'Named-person lookup playbook'
    assert_includes prompt, 'retry with the first word, then the last'
    assert_includes prompt, 'word separately'
    assert_includes prompt, 'ask which one the user means'
  end

  test 'system prompt personalizes organization and account' do
    prompt = AssistantPrompt.system_prompt(organization: @organization, account: @account)

    assert_includes prompt, @account.full_name
    assert_includes prompt, @organization.name
  end
end
