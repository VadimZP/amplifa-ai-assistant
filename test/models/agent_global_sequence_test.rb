require 'test_helper'

class AgentGlobalSequenceTest < ActiveSupport::TestCase
  test 'effective sequence steps come from assigned global sequence' do
    agent = agents(:global_sequence_agent)

    assert_equal [
      sequence_steps(:global_step_one_email).id,
      sequence_steps(:global_step_two_email).id
    ], agent.effective_sequence_steps.ordered.pluck(:id)
  end
end
