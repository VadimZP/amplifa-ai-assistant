import { useCallback, useEffect, useLayoutEffect, useRef, useState } from 'react'
import { ArrowDown, Loader2 } from 'lucide-react'
import { AskAssistantSelectionToolbar } from './AskAssistantSelectionToolbar'
import { MessageBubble, ThinkingIndicator } from './MessageBubble'
import { t } from '../../lib/i18n'
import { AssistantMessage, AssistantToolEvent } from './types'

interface MessageListProps {
  messages: AssistantMessage[]
  hasMore: boolean
  loadingOlder: boolean
  onLoadOlder: () => void
  /** Id of the message currently receiving tokens, if any. */
  streamingMessageId: number | null
  /** True between POSTing a prompt and the first token arriving. */
  awaitingReply: boolean
  /** Changes whenever the user switches chats, so scroll state resets. */
  chatId: number
  /** Tool invocations per assistant message id, shown as status chips. */
  toolEventsByMessage: Record<number, AssistantToolEvent[]>
  /** Called when the user selects text and clicks "Ask assistant". */
  onAskAssistant?: (text: string) => void
}

const NEAR_BOTTOM_PX = 120
const SCROLL_TO_BOTTOM_THRESHOLD_PX = 500

export function MessageList({
  messages,
  hasMore,
  loadingOlder,
  onLoadOlder,
  streamingMessageId,
  awaitingReply,
  chatId,
  toolEventsByMessage,
  onAskAssistant,
}: MessageListProps) {
  const scrollRef = useRef<HTMLDivElement>(null)
  const sentinelRef = useRef<HTMLDivElement>(null)
  // WHY: prepending older messages grows the container upwards, which would yank the viewport. We
  // snapshot scrollHeight before the DOM updates and re-apply the delta in a layout effect.
  const prependAnchorRef = useRef<number | null>(null)
  const oldestIdRef = useRef<number | null>(null)
  const stickToBottomRef = useRef(true)
  const [showScrollToBottom, setShowScrollToBottom] = useState(false)

  const oldestId = messages[0]?.id ?? null
  const lastMessage = messages[messages.length - 1]
  const lastId = lastMessage?.id ?? null
  const lastContentLength = lastMessage?.content.length ?? 0

  // Jump to the newest message when the chat opens.
  useLayoutEffect(() => {
    const element = scrollRef.current
    if (!element) return

    element.scrollTop = element.scrollHeight
    stickToBottomRef.current = true
    setShowScrollToBottom(false)
    prependAnchorRef.current = null
    oldestIdRef.current = oldestId
    // eslint-disable-next-line react-hooks/exhaustive-deps -- reset only when the chat changes
  }, [chatId])

  // Restore the visual position after an older page is prepended.
  useLayoutEffect(() => {
    const element = scrollRef.current
    if (!element) return

    const anchor = prependAnchorRef.current
    const grewAtTop = oldestId !== null && oldestIdRef.current !== null && oldestId < oldestIdRef.current
    oldestIdRef.current = oldestId

    if (anchor === null) return
    prependAnchorRef.current = null
    if (!grewAtTop) return

    element.scrollTop += element.scrollHeight - anchor
  }, [oldestId])

  // Follow the conversation while the user is at the bottom (new turns + streaming tokens), but
  // never fight a user who has deliberately scrolled up to read history. Tool chips appearing also
  // grow the container, so they participate in the deps.
  useEffect(() => {
    const element = scrollRef.current
    if (!element || !stickToBottomRef.current) return

    element.scrollTop = element.scrollHeight
    setShowScrollToBottom(false)
  }, [lastId, lastContentLength, awaitingReply, toolEventsByMessage])

  const updateScrollState = useCallback(() => {
    const element = scrollRef.current
    if (!element) return

    const distanceFromBottom = element.scrollHeight - element.scrollTop - element.clientHeight
    stickToBottomRef.current = distanceFromBottom < NEAR_BOTTOM_PX
    setShowScrollToBottom(distanceFromBottom > SCROLL_TO_BOTTOM_THRESHOLD_PX)
  }, [])

  const handleScroll = () => {
    updateScrollState()
  }

  const scrollToBottom = () => {
    const element = scrollRef.current
    if (!element) return

    element.scrollTop = element.scrollHeight
    stickToBottomRef.current = true
    setShowScrollToBottom(false)
  }

  // WHY IntersectionObserver over a scroll handler: it fires only when the top sentinel is actually
  // revealed, so paging up costs nothing while the user reads.
  useEffect(() => {
    const sentinel = sentinelRef.current
    const root = scrollRef.current
    if (!sentinel || !root || !hasMore || loadingOlder) return undefined

    const observer = new IntersectionObserver(
      entries => {
        if (!entries.some(entry => entry.isIntersecting)) return

        prependAnchorRef.current = root.scrollHeight
        onLoadOlder()
      },
      { root, rootMargin: '120px 0px 0px 0px' }
    )

    observer.observe(sentinel)

    return () => observer.disconnect()
  }, [hasMore, loadingOlder, onLoadOlder, messages.length])

  return (
    <div className="relative flex min-h-0 flex-1 flex-col">
      <div
        ref={scrollRef}
        onScroll={handleScroll}
        className="custom-scrollbar min-h-0 flex-1 overflow-y-auto px-4 py-6 sm:px-6"
      >
        {onAskAssistant && (
          <AskAssistantSelectionToolbar containerRef={scrollRef} onSelect={onAskAssistant} />
        )}
        <div className="mx-auto flex w-full max-w-3xl flex-col gap-6">
          {hasMore && <div ref={sentinelRef} aria-hidden className="h-px" />}

          {loadingOlder && (
            <div
              className="flex items-center justify-center gap-2 text-xs text-[var(--foreground-muted)]"
              role="status"
              aria-live="polite"
            >
              <Loader2 className="size-3.5 animate-spin" aria-hidden />
              {t('assistant.loading_older')}
            </div>
          )}

          {messages.map(message => (
            <MessageBubble
              key={message.id}
              message={message}
              streaming={message.id === streamingMessageId}
              toolEvents={toolEventsByMessage[message.id]}
            />
          ))}

          {/* The optimistic prompt is already rendered above; this is the "answer on its way" state
              shown before the assistant message row exists. */}
          {awaitingReply && streamingMessageId === null && (
            <div className="flex gap-3">
              <div className="size-7 shrink-0" aria-hidden />
              <ThinkingIndicator />
            </div>
          )}
        </div>
      </div>

      {showScrollToBottom && (
        <button
          type="button"
          onClick={scrollToBottom}
          aria-label={t('assistant.scroll_to_bottom')}
          className="absolute bottom-6 right-6 z-10 flex size-8 cursor-pointer items-center justify-center rounded-full border border-[var(--border)] bg-[var(--card)] text-[var(--foreground-muted)] shadow-[var(--shadow-md)] transition-colors hover:bg-[var(--card-hover)] hover:text-[var(--foreground)] sm:right-8"
        >
          <ArrowDown className="size-4" aria-hidden />
        </button>
      )}
    </div>
  )
}

export default MessageList
