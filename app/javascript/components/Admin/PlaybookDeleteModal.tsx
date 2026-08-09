import { Badge, BadgeProps } from '../ui/Badge'
import { Button } from '../ui/Button'
import { AlertTriangle, PauseCircle, Trash2, X } from 'lucide-react'
import { t } from '../../lib/i18n'

interface AffectedAgent {
  id: number
  name: string
  status: string
  will_pause: boolean
}

interface PlaybookDeleteModalProps {
  isOpen: boolean
  onClose: () => void
  onConfirm: () => void
  isDeleting: boolean
  affectedAgents: AffectedAgent[]
}

function getStatusBadgeVariant(status: string): BadgeProps['variant'] {
  switch (status) {
    case 'draft':
      return 'draft'
    case 'ready':
      return 'info'
    case 'active':
      return 'success'
    case 'paused':
      return 'warning'
    case 'completed':
      return 'approved'
    default:
      return 'default'
  }
}

export default function PlaybookDeleteModal({
  isOpen,
  onClose,
  onConfirm,
  isDeleting,
  affectedAgents
}: PlaybookDeleteModalProps) {
  if (!isOpen) return null

  const pausedAgentsCount = affectedAgents.filter((agent) => agent.will_pause).length

  return (
    <div className="fixed inset-0 z-50 overflow-y-auto">
      <div className="flex min-h-screen items-center justify-center p-4">
        <button
          type="button"
          aria-label={t('admin.common.cancel')}
          className="fixed inset-0 bg-black/60 backdrop-blur-sm transition-opacity"
          onClick={onClose}
          disabled={isDeleting}
        />

        <div className="relative w-full max-w-2xl rounded-xl border border-[var(--border)] bg-[var(--card)] p-6 shadow-2xl">
          <div className="mb-4 flex items-start justify-between gap-4">
            <div>
              <h3 className="flex items-center gap-2 text-xl font-semibold text-[var(--foreground)]">
                <AlertTriangle className="h-5 w-5 text-[var(--warning)]" />
                {t('admin.playbooks.delete_modal.title')}
              </h3>
              <p className="mt-1 text-sm text-[var(--foreground-muted)]">
                {t('admin.playbooks.delete_modal.description')}
              </p>
            </div>
            {!isDeleting && (
              <button
                type="button"
                onClick={onClose}
                className="text-[var(--foreground-muted)] transition-colors hover:text-[var(--foreground)]"
              >
                <X className="h-6 w-6" />
              </button>
            )}
          </div>

          <div className="space-y-4">
            {affectedAgents.length > 0 ? (
              <div className="space-y-3">
                <p className="text-sm text-[var(--foreground-muted)]">
                  {t('admin.playbooks.delete_modal.affected_agents_description')}
                </p>
                {pausedAgentsCount > 0 && (
                  <div className="rounded-lg border border-[var(--warning)]/30 bg-[var(--warning)]/10 p-3 text-sm text-[var(--foreground)]">
                    <div className="flex items-start gap-2">
                      <PauseCircle className="mt-0.5 h-4 w-4 text-[var(--warning)]" />
                      <span>{t('admin.playbooks.delete_modal.pause_notice')}</span>
                    </div>
                  </div>
                )}

                <div className="rounded-lg border border-[var(--border)] bg-[rgba(255,255,255,0.02)]">
                  <div className="border-b border-[var(--border)] px-4 py-3 text-sm font-medium text-[var(--foreground)]">
                    {t('admin.playbooks.delete_modal.affected_agents_title')}
                  </div>
                  <ul className="max-h-72 divide-y divide-[var(--border)] overflow-y-auto">
                    {affectedAgents.map((agent) => (
                      <li key={agent.id} className="flex items-center justify-between gap-3 px-4 py-3">
                        <div className="min-w-0">
                          <p className="truncate text-sm font-medium text-[var(--foreground)]">{agent.name}</p>
                          {agent.will_pause && (
                            <p className="mt-1 text-xs text-[var(--warning)]">
                              {t('admin.playbooks.delete_modal.will_pause')}
                            </p>
                          )}
                        </div>
                        <Badge variant={getStatusBadgeVariant(agent.status)}>
                          {t(`admin.agents.statuses.${agent.status}`)}
                        </Badge>
                      </li>
                    ))}
                  </ul>
                </div>
              </div>
            ) : (
              <div className="rounded-lg border border-[var(--border)] bg-[rgba(255,255,255,0.02)] p-4 text-sm text-[var(--foreground-muted)]">
                {t('admin.playbooks.delete_modal.no_affected_agents')}
              </div>
            )}
          </div>

          <div className="mt-6 flex justify-end gap-3">
            <Button type="button" variant="secondary" onClick={onClose} disabled={isDeleting}>
              {t('admin.common.cancel')}
            </Button>
            <Button
              type="button"
              variant="destructive"
              onClick={onConfirm}
              loading={isDeleting}
              icon={<Trash2 className="h-4 w-4" />}
            >
              {t('admin.playbooks.delete_modal.confirm_button')}
            </Button>
          </div>
        </div>
      </div>
    </div>
  )
}
