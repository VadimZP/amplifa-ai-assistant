import { useCallback, useEffect, useRef, useState } from 'react'
import { useActionCableChannel } from '../../lib/useActionCableChannel'
import { toast } from '../ui/Toaster'
import { t } from '../../lib/i18n'
import { AssistantMessage, AssistantStreamFrame, AssistantToolEvent } from './types'

interface UseAssistantChatOptions {
  chatId: number
  initialMessages: AssistantMessage[]
  initialHasMore: boolean
  /** True when the server is already generating a reply (e.g. after a first-prompt redirect). */
  initialStreaming: boolean
  /** Called when the server generates a title, so the sidebar can update without a reload. */
  onTitle: (chatId: number, title: string) => void
}

const csrfToken = () =>
  document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content || ''

// WHY a negative id: an optimistic prompt has no database id yet, but MessageList keys by id and
// pagination compares ids. Negative ids can never collide with real rows and always sort oldest-last.
let optimisticSeq = 0
const nextOptimisticId = () => {
  optimisticSeq += 1
  return -optimisticSeq
}

/** Maps a backend error reason onto a user-facing string, defaulting to the generic message. */
const errorMessage = (reason: string) => {
  const known = ['llm_unavailable', 'empty_completion', 'unexpected']
  const key = known.includes(reason) ? reason : 'unexpected'

  return String(t(`assistant.errors.${key}`))
}

/**
 * Owns the message list for the selected chat: optimistic sends, cable streaming, and backwards
 * pagination. Kept out of the page component so the JSX stays about layout.
 */
