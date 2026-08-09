import { useEffect, useMemo, useState } from 'react'
import { router } from '@inertiajs/react'
import { Button } from '../ui/Button'
import { X, Sparkles } from 'lucide-react'
import { t } from '../../lib/i18n'
import {
  playbookAiEditScopeOptions,
  type PlaybookAiEditScope
} from '../../lib/playbookAiEditScopes'

interface PlaybookOption {
  id: number
  product_name: string
}

interface PlaybookAiEditModalProps {
  organizationId: number
  playbooks?: PlaybookOption[]
  playbookId?: number
  playbookName?: string
  isOpen: boolean
  onClose: () => void
  onSuccess?: () => void
}

const inputClasses = [
  'w-full',
  'px-3',
  'py-2',
  'h-9',
  'bg-[var(--input)]',
  'border',
  'border-[var(--input-border)]',
  'rounded-lg',
  'text-sm',
  'text-[var(--foreground)]',
  'transition-all',
  'duration-150',
  'focus:outline-none',
  'focus:border-[var(--ring)]',
  'focus:shadow-[0_0_0_2px_var(--ring-offset),0_0_0_4px_var(--ring)]'
].join(' ')

export default function PlaybookAiEditModal({
  organizationId,
  playbooks,
  playbookId,
  playbookName,
  isOpen,
  onClose,
  onSuccess
}: PlaybookAiEditModalProps) {
  const [instruction, setInstruction] = useState('')
  const [editScope, setEditScope] = useState<PlaybookAiEditScope>('entire_playbook')
  const [selectedPlaybookId, setSelectedPlaybookId] = useState<number | null>(playbookId ?? null)
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const playbookOptions = useMemo(() => playbooks || [], [playbooks])
  const isFixedPlaybook = typeof playbookId === 'number'

  useEffect(() => {
    if (isFixedPlaybook) {
      setSelectedPlaybookId(playbookId ?? null)
      return
    }

    if (isOpen && playbookOptions.length > 0 && selectedPlaybookId === null) {
      setSelectedPlaybookId(playbookOptions[0].id)
    }
  }, [isFixedPlaybook, isOpen, playbookId, playbookOptions, selectedPlaybookId])

  const handleClose = () => {
    if (submitting) return
    setInstruction('')
    setEditScope('entire_playbook')
    setError(null)
    setSelectedPlaybookId(playbookId ?? playbookOptions[0]?.id ?? null)
    onClose()
  }

  const handleSubmit = () => {
    if (!selectedPlaybookId) {
      setError(t('admin.playbooks.ai_edit.missing_instruction'))
      return
    }

    if (!instruction.trim()) {
      setError(t('admin.playbooks.ai_edit.missing_instruction'))
      return
    }

    setSubmitting(true)
    setError(null)

    router.post(
      `/admin/organizations/${organizationId}/playbooks/${selectedPlaybookId}/ai_edit`,
      { instruction, edit_scope: editScope },
      {
        preserveScroll: true,
        onFinish: () => {
          setSubmitting(false)
          handleClose()
        },
        onSuccess: () => {
          onSuccess?.()
        },
        onError: () => {
          setSubmitting(false)
          setError(t('admin.playbooks.ai_edit.failed'))
        }
      }
    )
  }

  if (!isOpen) return null

  return (
    <div className="fixed inset-0 z-50 overflow-y-auto">
      <div className="flex min-h-screen items-center justify-center p-4">
        <button
          type="button"
          aria-label={t('admin.common.cancel')}
          className="fixed inset-0 bg-black/60 backdrop-blur-sm transition-opacity"
          onClick={handleClose}
        />

        <div className="relative bg-[var(--card)] rounded-xl shadow-2xl max-w-2xl w-full p-6 border border-[var(--border)]">
          <div className="flex items-start justify-between mb-4">
            <div>
              <h3 className="text-xl font-semibold text-[var(--foreground)] flex items-center gap-2">
                <Sparkles className="h-5 w-5 text-[var(--accent)]" />
                {t('admin.playbooks.ai_edit.title')}
              </h3>
              <p className="mt-1 text-sm text-[var(--foreground-muted)]">
                {t('admin.playbooks.ai_edit.helper')}
              </p>
            </div>
            {!submitting && (
              <button
                type="button"
                onClick={handleClose}
                className="text-[var(--foreground-muted)] hover:text-[var(--foreground)] transition-colors"
              >
                <X className="h-6 w-6" />
              </button>
            )}
          </div>

          <div className="space-y-4">
            {!isFixedPlaybook && (
              <div>
                <label htmlFor="playbook_select" className="block text-sm font-medium text-[var(--foreground)] mb-2">
                  {t('admin.playbooks.ai_edit.playbook_label')}
                </label>
                <select
                  id="playbook_select"
                  value={selectedPlaybookId ?? ''}
                  onChange={(e) => setSelectedPlaybookId(Number(e.target.value))}
                  className={inputClasses}
                >
                  {playbookOptions.map((playbook) => (
                    <option key={playbook.id} value={playbook.id}>
                      {playbook.product_name}
                    </option>
                  ))}
                </select>
              </div>
            )}
            {isFixedPlaybook && playbookName && (
              <div>
                <p className="block text-sm font-medium text-[var(--foreground)] mb-2">
                  {t('admin.playbooks.ai_edit.playbook_label')}
                </p>
                <div className={inputClasses}>{playbookName}</div>
              </div>
            )}

            <div>
              <label htmlFor="ai_edit_scope" className="block text-sm font-medium text-[var(--foreground)] mb-2">
                {t('admin.playbooks.ai_edit.scope_label')}
              </label>
              <select
                id="ai_edit_scope"
                value={editScope}
                onChange={(event) => setEditScope(event.target.value as PlaybookAiEditScope)}
                className={inputClasses}
              >
                {playbookAiEditScopeOptions.map((option) => (
                  <option key={option.value} value={option.value}>
                    {t(option.labelKey)}
                  </option>
                ))}
              </select>
            </div>

            <div>
              <label htmlFor="ai_edit_instruction" className="block text-sm font-medium text-[var(--foreground)] mb-2">
                {t('admin.playbooks.ai_edit.instruction_label')}
              </label>
              <textarea
                id="ai_edit_instruction"
                value={instruction}
                onChange={(e) => setInstruction(e.target.value)}
                rows={4}
                className="block w-full rounded-lg border border-[var(--input-border)] bg-[var(--input)] px-3 py-2 text-sm text-[var(--foreground)] transition-colors focus:outline-none focus:border-[var(--ring)]"
                placeholder={t('admin.playbooks.ai_edit.instruction_placeholder')}
              />
            </div>

            <div className="rounded-lg border border-[var(--border)] bg-[var(--card)] p-4">
              <h4 className="text-sm font-semibold text-[var(--foreground)] mb-2">
                {t('admin.playbooks.ai_edit.examples_title')}
              </h4>
              <ul className="text-sm text-[var(--foreground-muted)] list-disc list-inside space-y-1">
                <li>{t('admin.playbooks.ai_edit.example_one')}</li>
                <li>{t('admin.playbooks.ai_edit.example_two')}</li>
                <li>{t('admin.playbooks.ai_edit.example_three')}</li>
              </ul>
            </div>

            {error && (
              <p className="text-sm text-[var(--error)]">{error}</p>
            )}
          </div>

          <div className="mt-6 flex justify-end gap-3">
            <Button type="button" variant="secondary" onClick={handleClose} disabled={submitting}>
              {t('admin.common.cancel')}
            </Button>
            <Button
              type="button"
              onClick={handleSubmit}
              loading={submitting}
              icon={<Sparkles className="h-4 w-4" />}
            >
              {submitting ? t('admin.playbooks.ai_edit.submitting') : t('admin.playbooks.ai_edit.submit')}
            </Button>
          </div>
        </div>
      </div>
    </div>
  )
}
