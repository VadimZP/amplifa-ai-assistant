import { AlertCircle, Check, Loader2, Sparkles } from 'lucide-react'
import { renderBuyingSignalsMarkdown } from '../../lib/renderBuyingSignalsMarkdown'
import { t } from '../../lib/i18n'
import { AssistantMessage, AssistantToolEvent } from './types'

interface MessageBubbleProps {
  message: AssistantMessage
  /** True while tokens are still arriving for this message. */
  streaming?: boolean
  /** Tool invocations made during this turn, rendered as status chips above the reply. */
  toolEvents?: AssistantToolEvent[]
}

/**
 * One turn in the conversation. User turns are right-aligned bubbles (verbatim text, so no markdown
 * parsing); assistant turns are full-width prose.
 *
 * WHY renderBuyingSignalsMarkdown: it is the repo's existing renderer for the markdown subset the
 * models actually emit (paragraphs, bullets, ordered lists, bold). Reused rather than adding a
 * markdown dependency.
 *
 * WHY allowLinks: false: assistant replies must never contain anything clickable or fetchable —
 * links and bare URLs render as plain text, and no media is ever loaded. The system prompt also
 * forbids them, but the renderer is the guarantee (a prompt-injected model can't be trusted).
 */
export function MessageBubble({ message, streaming = false, toolEvents = [] }: MessageBubbleProps) {
  if (message.role === 'user') {
    return (
      <div className="flex justify-end">
        <div className="max-w-[85%] rounded-2xl rounded-br-md bg-white/[0.08] px-4 py-2.5 sm:max-w-[75%]">
          <p
            data-assistant-message-content
            className="text-sm leading-6 whitespace-pre-wrap break-words text-[var(--foreground)]"
          >
            {message.content}
          </p>
        </div>
      </div>
    )
  }

  const hasContent = message.content.trim().length > 0
  const toolRunning = toolEvents.some(event => event.status === 'running')

  return (
    <div className="flex gap-3">
      <div
        className="mt-0.5 flex size-7 shrink-0 items-center justify-center rounded-full border border-white/[0.08] bg-white/[0.04]"
        aria-hidden
      >
        <Sparkles className="size-3.5 text-[var(--accent)]" />
      </div>
      <div className="min-w-0 flex-1" data-assistant-message-content>
        <span className="sr-only">{t('assistant.assistant_label')}</span>
        {toolEvents.length > 0 && (
          <div className="mb-2 flex flex-wrap gap-1.5">
            {toolEvents.map(event => (
              <ToolActivityChip key={event.callId} event={event} />
            ))}
          </div>
        )}
        {hasContent ? (
          renderBuyingSignalsMarkdown(message.content, { allowLinks: false })
        ) : (
          // While a tool chip is already saying "Searching your inbox...", a second "Thinking..."
          // row underneath would just be noise.
          !toolRunning && <ThinkingIndicator />
        )}
        {/* WHY a caret while streaming: it tells the user tokens are still arriving, so a pause in
            the stream doesn't read as a finished (but truncated) answer. */}
        {streaming && hasContent && (
          <span
            className="ml-0.5 inline-block h-4 w-[2px] animate-pulse bg-[var(--accent)] align-middle"
            aria-hidden
          />
        )}
      </div>
    </div>
  )
}

function ToolActivityChip({ event }: { event: AssistantToolEvent }) {
  const stateKey = event.status === 'running' ? 'running' : event.status === 'ok' ? 'done' : 'failed'
  // WHY defaultValue: new backend tools only need locale keys — no frontend whitelist to keep in
  // sync. Unknown tool names still show the generic chip instead of a missing-translation string.
  const label = String(
    t(`assistant.tools.${event.tool}.${stateKey}`, {
      defaultValue: t(`assistant.tools.generic.${stateKey}`),
    }),
  )

  return (
    <span
      className="inline-flex items-center gap-1.5 rounded-full border border-[var(--border)] bg-white/[0.04] px-2.5 py-1 text-xs text-[var(--foreground-muted)]"
      role="status"
      aria-live="polite"
    >
      {event.status === 'running' && <Loader2 className="size-3 animate-spin" aria-hidden />}
      {event.status === 'ok' && <Check className="size-3 text-[var(--success)]" aria-hidden />}
      {event.status === 'error' && <AlertCircle className="size-3 text-[var(--error)]" aria-hidden />}
      {label}
    </span>
  )
}

export function ThinkingIndicator() {
  return (
    <div
      className="flex items-center gap-2 text-sm text-[var(--foreground-muted)]"
      role="status"
      aria-live="polite"
    >
      <Loader2 className="size-4 animate-spin" aria-hidden />
      {t('assistant.thinking')}
    </div>
  )
}

export default MessageBubble
