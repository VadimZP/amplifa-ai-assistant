import { useCallback, useEffect, useMemo, useState } from 'react'
import { Bookmark, Pencil, Trash2 } from 'lucide-react'
import { AssistantSavedPrompt } from './types'
import { Button } from '../ui/Button'
import { Input } from '../ui/Input'
import { SlideOver } from '../ui/SlideOver'
import { Textarea } from '../ui/Textarea'
import { toast } from '../ui/Toaster'
import {
  createAssistantSavedPrompt,
  defaultSavedPromptTitle,
  deleteAssistantSavedPrompt,
  updateAssistantSavedPrompt,
} from '../../lib/assistantSavedPrompts'
import { t } from '../../lib/i18n'

interface SavedPromptsSlideOverProps {
  open: boolean
  onClose: () => void
  prompts: AssistantSavedPrompt[]
  maxPromptLength: number
  draftPrompt?: string
  editingPrompt?: AssistantSavedPrompt | null
  onPromptsChange: (prompts: AssistantSavedPrompt[]) => void
}

type FormMode = 'list' | 'form'

export function SavedPromptsSlideOver({
  open,
  onClose,
  prompts,
  maxPromptLength,
  draftPrompt = '',
  editingPrompt = null,
  onPromptsChange,
}: SavedPromptsSlideOverProps) {
  const [mode, setMode] = useState<FormMode>('list')
  const [title, setTitle] = useState('')
  const [prompt, setPrompt] = useState('')
  const [welcomePinned, setWelcomePinned] = useState(false)
  const [activeId, setActiveId] = useState<number | null>(null)
  const [saving, setSaving] = useState(false)
  const [deletingId, setDeletingId] = useState<number | null>(null)
  const [pinningId, setPinningId] = useState<number | null>(null)

  const sortedPrompts = useMemo(
    () =>
      [...prompts].sort((left, right) => {
        if (left.welcome_pinned !== right.welcome_pinned) return left.welcome_pinned ? -1 : 1
        if (left.welcome_pinned) return left.position - right.position || left.id - right.id
        return right.updated_at.localeCompare(left.updated_at) || right.id - left.id
      }),
    [prompts]
  )

  const resetForm = useCallback(() => {
    setMode('list')
    setActiveId(null)
    setTitle('')
    setPrompt('')
    setWelcomePinned(false)
  }, [])

  const openCreateForm = useCallback((seedPrompt = '') => {
    const trimmed = seedPrompt.trim()
    setMode('form')
    setActiveId(null)
    setPrompt(trimmed)
    setTitle(trimmed ? defaultSavedPromptTitle(trimmed) : '')
    setWelcomePinned(false)
  }, [])

  const openEditForm = useCallback((savedPrompt: AssistantSavedPrompt) => {
    setMode('form')
    setActiveId(savedPrompt.id)
    setTitle(savedPrompt.title)
    setPrompt(savedPrompt.prompt)
    setWelcomePinned(savedPrompt.welcome_pinned)
  }, [])

  useEffect(() => {
    if (!open) {
      resetForm()
      return
    }

    if (editingPrompt) {
      openEditForm(editingPrompt)
      return
    }

    if (draftPrompt.trim()) {
      openCreateForm(draftPrompt)
    }
  }, [draftPrompt, editingPrompt, open, openCreateForm, openEditForm, resetForm])

  const handleSave = async () => {
    const trimmedTitle = title.trim()
    const trimmedPrompt = prompt.trim()

    if (!trimmedTitle || !trimmedPrompt) return

    setSaving(true)
    try {
      if (activeId) {
        const updated = await updateAssistantSavedPrompt(activeId, {
          title: trimmedTitle,
          prompt: trimmedPrompt,
          welcome_pinned: welcomePinned,
        })
        onPromptsChange(prompts.map(item => (item.id === updated.id ? updated : item)))
        toast.success(t('assistant.saved_prompts.updated'))
      } else {
        const created = await createAssistantSavedPrompt({
          title: trimmedTitle,
          prompt: trimmedPrompt,
          welcome_pinned: welcomePinned,
        })
        onPromptsChange([created, ...prompts])
        toast.success(t('assistant.saved_prompts.saved'))
      }
      resetForm()
    } catch (error) {
      toast.error(error instanceof Error ? error.message : t('assistant.errors.save_saved_prompt'))
    } finally {
      setSaving(false)
    }
  }

  const handleTogglePin = async (savedPrompt: AssistantSavedPrompt) => {
    setPinningId(savedPrompt.id)
    try {
      const updated = await updateAssistantSavedPrompt(savedPrompt.id, {
        welcome_pinned: !savedPrompt.welcome_pinned,
      })
      onPromptsChange(prompts.map(item => (item.id === updated.id ? updated : item)))
    } catch (error) {
      toast.error(error instanceof Error ? error.message : t('assistant.errors.save_saved_prompt'))
    } finally {
      setPinningId(null)
    }
  }

  const handleDelete = async (savedPrompt: AssistantSavedPrompt) => {
    if (!window.confirm(t('assistant.saved_prompts.delete_confirm'))) return

    setDeletingId(savedPrompt.id)
    try {
      await deleteAssistantSavedPrompt(savedPrompt.id)
      onPromptsChange(prompts.filter(item => item.id !== savedPrompt.id))
      toast.success(t('assistant.saved_prompts.deleted'))
      if (activeId === savedPrompt.id) resetForm()
    } catch (error) {
      toast.error(error instanceof Error ? error.message : t('assistant.errors.delete_saved_prompt'))
    } finally {
      setDeletingId(null)
    }
  }

  const renderPromptRow = (savedPrompt: AssistantSavedPrompt) => (
    <div
      key={savedPrompt.id}
      className="rounded-xl border border-[var(--border)] bg-[var(--card)] px-2.5 py-3"
    >
      <div className="flex items-start gap-3">
        <div className="min-w-0 flex-1 text-left">
          <p className="truncate text-sm font-medium text-[var(--foreground)]">{savedPrompt.title}</p>
          <p className="mt-1 line-clamp-2 text-xs leading-5 text-[var(--foreground-muted)]">
            {savedPrompt.prompt}
          </p>
        </div>
        <div className="flex shrink-0 items-center gap-1">
          <button
            type="button"
            aria-label={
              savedPrompt.welcome_pinned
                ? t('assistant.saved_prompts.unpin')
                : t('assistant.saved_prompts.pin')
            }
            title={
              savedPrompt.welcome_pinned
                ? t('assistant.saved_prompts.unpin')
                : t('assistant.saved_prompts.pin')
            }
            disabled={pinningId === savedPrompt.id}
            onClick={() => handleTogglePin(savedPrompt)}
            className="rounded-lg p-1.5 text-[var(--foreground-subtle)] transition-colors hover:bg-white/[0.06] hover:text-[var(--accent)] disabled:opacity-50 data-[pinned=true]:text-[var(--accent)]"
            data-pinned={savedPrompt.welcome_pinned ? 'true' : 'false'}
          >
            <Bookmark className="size-4" aria-hidden />
          </button>
          <button
            type="button"
            aria-label={t('assistant.saved_prompts.edit_title')}
            onClick={() => openEditForm(savedPrompt)}
            className="rounded-lg p-1.5 text-[var(--foreground-subtle)] transition-colors hover:bg-white/[0.06] hover:text-[var(--foreground)]"
          >
            <Pencil className="size-4" aria-hidden />
          </button>
          <button
            type="button"
            aria-label={t('assistant.saved_prompts.delete')}
            disabled={deletingId === savedPrompt.id}
            onClick={() => handleDelete(savedPrompt)}
            className="rounded-lg p-1.5 text-[var(--foreground-subtle)] transition-colors hover:bg-white/[0.06] hover:text-[var(--error)] disabled:opacity-50"
          >
            <Trash2 className="size-4" aria-hidden />
          </button>
        </div>
      </div>
    </div>
  )

  return (
    <SlideOver
      open={open}
      onClose={onClose}
      titleClassName="text-lg font-semibold tracking-[-0.02em] text-white"
      headerClassName="px-5 py-4"
      title={
        mode === 'form'
          ? activeId
            ? t('assistant.saved_prompts.edit_title')
            : t('assistant.saved_prompts.save_title')
          : t('assistant.saved_prompts.manage')
      }
      footer={
        mode === 'form' ? (
          <div className="flex justify-end gap-2">
            <Button type="button" variant="secondary" onClick={resetForm}>
              {t('common.cancel')}
            </Button>
            <Button
              type="button"
              loading={saving}
              disabled={!title.trim() || !prompt.trim() || prompt.length > maxPromptLength}
              onClick={handleSave}
            >
              {t('common.save')}
            </Button>
          </div>
        ) : undefined
      }
    >
      {mode === 'form' ? (
        <div className="space-y-4 px-5 py-5">
          <Input
            label={t('assistant.saved_prompts.title_label')}
            value={title}
            onChange={event => setTitle(event.target.value)}
            placeholder={t('assistant.saved_prompts.title_placeholder')}
          />
          <Textarea
            label={t('assistant.saved_prompts.prompt_label')}
            value={prompt}
            onChange={event => setPrompt(event.target.value)}
            rows={6}
            error={
              prompt.length > maxPromptLength
                ? t('assistant.errors.prompt_too_long', { count: maxPromptLength })
                : undefined
            }
          />
          <label className="flex items-start gap-3 rounded-xl border border-[var(--border)] bg-[var(--card)] p-3 text-left">
            <input
              type="checkbox"
              checked={welcomePinned}
              onChange={event => setWelcomePinned(event.target.checked)}
              className="mt-0.5 size-4 rounded border-[var(--border)]"
            />
            <span>
              <span className="block text-sm font-medium text-[var(--foreground)]">
                {t('assistant.saved_prompts.welcome_pinned_label')}
              </span>
              <span className="mt-1 block text-xs leading-5 text-[var(--foreground-muted)]">
                {t('assistant.saved_prompts.welcome_pinned_help')}
              </span>
            </span>
          </label>
        </div>
      ) : (
        <div className="space-y-5 px-5 py-5">
          <Button type="button" onClick={() => openCreateForm(draftPrompt)}>
            {t('assistant.saved_prompts.save')}
          </Button>

          {prompts.length === 0 ? (
            <div className="rounded-xl border border-dashed border-[var(--border)] px-4 py-8 text-center">
              <p className="text-sm text-[var(--foreground-muted)]">{t('assistant.saved_prompts.empty')}</p>
              <p className="mt-2 text-xs text-[var(--foreground-subtle)]">
                {t('assistant.saved_prompts.empty_hint')}
              </p>
            </div>
          ) : (
            <div className="space-y-3">
              {sortedPrompts.map(renderPromptRow)}
            </div>
          )}
        </div>
      )}
    </SlideOver>
  )
}

export default SavedPromptsSlideOver