export function useAssistantChat({
  chatId,
  initialMessages,
  initialHasMore,
  initialStreaming,
  onTitle,
}: UseAssistantChatOptions) {
  const [messages, setMessages] = useState<AssistantMessage[]>(initialMessages)
  const [hasMore, setHasMore] = useState(initialHasMore)
  const [loadingOlder, setLoadingOlder] = useState(false)
  const [sending, setSending] = useState(false)
  const [awaitingReply, setAwaitingReply] = useState(initialStreaming)
  const [streamingMessageId, setStreamingMessageId] = useState<number | null>(null)
  // Tool chips per assistant message. In-memory only: activity from before a reload is gone, which
  // is fine — the finished reply says what was done.
  const [toolEventsByMessage, setToolEventsByMessage] = useState<Record<number, AssistantToolEvent[]>>({})

  // WHY refs and not state for these two guards: the paginator and the sender are recreated on every
  // render, and a state update lands too late to stop a second in-flight request.
  const loadingOlderRef = useRef(false)
  const sendingRef = useRef(false)

  const upsertAssistantMessage = useCallback((id: number, content: string) => {
    setMessages(current => {
      const index = current.findIndex(message => message.id === id)

      if (index === -1) {
        return [
          ...current,
          { id, role: 'assistant', content, created_at: new Date().toISOString() },
        ]
      }

      const next = [...current]
      next[index] = { ...next[index], content }

      return next
    })
  }, [])

  // WHY not upsertAssistantMessage: a tool_start frame can arrive after tokens have already
  // streamed, and upserting with '' would wipe that content. This only inserts the row if missing.
  const ensureAssistantMessage = useCallback((id: number) => {
    setMessages(current => {
      if (current.some(message => message.id === id)) return current

      return [...current, { id, role: 'assistant', content: '', created_at: new Date().toISOString() }]
    })
  }, [])

  const recordToolEvent = useCallback((messageId: number, event: AssistantToolEvent) => {
    setToolEventsByMessage(current => {
      const events = current[messageId] ?? []
      const index = events.findIndex(existing => existing.callId === event.callId)
      const next = index === -1 ? [...events, event] : events.map((e, i) => (i === index ? event : e))

      return { ...current, [messageId]: next }
    })
  }, [])

  // A turn that dies (error frame) must not leave chips spinning forever.
  const failRunningToolEvents = useCallback(() => {
    setToolEventsByMessage(current => {
      const next: Record<number, AssistantToolEvent[]> = {}
      for (const [messageId, events] of Object.entries(current)) {
        next[Number(messageId)] = events.map(event =>
          event.status === 'running' ? { ...event, status: 'error' } : event
        )
      }

      return next
    })
  }, [])

  // WHY: `messages` is read inside the cable `connected` handler, which is registered once. A ref keeps
  // that handler reading the current list instead of the one captured at subscribe time.
  const messagesRef = useRef(messages)
  messagesRef.current = messages

  /**
   * Reconciles with the server after (re)connecting.
   *
   * WHY this exists: ActionCable has no replay. On the first prompt the server enqueues the reply and
   * redirects, and with the :async adapter the job can finish in milliseconds — before React has even
   * mounted and subscribed. Those frames are broadcast to nobody, so without this the user stares at a
   * spinner for a reply that already completed and only sees it after a manual reload.
   */
  const resync = useCallback(async () => {
    // The cursor is inclusive on the server, so sending the newest persisted id also re-fetches that row
    // with its final content — which is how a stalled stream repairs itself.
    const lastPersistedId = messagesRef.current.reduce(
      (max, message) => (message.id > max ? message.id : max),
      0
    )

    try {
      const response = await fetch(
        `/assistant/chats/${chatId}/messages?since_id=${lastPersistedId}`,
        { headers: { Accept: 'application/json' } }
      )
      if (!response.ok) return

      const payload = (await response.json()) as {
        messages?: AssistantMessage[]
        streaming?: boolean
        title?: string | null
      }

      if (payload.title) onTitle(chatId, payload.title)

      // WHY it merges rather than appends: the newest row the client holds may be a half-streamed
      // assistant message, and the server returns it (inclusive cursor) with its final content. Appending
      // would duplicate it; only updating in place both fills the gap and repairs a stalled stream.
      if (payload.messages?.length) {
        setMessages(current => {
          const byId = new Map(current.map(message => [message.id, message]))
          payload.messages!.forEach(message => byId.set(message.id, message))

          // Persisted rows sort by id; optimistic rows (negative ids) stay pinned at the end, where the
          // user just typed them, until the POST swaps them for the real row.
          const merged = [...byId.values()]

          return [
            ...merged.filter(message => message.id > 0).sort((a, b) => a.id - b.id),
            ...merged.filter(message => message.id < 0),
          ]
        })
      }

      // The server is the authority on whether a reply is still coming, so this also clears a spinner
      // left behind by a turn that finished while we were disconnected.
      if (!payload.streaming) {
        setAwaitingReply(false)
        setStreamingMessageId(null)
      }
    } catch {
      // A failed resync is not worth a toast: the next connect retries, and a reload always recovers.
    }
  }, [chatId, onTitle])

  useActionCableChannel<AssistantStreamFrame>(
    { channel: 'AssistantChatChannel', chat_id: chatId },
    {
      connected: () => {
        void resync()
      },
      received: frame => {
        switch (frame.type) {
          case 'start':
            setStreamingMessageId(frame.message_id)
            upsertAssistantMessage(frame.message_id, '')
            break
          case 'delta':
            setAwaitingReply(true)
            setStreamingMessageId(frame.message_id)
            upsertAssistantMessage(frame.message_id, frame.content)
            break
          case 'done':
            upsertAssistantMessage(frame.message_id, frame.content)
            setStreamingMessageId(null)
            setAwaitingReply(false)
            break
          case 'error':
            setStreamingMessageId(null)
            setAwaitingReply(false)
            failRunningToolEvents()
            toast.error(errorMessage(frame.error))
            break
          case 'title':
            onTitle(chatId, frame.title)
            break
          case 'tool_start':
            setAwaitingReply(true)
            setStreamingMessageId(frame.message_id)
            ensureAssistantMessage(frame.message_id)
            recordToolEvent(frame.message_id, {
              callId: frame.call_id,
              tool: frame.tool,
              status: 'running',
            })
            break
          case 'tool_end':
            recordToolEvent(frame.message_id, {
              callId: frame.call_id,
              tool: frame.tool,
              status: frame.status === 'ok' ? 'ok' : 'error',
            })
            break
        }
      },
      // WHY surface a rejected subscription: without the cable the reply is still generated and
      // persisted, but the user would stare at a spinner that never resolves.
      rejected: () => {
        setAwaitingReply(false)
        setStreamingMessageId(null)
        toast.error(String(t('assistant.errors.connection_lost')))
      },
    }
  )

  // WHY a bounded poll and not just the cable: `resync` closes the mount-time gap, but a reply can also
  // land in the window between the connect handshake and the resync response. Rather than trusting the
  // cable to be perfectly timed, re-check while a reply is outstanding. It stops as soon as the server
  // reports the lock released, so a normal streamed turn costs at most one extra request.
  useEffect(() => {
    if (!awaitingReply) return undefined

    const timer = window.setInterval(() => void resync(), 2500)

    return () => window.clearInterval(timer)
  }, [awaitingReply, resync])

  const send = useCallback(
    async (prompt: string) => {
      const trimmed = prompt.trim()
      if (!trimmed || sendingRef.current) return false

      sendingRef.current = true
      setSending(true)

      // Optimistic: the prompt and a "thinking" row appear before the request resolves.
      const optimisticId = nextOptimisticId()
      setMessages(current => [
        ...current,
        { id: optimisticId, role: 'user', content: trimmed, created_at: new Date().toISOString() },
      ])
      setAwaitingReply(true)

      try {
        const response = await fetch(`/assistant/chats/${chatId}/messages`, {
          method: 'POST',
          headers: {
            Accept: 'application/json',
            'Content-Type': 'application/json',
            'X-CSRF-Token': csrfToken(),
          },
          body: JSON.stringify({ prompt: trimmed }),
        })

        const payload = (await response.json()) as { message?: AssistantMessage; error?: string }

        if (!response.ok || !payload.message) {
          throw new Error(payload.error || String(t('assistant.errors.send_failed')))
        }

        // Swap the placeholder for the persisted row so later frames and pagination line up.
        const persisted = payload.message
        setMessages(current =>
          current.map(message => (message.id === optimisticId ? persisted : message))
        )

        return true
      } catch (error) {
        setMessages(current => current.filter(message => message.id !== optimisticId))
        setAwaitingReply(false)
        toast.error(
          error instanceof Error ? error.message : String(t('assistant.errors.send_failed'))
        )

        return false
      } finally {
        sendingRef.current = false
        setSending(false)
      }
    },
    [chatId]
  )

  const loadOlder = useCallback(async () => {
    const oldest = messages.find(message => message.id > 0)
    if (!hasMore || loadingOlderRef.current || !oldest) return

    loadingOlderRef.current = true
    setLoadingOlder(true)

    try {
      const response = await fetch(
        `/assistant/chats/${chatId}/messages?before_id=${oldest.id}`,
        { headers: { Accept: 'application/json' } }
      )

      const payload = (await response.json()) as {
        messages?: AssistantMessage[]
        has_more?: boolean
        error?: string
      }

      if (!response.ok || !payload.messages) {
        throw new Error(payload.error || String(t('assistant.errors.load_older_failed')))
      }

      const older = payload.messages
      setMessages(current => {
        const known = new Set(current.map(message => message.id))

        return [...older.filter(message => !known.has(message.id)), ...current]
      })
      setHasMore(Boolean(payload.has_more))
    } catch (error) {
      toast.error(
        error instanceof Error ? error.message : String(t('assistant.errors.load_older_failed'))
      )
    } finally {
      loadingOlderRef.current = false
      setLoadingOlder(false)
    }
  }, [chatId, hasMore, messages])

  return {
    messages,
    hasMore,
    loadingOlder,
    loadOlder,
    send,
    sending,
    awaitingReply,
    streamingMessageId,
    toolEventsByMessage,
  }
}
