# frozen_string_literal: true

# Customer-facing AI assistant (ChatGPT-style multi-chat).
#
# WHY the reply is not generated here: LLM calls take seconds. `create_message` persists the prompt,
# returns immediately so the UI can render it optimistically, and hands generation to
# AssistantReplyJob which streams tokens back over AssistantChatChannel.
class AssistantController < ApplicationController
  MAX_PROMPT_LENGTH = 8_000

  # WHY: Chat ids come from the client and `policy_scope` turns a foreign id into RecordNotFound.
  # Convert that into a clean 404 / redirect instead of a 500.
  rescue_from ActiveRecord::RecordNotFound, with: :record_not_found

  def index
    # WHY the redirects come before `authorize`: ChatPolicy denies both of these cases, and Pundit's
    # NotAuthorizedError handler bounces to the root path with a scary "not authorized" flash. Sending
    # an admin to their own dashboard (as RoiController does) is the accurate outcome — the assistant
    # isn't forbidden to them, it just has no workspace to run in.
    if current_account.amplifa_admin?
      skip_policy_scope
      return redirect_to admin_dashboard_path
    end

    if Current.organization.nil?
      skip_policy_scope
      return redirect_to no_workspace_path
    end

    authorize Chat, :index?
    authorize AssistantSavedPrompt, :index?

    scope = policy_scope(Chat).active.recent
    page = chat_page(scope, page: 1)
    chats = page[:chats]

    selected = if params[:id].present?
                 find_chat!
               end

    # WHY: A deep link to a chat beyond page 1 must still highlight it in the sidebar.
    if selected && chats.none? { |chat| chat.id == selected.id }
      chats.unshift(selected)
    end

    render inertia: 'Assistant/Index', props: index_props(chats, selected, has_more_chats: page[:has_more])
  end

  # WHY a prompt is required: "New chat" is just /assistant in the UI. Creating a row here only when
  # the user sends their first message keeps empty chats out of the database.
  def create
    authorize Chat, :create?

    prompt = params[:prompt].to_s.strip

    if prompt.blank?
      return redirect_to assistant_path, alert: t('assistant.errors.blank_prompt')
    end

    if prompt.length > MAX_PROMPT_LENGTH
      return redirect_to assistant_path, alert: t('assistant.errors.prompt_too_long', count: MAX_PROMPT_LENGTH)
    end

    chat = Chat.new(account: current_account, organization: Current.organization)

    unless chat.save
      return redirect_to assistant_path, alert: t('assistant.errors.create_chat')
    end

    start_conversation(chat, prompt)

    redirect_to assistant_conversation_path(chat)
  end

  def destroy
    chat = find_chat!
    authorize chat, :destroy?
    chat.destroy!

    # WHY `suppress_flash`: the layout renders flash as an inline banner that pushes the chat UI down
    # and never leaves. The assistant reports both outcomes as a toast instead (see Assistant/Index),
    # so the banner is suppressed the same way RoiController does it.
    redirect_to assistant_path(suppress_flash: true), notice: t('assistant.flash.chat_deleted')
  rescue ActiveRecord::RecordNotDestroyed
    redirect_to assistant_path(suppress_flash: true), alert: t('assistant.errors.delete_chat')
  end

  # GET /assistant/chats — paginated sidebar list for "Load more".
  def list_chats
    authorize Chat, :index?

    scope = policy_scope(Chat).active.recent
    page = chat_page(scope, page: chat_list_page)

    render json: { chats: page[:chats].map { |chat| chat_json(chat) }, has_more: page[:has_more] }
  end

  # GET /assistant/prompts — saved prompts for the current user in the active workspace.
  def list_prompts
    authorize AssistantSavedPrompt, :index?

    prompts = policy_scope(AssistantSavedPrompt).recent

    render json: { prompts: prompts.map { |prompt| saved_prompt_json(prompt) } }
  end

  # POST /assistant/prompts
  def create_prompt
    authorize AssistantSavedPrompt, :create?

    prompt = policy_scope(AssistantSavedPrompt).build(saved_prompt_attributes)
    prompt.account = current_account
    prompt.organization = Current.organization

    if prompt.save
      render json: { prompt: saved_prompt_json(prompt) }, status: :created
    else
      render json: { error: saved_prompt_error_message(prompt) }, status: :unprocessable_entity
    end
  end

  # PATCH /assistant/prompts/:id
  def update_prompt
    prompt = find_saved_prompt!
    authorize prompt, :update?

    if prompt.update(saved_prompt_attributes)
      render json: { prompt: saved_prompt_json(prompt) }
    else
      render json: { error: saved_prompt_error_message(prompt) }, status: :unprocessable_entity
    end
  end

  # DELETE /assistant/prompts/:id
  def destroy_prompt
    prompt = find_saved_prompt!
    authorize prompt, :destroy?
    prompt.destroy!

    head :no_content
  rescue ActiveRecord::RecordNotDestroyed
    render json: { error: t('assistant.errors.delete_saved_prompt') }, status: :unprocessable_entity
  end

  # PATCH /assistant/chats/:id/pin
  def pin
    chat = find_chat!
    authorize chat, :pin?

    pinned = ActiveModel::Type::Boolean.new.cast(params[:pinned])
    chat.update!(pinned: pinned)

    render json: { chat: chat_json(chat) }
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.to_sentence.presence || t('assistant.errors.pin_chat') },
           status: :unprocessable_entity
  end

  # POST /assistant/chats/:id/messages
  def create_message
    chat = find_chat!
    authorize chat, :create_message?

    prompt = params[:prompt].to_s.strip

    if prompt.blank?
      return render json: { error: t('assistant.errors.blank_prompt') }, status: :unprocessable_entity
    end

    if prompt.length > MAX_PROMPT_LENGTH
      return render json: { error: t('assistant.errors.prompt_too_long', count: MAX_PROMPT_LENGTH) },
                    status: :unprocessable_entity
    end

    # WHY: Refuse a second prompt while one is in flight, so the thread cannot interleave two
    # assistant turns and produce out-of-order history.
    if chat.streaming?
      return render json: { error: t('assistant.errors.already_streaming') }, status: :conflict
    end

    message = persist_prompt!(chat, prompt)
    AssistantReplyJob.perform_later(chat.id, message.id)

    render json: { chat: chat_json(chat.reload), message: message_json(message) }, status: :created
  end

  # GET /assistant/chats/:id/messages — pages backwards through history.
  def messages
    chat = find_chat!
    authorize chat, :show?

    # WHY two cursors: `before_id` pages backwards for infinite scroll, `since_id` catches up on
    # messages that arrived while the cable was down or not yet subscribed.
    if params[:since_id].present?
      # `title` rides along because AssistantTitleJob also broadcasts into the same pre-subscribe gap.
      return render json: { messages: messages_since(chat, params[:since_id]).map { |m| message_json(m) },
                            has_more: false,
                            streaming: chat.streaming?,
                            title: chat.title }
    end

    page = message_page(chat, before_id: params[:before_id])

    # WHY `streaming` is included: the client calls this on every cable (re)connect to resync. Frames
    # broadcast before the subscription existed are gone, so `streaming` is the only way for the client
    # to tell "a reply is still coming" from "it already finished and I missed it".
    render json: { messages: page[:messages].map { |message| message_json(message) },
                   has_more: page[:has_more],
                   streaming: chat.streaming? }
  end

  private

  def find_chat!
    policy_scope(Chat).find(params[:id])
  end

  def find_saved_prompt!
    policy_scope(AssistantSavedPrompt).find(params[:id])
  end

  # WHY it swallows failures: the chat itself was created, so the user still lands on a usable page.
  # Losing the seed prompt is recoverable (they retype); a 500 on the redirect is not.
  def start_conversation(chat, prompt)
    message = persist_prompt!(chat, prompt)
    AssistantReplyJob.perform_later(chat.id, message.id)
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error("[AssistantController] failed to seed chat ##{chat.id}: #{e.class}: #{e.message}")
  end

  def persist_prompt!(chat, prompt)
    Chat.transaction do
      message = chat.messages.create!(role: 'user', content: prompt)
      # WHY: `streaming` is the server-side lock the guard above reads, and `last_message_at` drives
      # sidebar ordering. Set together so the chat jumps to the top the moment the prompt lands.
      chat.update!(streaming: true, last_message_at: Time.current)
      # WHY: The very first prompt is what the title is derived from, so enqueue it only once.
      AssistantTitleJob.perform_later(chat.id) if chat.title.blank?
      message
    end
  end

  # WHY: The newest page is loaded on first render; scrolling up pages backwards with a `before_id`
  # cursor. A cursor (not OFFSET) means new messages arriving mid-scroll can't shift the window.
  def message_page(chat, before_id: nil)
    # `renderable_messages`: never hand the client the empty in-flight assistant row (see Chat).
    scope = chat.renderable_messages
    scope = scope.where(id: ...before_id.to_i) if before_id.present?

    # WHY: Fetch one extra row to learn whether an older page exists without a second COUNT query.
    # WHY `reorder`: `visible_messages` is already ordered ascending, and `order` would append rather
    # than replace, leaving the newest-first limit reading from the wrong end of the thread.
    rows = scope.reorder(id: :desc).limit(Chat::MESSAGES_PER_PAGE + 1).to_a
    has_more = rows.size > Chat::MESSAGES_PER_PAGE

    { messages: rows.first(Chat::MESSAGES_PER_PAGE).reverse, has_more: has_more }
  end

  # WHY `>=` and not `>`: the client's cursor is the id of the newest row it holds, and that row may be a
  # partially-streamed assistant message. A strict `>` would exclude the very message the client is
  # waiting to have filled in, which is exactly how a missed frame became a permanent spinner.
  def messages_since(chat, since_id)
    chat.renderable_messages.where('messages.id >= ?', since_id.to_i).to_a
  end

  def index_props(chats, selected, has_more_chats: false)
    saved_prompts = policy_scope(AssistantSavedPrompt).recent

    props = {
      chats: chats.map { |chat| chat_json(chat) },
      has_more_chats: has_more_chats,
      selected_chat_id: selected&.id,
      messages: [],
      has_more_messages: false,
      user_first_name: current_account.first_name,
      max_prompt_length: MAX_PROMPT_LENGTH,
      saved_prompts: saved_prompts.map { |prompt| saved_prompt_json(prompt) }
    }

    if selected
      page = message_page(selected)
      props[:messages] = page[:messages].map { |message| message_json(message) }
      props[:has_more_messages] = page[:has_more]
    end

    props
  end

  def chat_json(chat)
    {
      id: chat.id,
      title: chat.title,
      streaming: chat.streaming?,
      pinned: chat.pinned?,
      last_message_at: chat.last_message_at&.iso8601,
      created_at: chat.created_at.iso8601
    }
  end

  def chat_page(scope, page: 1)
    offset = (page - 1) * Chat::CHATS_PER_PAGE
    rows = scope.offset(offset).limit(Chat::CHATS_PER_PAGE + 1).to_a
    has_more = rows.size > Chat::CHATS_PER_PAGE

    { chats: rows.first(Chat::CHATS_PER_PAGE), has_more: has_more }
  end

  def chat_list_page
    page = params[:page].to_i
    page.positive? ? page : 1
  end

  def message_json(message)
    {
      id: message.id,
      role: message.role,
      content: message.content.to_s,
      created_at: message.created_at.iso8601
    }
  end

  def saved_prompt_json(prompt)
    {
      id: prompt.id,
      title: prompt.title,
      prompt: prompt.prompt,
      welcome_pinned: prompt.welcome_pinned?,
      position: prompt.position,
      updated_at: prompt.updated_at.iso8601
    }
  end

  def saved_prompt_attributes
    attrs = params.permit(:title, :prompt, :welcome_pinned, :position)
    attrs[:title] = attrs[:title].to_s.strip if attrs.key?(:title)
    attrs[:prompt] = attrs[:prompt].to_s.strip if attrs.key?(:prompt)
    attrs[:welcome_pinned] = ActiveModel::Type::Boolean.new.cast(attrs[:welcome_pinned]) if attrs.key?(:welcome_pinned)
    attrs
  end

  def saved_prompt_error_message(prompt)
    if prompt.errors.of_kind?(:welcome_pinned, :too_many)
      return t('assistant.errors.too_many_welcome_prompts', count: AssistantSavedPrompt::WELCOME_PINNED_LIMIT)
    end

    prompt.errors.full_messages.to_sentence.presence || t('assistant.errors.save_saved_prompt')
  end

  # WHY: A foreign or deleted chat id must be indistinguishable from one that never existed, so the
  # response can't be used to probe for other users' chats. XHR endpoints get a 404 with a friendly
  # message; page navigations silently bounce back to a clean assistant page.
  def record_not_found
    skip_authorization

    if prompt_action?
      render json: { error: t('assistant.errors.saved_prompt_not_found') }, status: :not_found
    elsif %w[create_message messages pin list_chats].include?(action_name)
      render json: { error: t('assistant.errors.chat_not_found') }, status: :not_found
    else
      redirect_to assistant_path
    end
  end

  def prompt_action?
    %w[list_prompts create_prompt update_prompt destroy_prompt].include?(action_name)
  end
end
