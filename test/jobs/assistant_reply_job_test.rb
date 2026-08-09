require 'test_helper'

class AssistantReplyJobTest < ActiveJob::TestCase
  setup do
    @chat = chats(:acme_admin_chat)
    @chat.update!(streaming: true)
  end

  test 'persists the reply and releases the streaming lock' do
    stub_reply(success: true) do
      AssistantReplyJob.perform_now(@chat.id)
    end

    assert_not @chat.reload.streaming?, 'the composer stays disabled forever if the lock is not released'
  end

  test 'releases the streaming lock when generation fails' do
    stub_reply(success: false) do
      AssistantReplyJob.perform_now(@chat.id)
    end

    assert_not @chat.reload.streaming?
  end

  # WHY this is the important one: without the `ensure`, an exception would leave `streaming` true and
  # every future prompt on this chat would be rejected with 409 until someone edited the database.
  test 'releases the streaming lock even when the service raises' do
    exploding = ->(*) { raise 'provider exploded' }

    AssistantReplyService.stub(:call, exploding) do
      assert_raises(RuntimeError) { AssistantReplyJob.perform_now(@chat.id) }
    end

    assert_not @chat.reload.streaming?
  end

  test 'broadcasts a terminal error frame so the UI stops waiting' do
    frames = capture_broadcasts do
      stub_reply(success: false, error: :llm_unavailable) do
        AssistantReplyJob.perform_now(@chat.id)
      end
    end

    error_frame = frames.find { |frame| frame[:type] == 'error' }
    assert error_frame, 'a failed turn must broadcast an error frame'
    assert_equal 'llm_unavailable', error_frame[:error]
  end

  test 'enqueues a summary job once the thread is long enough' do
    create_messages(Chat::SUMMARY_EVERY)

    assert_enqueued_with job: AssistantSummaryJob, args: [@chat.id] do
      stub_reply(success: true) do
        AssistantReplyJob.perform_now(@chat.id)
      end
    end
  end

  test 'does not enqueue a summary job for a short thread' do
    create_messages(4)

    assert_no_enqueued_jobs only: AssistantSummaryJob do
      stub_reply(success: true) do
        AssistantReplyJob.perform_now(@chat.id)
      end
    end
  end

  test 'does not summarise after a failed turn' do
    create_messages(Chat::SUMMARY_EVERY)

    # WHY: folding a half-finished exchange into the summary would bake the failure into context.
    assert_no_enqueued_jobs only: AssistantSummaryJob do
      stub_reply(success: false) do
        AssistantReplyJob.perform_now(@chat.id)
      end
    end
  end

  test 'discards silently when the chat is gone' do
    assert_nothing_raised do
      AssistantReplyJob.perform_now(-999)
    end
  end

  private

  def create_messages(count)
    count.times do |index|
      @chat.messages.create!(role: index.even? ? 'user' : 'assistant', content: "Message #{index}")
    end
  end

  def stub_reply(success:, error: :unexpected, &block)
    result = AssistantReplyService::Result.new(success?: success, error: success ? nil : error, message: nil)

    AssistantReplyService.stub(:call, ->(*) { result }, &block)
  end

  def capture_broadcasts
    frames = []
    AssistantChatChannel.stub(:broadcast_to, ->(_chat, payload) { frames << payload }) do
      yield
    end
    frames
  end
end
