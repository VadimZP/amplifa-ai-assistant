import { BarChart3, Bookmark, FileText, Inbox, Sparkles, ThumbsUp } from 'lucide-react'
import { AssistantSavedPrompt } from './types'
import { t } from '../../lib/i18n'

interface WelcomeScreenProps {
  firstName: string
  savedPrompts: AssistantSavedPrompt[]
  onSuggestion: (prompt: string) => void
  onManagePrompts: () => void
}

// WHY these four: each one exercises a real inbox tool (conversation_list, conversation_stats,
// conversation_read), so the first answer is grounded in live workspace data rather than a
// generic chatbot reply.
const DEFAULT_SUGGESTIONS = [
  { id: 'inbox', key: 'assistant.welcome.suggestions.inbox', icon: Inbox },
  { id: 'interested', key: 'assistant.welcome.suggestions.interested', icon: ThumbsUp },
  { id: 'stats', key: 'assistant.welcome.suggestions.stats', icon: BarChart3 },
  { id: 'summarize', key: 'assistant.welcome.suggestions.summarize', icon: FileText },
] as const

function suggestionButtonClassName() {
  return 'flex items-center gap-3 rounded-xl border border-[var(--border)] bg-[var(--card)] px-3.5 py-3 text-left text-sm text-[var(--foreground-muted)] transition-colors hover:border-white/[0.14] hover:bg-white/[0.04] hover:text-[var(--foreground)] focus:outline-none focus-visible:shadow-[0_0_0_2px_var(--ring-offset),0_0_0_4px_var(--ring)]'
}

export function WelcomeScreen({
  firstName,
  savedPrompts,
  onSuggestion,
  onManagePrompts,
}: WelcomeScreenProps) {
  const welcomePrompts = [...savedPrompts]
    .filter(prompt => prompt.welcome_pinned)
    .sort((left, right) => left.position - right.position || left.id - right.id)

  return (
    <div className="mx-auto flex w-full max-w-3xl flex-col items-center px-4 py-10 text-center sm:py-16">
      <div
        className="flex size-12 items-center justify-center rounded-2xl border border-white/[0.08] bg-white/[0.04]"
        aria-hidden
      >
        <Sparkles className="size-5 text-[var(--accent)]" />
      </div>

      <p className="mt-5 text-sm text-[var(--foreground-muted)]">
        {t('assistant.welcome.greeting', { name: firstName })}
      </p>
      <h1 className="mt-1 text-2xl font-semibold text-[var(--foreground)] sm:text-3xl">
        {t('assistant.welcome.title')}
      </h1>
      <p className="mt-3 max-w-xl text-sm leading-6 text-[var(--foreground-muted)]">
        {t('assistant.welcome.description')}
      </p>

      {welcomePrompts.length > 0 && (
        <>
          <div className="mt-8 flex w-full items-center justify-between gap-3">
            <p className="text-xs font-medium tracking-wide text-[var(--foreground-subtle)] uppercase">
              {t('assistant.saved_prompts.your_prompts_label')}
            </p>
            <button
              type="button"
              onClick={onManagePrompts}
              className="text-xs text-[var(--foreground-muted)] transition-colors hover:text-[var(--foreground)]"
            >
              {t('assistant.saved_prompts.manage')}
            </button>
          </div>
          <div className="mt-3 grid w-full gap-2 sm:grid-cols-2">
            {welcomePrompts.map(savedPrompt => (
              <button
                key={savedPrompt.id}
                type="button"
                onClick={() => onSuggestion(savedPrompt.prompt)}
                className={suggestionButtonClassName()}
              >
                <Bookmark className="size-4 shrink-0 text-[var(--accent)]" aria-hidden />
                <span className="min-w-0">
                  <span className="block truncate font-medium text-[var(--foreground)]">
                    {savedPrompt.title}
                  </span>
                  <span className="mt-0.5 block line-clamp-2 text-xs leading-5 text-[var(--foreground-muted)]">
                    {savedPrompt.prompt}
                  </span>
                </span>
              </button>
            ))}
          </div>
        </>
      )}

      <div className="mt-8 flex w-full items-center justify-between gap-3">
        <p className="text-xs font-medium tracking-wide text-[var(--foreground-subtle)] uppercase">
          {t('assistant.welcome.suggestions_label')}
        </p>
        {welcomePrompts.length === 0 && (
          <button
            type="button"
            onClick={onManagePrompts}
            className="text-xs text-[var(--foreground-muted)] transition-colors hover:text-[var(--foreground)]"
          >
            {t('assistant.saved_prompts.manage')}
          </button>
        )}
      </div>
      <div className="mt-3 grid w-full gap-2 sm:grid-cols-2">
        {DEFAULT_SUGGESTIONS.map(({ id, key, icon: Icon }) => {
          const prompt = String(t(key))

          return (
            <button
              key={id}
              type="button"
              onClick={() => onSuggestion(prompt)}
              className={suggestionButtonClassName()}
            >
              <Icon className="size-4 shrink-0 text-[var(--foreground-subtle)]" aria-hidden />
              <span className="min-w-0">{prompt}</span>
            </button>
          )
        })}
      </div>
    </div>
  )
}

export default WelcomeScreen
