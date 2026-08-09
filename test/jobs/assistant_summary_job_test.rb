require 'test_helper'

class AssistantSummaryJobTest < ActiveJob::TestCase
  # The prompt the stubbed model was last asked with; set by `stub_llm`.
  attr_reader :captured_prompt

  setup do
    @chat = chats(:acme_admin_chat)
    @chat.messages.destroy_all
  end

  test 'summarises everything older than the verbatim tail and records the watermark' do
    create_messages(30)

    stub_llm('The user asked about inbox triage.') do
      AssistantSummaryJob.perform_now(@chat.id)
    end

    @chat.reload
    assert_equal 'The user asked about inbox triage.', @chat.summary
    assert_equal 30 - AssistantSummaryJob::KEEP_VERBATIM, @chat.summarized_message_count
  end

  test 'leaves the most recent messages verbatim' do
    create_messages(30)

    stub_llm('Summary.') do
      AssistantSummaryJob.perform_now(@chat.id)
    end

    # WHY this is the point of the feature: the summary replaces the head of the thread, and exactly
    # KEEP_VERBATIM messages must still be replayed word-for-word.
    assert_equal AssistantSummaryJob::KEEP_VERBATIM, @chat.reload.messages_after_summary.count
  end

  test 'only sends the unsummarised head to the model' do
    create_messages(30)

    stub_llm('Summary.') do
      AssistantSummaryJob.perform_now(@chat.id)
    end

    assert_includes captured_prompt, 'Message 0', 'the oldest message belongs in the summary prompt'
    assert_includes captured_prompt, 'Message 19', 'everything up to the watermark belongs in the prompt'
    assert_not_includes captured_prompt, 'Message 29', 'the verbatim tail must not be summarised'
  end

  test 'feeds the previous summary back in so earlier context survives' do
    create_messages(30)
    @chat.update!(summary: 'Earlier: the user set up a playbook.', summarized_message_count: 5)

    stub_llm('Updated summary.') do
      AssistantSummaryJob.perform_now(@chat.id)
    end

    assert_includes captured_prompt, 'Earlier: the user set up a playbook.',
                    'rolling summaries must build on the previous one, not discard it'
  end

  test 'does nothing when the watermark has already been reached' do
    create_messages(12)
    @chat.update!(summary: 'Existing.', summarized_message_count: 12 - AssistantSummaryJob::KEEP_VERBATIM)

    # WHY assert no LLM call at all: duplicate enqueues are expected (jobs can be retried or raced),
    # and re-summarising the same watermark would silently burn tokens.
    exploding = ->(*) { raise 'the model must not be called' }
    RubyLLM.stub(:chat, exploding) do
      AssistantSummaryJob.perform_now(@chat.id)
    end

    assert_equal 'Existing.', @chat.reload.summary
  end

  test 'does nothing for a short conversation' do
    create_messages(AssistantSummaryJob::KEEP_VERBATIM)

    exploding = ->(*) { raise 'the model must not be called' }
    RubyLLM.stub(:chat, exploding) do
      AssistantSummaryJob.perform_now(@chat.id)
    end

    assert_nil @chat.reload.summary
  end

  test 'keeps the previous summary when the model returns nothing usable' do
    create_messages(30)
    @chat.update!(summary: 'Still useful.', summarized_message_count: 3)

    stub_llm('   ') do
      AssistantSummaryJob.perform_now(@chat.id)
    end

    @chat.reload
    assert_equal 'Still useful.', @chat.summary
    assert_equal 3, @chat.summarized_message_count, 'a blank summary must not advance the watermark'
  end

  test 'discards silently when the chat is gone' do
    assert_nothing_raised do
      AssistantSummaryJob.perform_now(-999)
    end
  end

  test 'system and tool messages are neither summarised nor counted' do
    create_messages(30)
    @chat.messages.create!(role: 'system', content: 'You are a helpful assistant.')

    stub_llm('Summary.') do
      AssistantSummaryJob.perform_now(@chat.id)
    end

    # The watermark counts visible turns only, so the system row must not shift it.
    assert_equal 30 - AssistantSummaryJob::KEEP_VERBATIM, @chat.reload.summarized_message_count
  end

  private

  def create_messages(count)
    count.times do |index|
      @chat.messages.create!(role: index.even? ? 'user' : 'assistant', content: "Message #{index}")
    end
  end

  # Replaces RubyLLM.chat with a double that returns `reply`, and records the prompt it was asked with
  # in `captured_prompt` so tests can assert on the context that was actually sent.
  def stub_llm(reply)
    response = Struct.new(:content).new(reply)
    prompts = []

    fake_chat = Object.new
    fake_chat.define_singleton_method(:ask) do |prompt|
      prompts << prompt
      response
    end

    RubyLLM.stub(:chat, ->(*) { fake_chat }) { yield }
    @captured_prompt = prompts.last
  end
end
