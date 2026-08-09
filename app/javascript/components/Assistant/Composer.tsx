import { useEffect, useRef } from 'react'
import { ArrowUp, Bookmark, CornerDownRight, X } from 'lucide-react'
import { Textarea } from '../ui/Textarea'
import { Button } from '../ui/Button'
import { t } from '../../lib/i18n'

interface ComposerProps {
  value: string
  onChange: (value: string) => void
  onSubmit: () => void
  /** True while the assistant is answering — sending is blocked until it finishes. */
  busy: boolean
  maxLength: number
  /** Bumped by the parent to pull focus back into the field (e.g. after a suggestion click). */
  focusToken?: number
  /** Quoted excerpt from a message selection, shown above the textarea. */
  reference?: string | null
  onReferenceClear?: () => void
  onSavePrompt?: () => void
}

export function Composer({
  value,
  onChange,
  onSubmit,
  busy,
  maxLength,
  focusToken = 0,
  reference = null,
  onReferenceClear,
  onSavePrompt,
}: ComposerProps) {
  const textareaRef = useRef<HTMLTextAreaElement>(null)

  useEffect(() => {
    textareaRef.current?.focus()
  }, [focusToken])

  const trimmed = value.trim()
  const tooLong = value.length > maxLength
  const canSend = trimmed.length > 0 && !tooLong && !busy
  const canSave = trimmed.length > 0 && !tooLong && !busy && Boolean(onSavePrompt)

  const submit = () => {
    if (!canSend) return
    onSubmit()
  }

  // WHY keyDown and not keyPress: Enter must send while Shift+Enter inserts a newline, and IME
  // composition (`isComposing`) must not be interrupted or CJK input would submit mid-word.
  const handleKeyDown = (event: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (event.key !== 'Enter' || event.shiftKey || event.nativeEvent.isComposing) return

    event.preventDefault()
    submit()
  }

  const shellBorderClass = tooLong
    ? 'border-[var(--error)]'
    : 'border-[var(--input-border)]'

  return (
    <div className="border-t border-white/[0.06] bg-[var(--background)] px-4 py-3 sm:px-6">
      <div className="mx-auto flex w-full max-w-3xl flex-col gap-1.5">
        <div
          className={[
            'overflow-hidden rounded-xl border bg-[var(--input)] shadow-[inset_0_1px_0_rgba(255,255,255,0.03)]',
            shellBorderClass,
          ].join(' ')}
        >
          {reference && (
            <div className="flex items-start gap-2 border-b border-white/[0.06] px-3 py-2">
              <CornerDownRight className="mt-0.5 size-3.5 shrink-0 text-[var(--foreground-muted)]" aria-hidden />
              <p className="min-w-0 flex-1 text-sm leading-5 text-[var(--foreground-muted)] line-clamp-2">
                &ldquo;{reference}&rdquo;
              </p>
              {onReferenceClear && (
                <button
                  type="button"
                  onClick={onReferenceClear}
                  aria-label={t('assistant.composer.remove_reference')}
                  className="shrink-0 rounded-md p-1 text-[var(--foreground-muted)] transition-colors hover:bg-white/[0.06] hover:text-[var(--foreground)] focus:outline-none focus-visible:shadow-[0_0_0_2px_var(--ring-offset),0_0_0_4px_var(--ring)]"
                >
                  <X className="size-3.5" aria-hidden />
                </button>
              )}
            </div>
          )}

          <div className="flex items-end gap-1 p-1 pl-3">
            <Textarea
              ref={textareaRef}
              embedded
              autoResize
              maxRows={15}
              rows={1}
              value={value}
              onChange={event => onChange(event.target.value)}
              onKeyDown={handleKeyDown}
              placeholder={t('assistant.composer.placeholder')}
              aria-label={t('assistant.composer.placeholder')}
              containerClassName="min-w-0 flex-1 gap-0"
              className="min-h-10 pr-1"
            />
            {onSavePrompt && (
              <Button
                type="button"
                variant="ghost"
                aria-label={t('assistant.saved_prompts.save')}
                title={t('assistant.saved_prompts.save')}
                icon={<Bookmark className="size-4" aria-hidden />}
                disabled={!canSave}
                onClick={onSavePrompt}
                className="size-10! shrink-0 cursor-pointer rounded-full p-0! min-w-10"
              />
            )}
            <Button
              type="button"
              aria-label={t('assistant.composer.send')}
              title={t('assistant.composer.send')}
              icon={<ArrowUp className="size-4" aria-hidden />}
              disabled={!canSend}
              loading={busy}
              onClick={submit}
              className="size-10! shrink-0 cursor-pointer rounded-full p-0! min-w-10"
            />
          </div>
        </div>

        {tooLong && (
          <p className="text-xs text-[var(--error)]" role="alert">
            {t('assistant.errors.prompt_too_long', { count: maxLength })}
          </p>
        )}

        <p className="hidden text-xs text-[var(--foreground-subtle)] sm:block">
          {t('assistant.composer.hint')}
        </p>
      </div>
    </div>
  )
}

export default Composer
