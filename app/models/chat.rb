# frozen_string_literal: true

# An assistant conversation. Backed by ruby_llm's `acts_as_chat`, which supplies the
# `messages`/`model` associations and the `ask`/`complete` LLM plumbing.
#
# WHY account_id AND organization_id: a chat is private to one user inside one workspace. A user
# with memberships in two organizations gets a separate chat list per workspace, so a chat can never
# surface data from the wrong tenant. See ChatPolicy::Scope.
class Chat < ApplicationRecord
  acts_as_chat

  # WHY: Every SUMMARY_EVERY messages, AssistantSummaryJob compresses everything older into
  # `summary` so the replayed context stays bounded no matter how long the thread grows.
  SUMMARY_EVERY = 20

  # WHY: How many messages the UI loads per page, both on first render and per scroll-up fetch.
  MESSAGES_PER_PAGE = 20

  # WHY: How many chats the sidebar loads per page, both on first render and per "Load more" fetch.
  CHATS_PER_PAGE = 20

  TITLE_MAX_LENGTH = 60

  belongs_to :account
  belongs_to :organization

  # WHY before_validation and not before_save: ruby_llm registers its resolver as a `before_save`, and
  # `acts_as_chat` above runs first, so a `before_save` of ours would land *after* the raise. Every
  # before_validation runs earlier than every before_save, which is the only ordering that preempts it.
  #
  # WHY on every save and not just :create: fixtures and seeds insert rows without callbacks, so an
  # existing chat can reach an `update!` with no model attached and blow up there instead.
  before_validation :assign_default_model

  validates :title, length: { maximum: 255 }, allow_nil: true
  validates :summarized_message_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :active, -> { where(archived_at: nil) }
  scope :recent, -> { order(Arel.sql('pinned DESC, COALESCE(last_message_at, created_at) DESC, id DESC')) }

  # WHY: Only user/assistant turns are shown or counted. System prompts and tool plumbing are
  # implementation details the user never sees.
  #
  # WHY `reorder` and not `order`: `acts_as_chat` declares the association with a default
  # `order(created_at: :asc)`, so a plain `.order(:id)` would append to it and leave `created_at`
  # as the primary key of the sort. Messages written in the same clock tick would then page in an
  # unstable order and the `before_id` cursor could skip or repeat rows. `id` is the only
  # monotonic, unique ordering available, so it replaces the default outright.
  def visible_messages
    messages.where(role: %w[user assistant]).reorder(:id)
  end

  # WHY this exists separately from `visible_messages`: the assistant row is inserted with an empty body
  # before the first token arrives. Including it would render a blank bubble, and — worse — it would make
  # the client's `since_id` cursor equal to a row that has no content yet, so the catch-up poll would ask
  # for messages *after* the very row it is waiting for and never receive the reply.
  def renderable_messages
    visible_messages.where.not(content: [nil, ''])
  end

  def summary?
    summary.present?
  end

  # WHY: Messages already folded into `summary` must not be replayed to the LLM as well, or the
  # thread would be sent twice. This is the watermark that splits "summarised" from "verbatim".
  def messages_after_summary
    scope = visible_messages
    return scope unless summary?

    scope.offset(summarized_message_count)
  end

  def summary_due?
    visible_messages.count - summarized_message_count >= SUMMARY_EVERY
  end

  private

  # WHY: `acts_as_chat` installs a `before_save` that resolves the *configured default* model through
  # the RubyLLM registry. That registry is only populated when an OpenRouter key is present (see
  # RubyLlmRegistrySeed, which deliberately no-ops in test), so without this a plain `Chat.create!`
  # raises ModelNotFoundError — the chat could not even be created in a key-less environment.
  # Attaching the `models` row up front leaves `model_association` non-nil, which makes ruby_llm's
  # resolver a no-op. The record is the source of truth the app already uses elsewhere.
  def assign_default_model
    return if model_association

    self.model = Model.find_or_create_by!(
      model_id: AssistantReplyService::MODEL,
      provider: AssistantReplyService::PROVIDER.to_s
    ) { |model| model.name = AssistantReplyService::MODEL }
  end
end
