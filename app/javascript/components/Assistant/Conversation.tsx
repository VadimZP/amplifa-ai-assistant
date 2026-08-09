import { useCallback, useState } from 'react'
import { MessageList } from './MessageList'
import { Composer } from './Composer'
import { WelcomeScreen } from './WelcomeScreen'
import { useAssistantChat } from './useAssistantChat'
import { AssistantMessage, AssistantSavedPrompt } from './types'

interface ConversationProps {
  chatId: number
  initialMessages: AssistantMessage[]
  initialHasMore: boolean
  initialStreaming: boolean
  firstName: string
  maxPromptLength: number
  savedPrompts: AssistantSavedPrompt[]
  onTitle: (chatId: number, title: string) => void
  onManagePrompts: () => void
  onSavePrompt: (prompt: string) => void
}

/**
 * The message pane for one chat.
 *
 * WHY the page mounts this with `key={chatId}`: switching chats replaces every piece of local state
 * (messages, pagination cursor, stream position, scroll anchor). Remounting is both simpler and less
 * bug-prone than resetting six pieces of state in an effect.
 */
export function Conversation({
  chatId,
  initialMessages,
  initialHasMore,
  initialStreaming,
  firstName,
  maxPromptLength,
  savedPrompts,
  onTitle,
  onManagePrompts,
  onSavePrompt,
}: ConversationProps) {
  const [draft, setDraft] = useState('')
  const [reference, setReference] = useState<string | null>(null)
  const [focusToken, setFocusToken] = useState(0)

  const {
    messages,
    hasMore,
    loadingOlder,
    loadOlder,
    send,
    sending,
    awaitingReply,
    streamingMessageId,
    toolEventsByMessage,
  } = useAssistantChat({
    chatId,
    initialMessages,
    initialHasMore,
    initialStreaming,
    onTitle,
  })

  const handleSubmit = useCallback(async () => {
    const trimmedDraft = draft.trim()
    const savedReference = reference
    const prompt = savedReference ? `"${savedReference}"\n\n${trimmedDraft}` : trimmedDraft
    setDraft('')
    setReference(null)

    const sent = await send(prompt)
    // WHY restore the draft on failure: retyping a long prompt after a network blip is the most
    // annoying possible outcome, so the text goes back in the composer ready to resend.
    if (!sent) {
      setDraft(trimmedDraft)
      setReference(savedReference)
    }
    setFocusToken(token => token + 1)
  }, [draft, reference, send])

  const handleSuggestion = useCallback((prompt: string) => {
    setDraft(prompt)
    setFocusToken(token => token + 1)
  }, [])

  const handleAskAssistant = useCallback((text: string) => {
    setReference(text)
    setFocusToken(token => token + 1)
  }, [])

  const busy = sending || awaitingReply

  return (
    <>
      {messages.length === 0 && !awaitingReply ? (
        <div className="custom-scrollbar min-h-0 flex-1 overflow-y-auto">
          <WelcomeScreen
            firstName={firstName}
            savedPrompts={savedPrompts}
            onSuggestion={handleSuggestion}
            onManagePrompts={onManagePrompts}
          />
        </div>
      ) : (
        <MessageList
          chatId={chatId}
          messages={messages}
          hasMore={hasMore}
          loadingOlder={loadingOlder}
          onLoadOlder={loadOlder}
          streamingMessageId={streamingMessageId}
          awaitingReply={awaitingReply}
          toolEventsByMessage={toolEventsByMessage}
          onAskAssistant={handleAskAssistant}
        />
      )}

      <Composer
        value={draft}
        onChange={setDraft}
        onSubmit={handleSubmit}
        onSavePrompt={() => onSavePrompt(draft.trim())}
        busy={busy}
        maxLength={maxPromptLength}
        focusToken={focusToken}
        reference={reference}
        onReferenceClear={() => setReference(null)}
      />
    </>
  )
}

export default Conversation
