require 'test_helper'

class AssistantReplyServiceTest < ActiveSupport::TestCase
  setup do
    @chat = chats(:acme_admin_chat)
    @chat.messages.destroy_all
    @chat.messages.create!(role: 'user', content: 'Which replies need an answer?')
  end

  test 'persists the streamed reply and reports success' do
    result = stub_llm(chunks: ['You have ', 'two unread replies.']) do
      AssistantReplyService.call(chat: @chat)
    end

    assert result.success?
    assert_nil result.error
    assert_equal 'You have two unread replies.', @chat.messages.where(role: 'assistant').sole.content
  end

  test 'broadcasts start, deltas and a terminal done frame' do
    frames = capture_broadcasts do
      stub_llm(chunks: %w[Hello there]) { AssistantReplyService.call(chat: @chat) }
    end

    assert_equal 'start', frames.first[:type]
    assert_equal 'done', frames.last[:type]
    assert_equal 'Hellothere', frames.last[:content]
  end

  test 'replays only the messages after the summary watermark' do
    @chat.messages.destroy_all
    6.times { |index| @chat.messages.create!(role: index.even? ? 'user' : 'assistant', content: "Message #{index}") }
    @chat.update!(summary: 'Earlier the user asked about playbooks.', summarized_message_count: 4)

    fake_chat = build_fake_chat(chunks: ['ok'], raises: nil)
    RubyLLM.stub(:chat, ->(*) { fake_chat }) { AssistantReplyService.call(chat: @chat) }

    # The first four messages are represented by the summary, so only the tail is sent verbatim.
    assert_equal ['Message 4', 'Message 5'], fake_chat.replayed
  end

  test 'fails cleanly and leaves no empty bubble when the provider errors' do
    error = RubyLLM::Error.new(nil, 'upstream is down')

    result = stub_llm(raises: error) { AssistantReplyService.call(chat: @chat) }

    assert_not result.success?
    assert_equal :llm_unavailable, result.error
    assert_empty @chat.messages.where(role: 'assistant'),
                 'an empty assistant row would be replayed as context and rendered as a blank reply'
  end

  test 'treats an empty completion as a failure' do
    result = stub_llm(chunks: []) { AssistantReplyService.call(chat: @chat) }

    assert_not result.success?
    assert_equal :empty_completion, result.error
    assert_empty @chat.messages.where(role: 'assistant')
  end

  test 'registers the inbox tools scoped to the chat account and organization' do
    fake_chat = build_fake_chat(chunks: ['ok'], raises: nil)
    RubyLLM.stub(:chat, ->(*) { fake_chat }) { AssistantReplyService.call(chat: @chat) }

    assert_equal AssistantReplyService::TOOL_CLASSES.map { |klass| klass.name.demodulize.underscore.delete_suffix('_tool') }.sort,
                 fake_chat.registered_tools.map(&:name).sort

    fake_chat.registered_tools.each do |tool|
      # WHY: a tool bound to the wrong tenant would silently leak another organization's inbox.
      assert_equal @chat.account, tool.instance_variable_get(:@account)
      assert_equal @chat.organization, tool.instance_variable_get(:@organization)
    end
  end

  test 'establishes the tenant context for the duration of the turn' do
    observed = nil
    fake_chat = build_fake_chat(chunks: ['ok'], raises: nil)
    fake_chat.define_singleton_method(:complete) do |&block|
      observed = [Current.organization, Current.organization_membership]
      block.call(Struct.new(:content).new('ok'))
      Struct.new(:content).new('ok')
    end

    RubyLLM.stub(:chat, ->(*) { fake_chat }) { AssistantReplyService.call(chat: @chat) }

    # WHY: Pundit scopes resolve the tenant from Current, which is empty in a background job.
    # Without this every tool would fail closed and the assistant would see an empty workspace.
    assert_equal @chat.organization, observed[0]
    assert_equal organization_memberships(:customer_admin_acme), observed[1]
    assert_nil Current.organization, 'the tenant context must not leak outside the turn'
  end

  test 'does not leak the provider message to the caller' do
    error = RubyLLM::Error.new(nil, 'sk-secret-key rejected by https://internal.example')

    result = stub_llm(raises: error) { AssistantReplyService.call(chat: @chat) }

    # WHY: the Result carries a symbol the frontend maps to a t() string; raw provider text can
    # contain keys and internal URLs.
    assert_equal :llm_unavailable, result.error
    assert_kind_of Symbol, result.error
  end

  private

  # Stubs RubyLLM.chat with a double that yields `chunks` to the streaming block, or raises.
  def stub_llm(chunks: [], raises: nil)
    fake_chat = build_fake_chat(chunks: chunks, raises: raises)

    RubyLLM.stub(:chat, ->(*) { fake_chat }) { yield }
  end

  def build_fake_chat(chunks:, raises:)
    fake_chat = Object.new
    replayed = []
    registered_tools = []

    fake_chat.define_singleton_method(:with_instructions) { |*| self }
    fake_chat.define_singleton_method(:with_tools) { |*tools| registered_tools.concat(tools) && self }
    fake_chat.define_singleton_method(:on_tool_call) { |&| self }
    fake_chat.define_singleton_method(:on_tool_result) { |&| self }
    fake_chat.define_singleton_method(:add_message) { |content:, **| replayed << content }
    fake_chat.define_singleton_method(:replayed) { replayed }
    fake_chat.define_singleton_method(:registered_tools) { registered_tools }
    fake_chat.define_singleton_method(:complete) do |&block|
      raise raises if raises

      chunks.each { |chunk| block.call(Struct.new(:content).new(chunk)) }
      Struct.new(:content).new(chunks.join)
    end

    fake_chat
  end

  def capture_broadcasts
    frames = []
    AssistantChatChannel.stub(:broadcast_to, ->(_chat, payload) { frames << payload }) do
      yield
    end
    frames
  end
end
