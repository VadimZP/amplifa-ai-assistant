require 'test_helper'

class AssistantControllerTest < ActionDispatch::IntegrationTest
  setup do
    @account = accounts(:customer_admin)
    @chat = chats(:acme_admin_chat)
    login_as @account
  end

  test 'index lists only the current account chats in the current organization' do
    get assistant_path, headers: inertia_headers

    assert_response :success
    assert_inertia_component 'Assistant/Index'

    chat_ids = inertia_props['chats'].map { |chat| chat['id'] }
    assert_includes chat_ids, @chat.id
    assert_not_includes chat_ids, chats(:acme_user_chat).id, 'a colleague chat must never be listed'
    assert_not_includes chat_ids, chats(:growth_lab_chat).id, 'a cross-org chat must never be listed'
    assert inertia_props['chats'].all? { |chat| chat.key?('pinned') }
  end

  test 'index returns at most one page of chats and flags that more exist' do
    create_chats(count: Chat::CHATS_PER_PAGE + 3)

    get assistant_path, headers: inertia_headers

    assert_response :success
    assert_operator inertia_props['chats'].size, :<=, Chat::CHATS_PER_PAGE + 1
    assert inertia_props['has_more_chats'], 'has_more_chats must be true when older chats exist'
  end

  test 'index lists pinned chats before unpinned regardless of recency' do
    older_pinned = create_chat(last_message_at: 2.days.ago, pinned: true)
    newer_unpinned = create_chat(last_message_at: 1.hour.ago, pinned: false)

    get assistant_path, headers: inertia_headers

    chat_ids = inertia_props['chats'].map { |chat| chat['id'] }
    assert_operator chat_ids.index(older_pinned.id), :<, chat_ids.index(newer_unpinned.id)
  end

  test 'index injects a deep-linked chat that is beyond page one into the sidebar' do
    create_chats(count: Chat::CHATS_PER_PAGE)
    distant = create_chat(last_message_at: 30.days.ago)

    get assistant_conversation_path(distant), headers: inertia_headers

    assert_response :success
    assert_includes inertia_props['chats'].map { |chat| chat['id'] }, distant.id
  end

  test 'list_chats returns the requested page with has_more' do
    create_chats(count: Chat::CHATS_PER_PAGE + 1)

    get assistant_chat_list_path, params: { page: 2 }, headers: { 'Accept' => 'application/json' }

    assert_response :success
    payload = response.parsed_body
    assert_equal 2, payload['chats'].size
    assert_not payload['has_more']
  end

  test 'pin toggles pinned for the owner' do
    patch assistant_chat_pin_path(@chat),
          params: { pinned: true },
          headers: { 'Accept' => 'application/json' },
          as: :json

    assert_response :success
    assert response.parsed_body['chat']['pinned']
    assert @chat.reload.pinned?

    patch assistant_chat_pin_path(@chat),
          params: { pinned: false },
          headers: { 'Accept' => 'application/json' },
          as: :json

    assert_response :success
    assert_not response.parsed_body['chat']['pinned']
    assert_not @chat.reload.pinned?
  end

  test 'pin on a foreign chat is not found' do
    patch assistant_chat_pin_path(chats(:growth_lab_chat)),
          params: { pinned: true },
          headers: { 'Accept' => 'application/json' },
          as: :json

    assert_response :not_found
    assert_equal I18n.t('assistant.errors.chat_not_found'), response.parsed_body['error']
  end

  test 'index without a chat id renders no messages' do
    get assistant_path, headers: inertia_headers

    assert_response :success
    assert_nil inertia_props['selected_chat_id']
    assert_empty inertia_props['messages']
  end

  test 'index with a chat id renders that chat newest page' do
    get assistant_conversation_path(@chat), headers: inertia_headers

    assert_response :success
    assert_equal @chat.id, inertia_props['selected_chat_id']
    assert_equal @chat.visible_messages.count, inertia_props['messages'].size
  end

  test 'index returns at most one page of messages and flags that more exist' do
    create_messages(@chat, count: Chat::MESSAGES_PER_PAGE + 5)

    get assistant_conversation_path(@chat), headers: inertia_headers

    assert_response :success
    assert_equal Chat::MESSAGES_PER_PAGE, inertia_props['messages'].size
    assert inertia_props['has_more_messages'], 'has_more_messages must be true when older messages exist'
  end

  test 'index sends the newest messages, oldest first' do
    create_messages(@chat, count: Chat::MESSAGES_PER_PAGE + 5)
    # `visible_messages` is ordered oldest-first, so the newest page is simply its tail.
    newest_ids = @chat.visible_messages.pluck(:id).last(Chat::MESSAGES_PER_PAGE)

    get assistant_conversation_path(@chat), headers: inertia_headers

    assert_equal newest_ids, inertia_props['messages'].map { |message| message['id'] }
  end

  test 'index redirects a deep link to a foreign chat back to a clean assistant page' do
    get assistant_conversation_path(chats(:growth_lab_chat)), headers: inertia_headers

    assert_redirected_to assistant_path
    assert_nil flash[:alert]
  end

  test 'index redirects amplifa admins to the admin dashboard' do
    login_as accounts(:amplifa_admin)

    get assistant_path, headers: inertia_headers

    assert_redirected_to admin_dashboard_path
  end

  test 'create without a prompt does not create a chat' do
    assert_no_difference 'Chat.count' do
      post assistant_chats_path
    end

    assert_redirected_to assistant_path
    assert_equal I18n.t('assistant.errors.blank_prompt'), flash[:alert]
  end

  test 'create with a prompt seeds the first message and enqueues the reply' do
    assert_enqueued_with job: AssistantReplyJob do
      post assistant_chats_path, params: { prompt: 'Who replied yesterday?' }
    end

    chat = Chat.order(:id).last
    assert_equal 'Who replied yesterday?', chat.messages.sole.content
    assert chat.streaming?, 'seeding a prompt must take the streaming lock'
  end

  test 'create_message persists the prompt, locks the chat and enqueues the reply' do
    assert_enqueued_with job: AssistantReplyJob do
      post assistant_chat_messages_path(@chat), params: { prompt: 'And the second one?' }
    end

    assert_response :created

    payload = response.parsed_body
    assert_equal 'user', payload['message']['role']
    assert_equal 'And the second one?', payload['message']['content']
    assert @chat.reload.streaming?
  end

  test 'create_message enqueues a title job only for the first prompt' do
    untitled = Chat.create!(account: @account, organization: organizations(:acme))

    assert_enqueued_with job: AssistantTitleJob do
      post assistant_chat_messages_path(untitled), params: { prompt: 'First question' }
    end

    untitled.update!(streaming: false)

    assert_no_enqueued_jobs only: AssistantTitleJob do
      post assistant_chat_messages_path(untitled), params: { prompt: 'Second question' }
    end
  end

  test 'create_message rejects a blank prompt without touching the chat' do
    assert_no_difference 'Message.count' do
      post assistant_chat_messages_path(@chat), params: { prompt: '   ' }
    end

    assert_response :unprocessable_entity
    assert_equal I18n.t('assistant.errors.blank_prompt'), response.parsed_body['error']
    assert_not @chat.reload.streaming?
  end

  test 'create_message rejects an over-long prompt' do
    assert_no_difference 'Message.count' do
      post assistant_chat_messages_path(@chat),
           params: { prompt: 'a' * (AssistantController::MAX_PROMPT_LENGTH + 1) }
    end

    assert_response :unprocessable_entity
  end

  test 'create_message refuses a second prompt while a reply is streaming' do
    @chat.update!(streaming: true)

    assert_no_difference 'Message.count' do
      post assistant_chat_messages_path(@chat), params: { prompt: 'Are you there?' }
    end

    assert_response :conflict
    assert_equal I18n.t('assistant.errors.already_streaming'), response.parsed_body['error']
  end

  test 'create_message on a foreign chat is indistinguishable from a missing one' do
    assert_no_difference 'Message.count' do
      post assistant_chat_messages_path(chats(:growth_lab_chat)), params: { prompt: 'Leak?' }
    end

    assert_response :not_found
    assert_equal I18n.t('assistant.errors.chat_not_found'), response.parsed_body['error']
  end

  test 'create_message on a colleague chat in the same organization is not found' do
    assert_no_difference 'Message.count' do
      post assistant_chat_messages_path(chats(:acme_user_chat)), params: { prompt: 'Leak?' }
    end

    assert_response :not_found
  end

  test 'messages pages backwards from a cursor' do
    create_messages(@chat, count: Chat::MESSAGES_PER_PAGE + 5)
    all_ids = @chat.visible_messages.order(:id).pluck(:id)
    cursor = all_ids[-Chat::MESSAGES_PER_PAGE]

    get assistant_chat_older_messages_path(@chat), params: { before_id: cursor }

    assert_response :success

    payload = response.parsed_body
    expected = all_ids.select { |id| id < cursor }.last(Chat::MESSAGES_PER_PAGE)
    assert_equal expected, payload['messages'].map { |message| message['id'] }
    assert_not payload['has_more'], 'the last page must not claim more history'
  end

  test 'messages caps a page at MESSAGES_PER_PAGE' do
    create_messages(@chat, count: Chat::MESSAGES_PER_PAGE * 3)

    get assistant_chat_older_messages_path(@chat)

    assert_response :success
    assert_equal Chat::MESSAGES_PER_PAGE, response.parsed_body['messages'].size
    assert response.parsed_body['has_more']
  end

  test 'messages on a foreign chat is not found' do
    get assistant_chat_older_messages_path(chats(:growth_lab_chat))

    assert_response :not_found
  end

  test 'destroy removes the chat and its messages' do
    assert_difference 'Chat.count', -1 do
      delete assistant_chat_path(@chat)
    end

    # WHY suppress_flash: the assistant surfaces outcomes as toasts; the layout's flash banner
    # would push the chat UI down (see AssistantController#destroy).
    assert_redirected_to assistant_path(suppress_flash: true)
    assert_equal I18n.t('assistant.flash.chat_deleted'), flash[:notice]
    assert_empty Message.where(chat_id: @chat.id)
  end

  test 'destroy on a foreign chat leaves it untouched' do
    foreign = chats(:growth_lab_chat)

    assert_no_difference 'Chat.count' do
      delete assistant_chat_path(foreign)
    end

    assert_redirected_to assistant_path
    assert_nil flash[:alert]
    assert Chat.exists?(foreign.id)
  end

  # WHY these exist: ActionCable has no replay, and with the :async adapter a reply can finish before the
  # browser has even subscribed. `since_id` is how the client recovers those missed frames — without it
  # the user waits on a spinner for a reply that already completed (observed in development).
  test 'since_id returns the cursor row and everything after it, and nothing older' do
    older = @chat.messages.create!(role: 'user', content: 'Older')
    cursor = @chat.messages.create!(role: 'user', content: 'Cursor row')
    newer = @chat.messages.create!(role: 'assistant', content: 'Newer')

    get assistant_chat_older_messages_path(@chat), params: { since_id: cursor.id },
                                                   headers: { 'Accept' => 'application/json' }

    assert_response :success
    ids = response.parsed_body['messages'].map { |message| message['id'] }
    assert_equal [cursor.id, newer.id], ids
    assert_not_includes ids, older.id
  end

  test 'since_id reports the streaming lock so the client can stop waiting' do
    @chat.update!(streaming: false)

    get assistant_chat_older_messages_path(@chat), params: { since_id: 0 },
                                                   headers: { 'Accept' => 'application/json' }

    assert_equal false, response.parsed_body['streaming']
  end

  test 'since_id omits the in-flight assistant row so no empty bubble renders' do
    cursor = @chat.messages.maximum(:id)
    blank = @chat.messages.create!(role: 'assistant', content: '')

    get assistant_chat_older_messages_path(@chat), params: { since_id: cursor },
                                                   headers: { 'Accept' => 'application/json' }

    assert_not_includes response.parsed_body['messages'].map { |message| message['id'] }, blank.id
  end

  # WHY the cursor is inclusive: this is the exact bug that made a reply never appear in development. The
  # client's newest row is the assistant message being streamed, so an exclusive `>` cursor asked for
  # messages after the very row it was waiting for and could never recover a missed frame.
  test 'since_id re-returns the cursor row itself so a stalled stream can repair' do
    streamed = @chat.messages.create!(role: 'assistant', content: 'Final streamed answer.')

    get assistant_chat_older_messages_path(@chat), params: { since_id: streamed.id },
                                                   headers: { 'Accept' => 'application/json' }

    payload = response.parsed_body
    assert_includes payload['messages'].map { |message| message['id'] }, streamed.id
    assert_equal 'Final streamed answer.', payload['messages'].last['content']
  end

  test 'index never sends the empty in-flight assistant row' do
    blank = @chat.messages.create!(role: 'assistant', content: '')

    get assistant_conversation_path(@chat), headers: inertia_headers

    assert_not_includes inertia_props['messages'].map { |message| message['id'] }, blank.id
  end

  test 'since_id carries the title, which is also broadcast into the pre-subscribe gap' do
    @chat.update!(title: 'Inbox triage')

    get assistant_chat_older_messages_path(@chat), params: { since_id: 0 },
                                                   headers: { 'Accept' => 'application/json' }

    assert_equal 'Inbox triage', response.parsed_body['title']
  end

  test 'since_id is scoped to the current user' do
    get assistant_chat_older_messages_path(chats(:growth_lab_chat)), params: { since_id: 0 },
                                                                     headers: { 'Accept' => 'application/json' }

    assert_response :not_found
  end

  test 'index includes saved prompts for the current account in the active organization' do
    owned = create_saved_prompt(title: 'My prompt', welcome_pinned: true)
    create_saved_prompt(account: accounts(:customer_user), title: 'Colleague prompt')
    create_saved_prompt(account: @account, organization: organizations(:growth_lab), title: 'Other org')

    get assistant_path, headers: inertia_headers

    assert_response :success
    prompt_ids = inertia_props['saved_prompts'].map { |prompt| prompt['id'] }
    assert_equal [owned.id], prompt_ids
    assert_equal 'My prompt', inertia_props['saved_prompts'].first['title']
    assert inertia_props['saved_prompts'].first['welcome_pinned']
  end

  test 'create_prompt saves a prompt for the current user' do
    post assistant_prompts_path,
         params: { title: 'Weekly stats', prompt: 'How is my inbox doing?', welcome_pinned: true },
         headers: { 'Accept' => 'application/json' },
         as: :json

    assert_response :created
    payload = response.parsed_body
    assert_equal 'Weekly stats', payload['prompt']['title']
    assert payload['prompt']['welcome_pinned']

    prompt = AssistantSavedPrompt.find(payload['prompt']['id'])
    assert_equal @account.id, prompt.account_id
    assert_equal organizations(:acme).id, prompt.organization_id
  end

  test 'update_prompt toggles welcome_pinned for the owner' do
    prompt = create_saved_prompt(welcome_pinned: false)

    patch assistant_prompt_path(prompt),
          params: { welcome_pinned: true },
          headers: { 'Accept' => 'application/json' },
          as: :json

    assert_response :success
    assert response.parsed_body['prompt']['welcome_pinned']
    assert prompt.reload.welcome_pinned?
  end

  test 'destroy_prompt removes the owners prompt' do
    prompt = create_saved_prompt

    delete assistant_prompt_destroy_path(prompt),
           headers: { 'Accept' => 'application/json' }

    assert_response :no_content
    assert_not AssistantSavedPrompt.exists?(prompt.id)
  end

  test 'update_prompt on a foreign prompt is not found' do
    foreign = AssistantSavedPrompt.create!(
      account: accounts(:growth_lab_admin),
      organization: organizations(:growth_lab),
      title: 'Foreign',
      prompt: 'Secret prompt'
    )

    patch assistant_prompt_path(foreign),
          params: { title: 'Hacked' },
          headers: { 'Accept' => 'application/json' },
          as: :json

    assert_response :not_found
    assert_equal I18n.t('assistant.errors.saved_prompt_not_found'), response.parsed_body['error']
  end

  test 'create_prompt rejects pinning more than the welcome limit' do
    AssistantSavedPrompt::WELCOME_PINNED_LIMIT.times do |index|
      create_saved_prompt(title: "Pinned #{index}", welcome_pinned: true)
    end

    post assistant_prompts_path,
         params: { title: 'One too many', prompt: 'Overflow', welcome_pinned: true },
         headers: { 'Accept' => 'application/json' },
         as: :json

    assert_response :unprocessable_entity
    assert_equal I18n.t('assistant.errors.too_many_welcome_prompts',
                        count: AssistantSavedPrompt::WELCOME_PINNED_LIMIT),
                 response.parsed_body['error']
  end

  private

  def create_chat(last_message_at:, pinned: false)
    Chat.create!(
      account: @account,
      organization: organizations(:acme),
      last_message_at: last_message_at,
      pinned: pinned
    )
  end

  def create_chats(count:)
    count.times do |index|
      create_chat(last_message_at: (count - index).hours.ago)
    end
  end

  # WHY roles alternate: `visible_messages` only counts user/assistant turns, and the paginator is
  # role-agnostic, so a realistic alternating transcript is what the assertions should page through.
  def create_messages(chat, count:)
    count.times do |index|
      chat.messages.create!(
        role: index.even? ? 'user' : 'assistant',
        content: "Filler message #{index}"
      )
    end
  end

  def create_saved_prompt(title: 'Saved prompt', prompt: 'Show me my inbox stats', welcome_pinned: false,
                          account: @account, organization: organizations(:acme))
    AssistantSavedPrompt.create!(
      account: account,
      organization: organization,
      title: title,
      prompt: prompt,
      welcome_pinned: welcome_pinned
    )
  end
end
