import { useEffect, useMemo, useState } from 'react'
import { Check, Users, AlertTriangle, Search, X } from 'lucide-react'
import { toast } from 'sonner'
import { SlideOver, SlideOverFooterButtons } from '../ui/SlideOver'
import { t } from '../../lib/i18n'

interface AgentSelectionOption {
  id: number
  name: string
  steps_count: number
}

interface SourceAgentOption extends AgentSelectionOption {
  organization_id: number
  organization_name: string
}

interface ImportSequenceModalProps {
  open: boolean
  onClose: () => void
  sourceAgents: SourceAgentOption[]
  organizationId: number
  targetAgentId?: number | null
  targetAgents?: AgentSelectionOption[]
  hasExistingSteps?: boolean
  onSuccess?: () => void
}

interface ImportSequenceResponse {
  success?: boolean
  message?: string
  error?: string
}

async function parseImportSequenceResponse(response: Response): Promise<ImportSequenceResponse> {
  const responseText = await response.text()

  if (!responseText.trim()) {
    return {}
  }

  try {
    return JSON.parse(responseText) as ImportSequenceResponse
  } catch {
    const trimmedResponseText = responseText.trim()

    return {
      success: false,
      error: trimmedResponseText.startsWith('<')
        ? response.statusText || 'Import failed'
        : trimmedResponseText || response.statusText || 'Import failed'
    }
  }
}

export function ImportSequenceModal({
  open,
  onClose,
  sourceAgents,
  organizationId,
  targetAgentId,
  targetAgents,
  hasExistingSteps,
  onSuccess,
}: ImportSequenceModalProps) {
  const [selectedTargetId, setSelectedTargetId] = useState<number | null>(targetAgentId ?? null)
  const [selectedSourceId, setSelectedSourceId] = useState<number | null>(null)
  const [sourceSearchQuery, setSourceSearchQuery] = useState('')
  const [isSubmitting, setIsSubmitting] = useState(false)

  useEffect(() => {
    if (!open) return
    setSelectedTargetId(targetAgentId ?? null)
    setSelectedSourceId(null)
    setSourceSearchQuery('')
    setIsSubmitting(false)
  }, [open, targetAgentId])

  const effectiveTargetId = targetAgentId ?? selectedTargetId
  const selectedTarget = targetAgents?.find(agent => agent.id === effectiveTargetId) ?? null
  const resolvedHasExistingSteps = selectedTarget
    ? selectedTarget.steps_count > 0
    : Boolean(hasExistingSteps)

  const availableSourceAgents = useMemo(() => {
    if (!effectiveTargetId) return sourceAgents
    return sourceAgents.filter(agent => agent.id !== effectiveTargetId)
  }, [effectiveTargetId, sourceAgents])

  const filteredSourceAgents = useMemo(() => {
    const query = sourceSearchQuery.trim().toLowerCase()
    if (!query) return availableSourceAgents

    return availableSourceAgents.filter(agent =>
      agent.name.toLowerCase().includes(query) ||
      agent.organization_name.toLowerCase().includes(query)
    )
  }, [availableSourceAgents, sourceSearchQuery])

  const groupedSourceAgents = useMemo(() => {
    return filteredSourceAgents.reduce<Array<{ organizationName: string; agents: SourceAgentOption[] }>>((groups, agent) => {
      const existingGroup = groups.find(group => group.organizationName === agent.organization_name)
      if (existingGroup) {
        existingGroup.agents.push(agent)
      } else {
        groups.push({ organizationName: agent.organization_name, agents: [agent] })
      }

      return groups
    }, [])
  }, [filteredSourceAgents])

  const showTargetSelection = Boolean(targetAgents && targetAgents.length > 0 && !targetAgentId)

  const handleImport = () => {
    if (!effectiveTargetId || !selectedSourceId) return

    if (resolvedHasExistingSteps) {
      const confirmed = window.confirm(t('admin.sequence_steps.import.confirm_replace'))
      if (!confirmed) return
    }

    setIsSubmitting(true)
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || ''
    fetch(
      `/admin/organizations/${organizationId}/agents/${effectiveTargetId}/sequence_steps/import_sequence`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'X-CSRF-Token': csrfToken,
          'X-Requested-With': 'XMLHttpRequest'
        },
        body: JSON.stringify({ source_agent_id: selectedSourceId })
      }
    )
      .then(async (response) => {
        const result = await parseImportSequenceResponse(response)

        if (!response.ok || !result.success) {
          throw new Error(result.error || response.statusText || 'Import failed')
        }

        toast.success(result.message || t('admin.sequence_steps.import.success'))
        onSuccess?.()
        handleClose()
      })
      .catch((error: Error) => {
        toast.error(error.message)
        setIsSubmitting(false)
      })
      .finally(() => {
        setIsSubmitting(false)
      })
  }

  const handleClose = () => {
    setSelectedTargetId(targetAgentId ?? null)
    setSelectedSourceId(null)
    setSourceSearchQuery('')
    setIsSubmitting(false)
    onClose()
  }

  const renderAgentButton = (
    agent: AgentSelectionOption,
    selectedId: number | null,
    onSelect: (id: number) => void
  ) => (
    <button
      key={agent.id}
      type="button"
      onClick={() => onSelect(agent.id)}
      className={`
        w-full flex items-center justify-between p-4 rounded-lg border transition-colors
        ${selectedId === agent.id
          ? 'border-[var(--accent)] bg-[var(--accent)]/10'
          : 'border-[var(--border)] hover:border-[var(--foreground-subtle)] hover:bg-[var(--card-hover)]'
        }
      `}
    >
      <div className="flex-1 text-left">
        <div className="font-medium text-[var(--foreground)]">
          {agent.name}
        </div>
        <div className="text-sm text-[var(--foreground-muted)]">
          {t('admin.sequence_steps.import.steps_count', { count: agent.steps_count })}
        </div>
      </div>
      {selectedId === agent.id && (
        <div className="w-5 h-5 rounded-full bg-[var(--accent)] flex items-center justify-center shrink-0">
          <Check className="w-3 h-3 text-white" />
        </div>
      )}
    </button>
  )

  return (
    <SlideOver
      open={open}
      onClose={handleClose}
      title={t('admin.sequence_steps.import.title')}
      width="md"
      footer={
        <SlideOverFooterButtons
          primaryLabel={t('admin.sequence_steps.import.import_button')}
          onPrimary={handleImport}
          primaryDisabled={!effectiveTargetId || !selectedSourceId}
          primaryLoading={isSubmitting}
          secondaryLabel={t('admin.sequence_steps.import.cancel')}
          onSecondary={handleClose}
        />
      }
    >
      <div className="p-6 space-y-4">
        <div className="text-sm text-[var(--foreground-muted)] bg-[var(--card-hover)] rounded-lg px-4 py-3">
          {t('admin.sequence_steps.import.description')}
        </div>
        <div className="p-4 bg-red-900/50 border border-red-500/50 rounded-lg flex gap-3 text-red-200">
          <AlertTriangle className="h-5 w-5 shrink-0 mt-0.5" />
          <div className="text-sm">
            {t('admin.sequence_steps.import.destructive_warning')}
          </div>
        </div>

        {showTargetSelection && (
          <div className="space-y-2">
            <div className="text-xs font-semibold uppercase tracking-wide text-[var(--foreground-subtle)]">
              {t('admin.sequence_steps.import.select_target_agent')}
            </div>
            <div className="space-y-2 max-h-[220px] overflow-y-auto">
              {targetAgents?.length ? (
                targetAgents.map(agent => renderAgentButton(agent, selectedTargetId, setSelectedTargetId))
              ) : (
                <div className="text-center py-6 text-[var(--foreground-muted)]">
                  <Users className="h-8 w-8 mx-auto mb-2" />
                  <p>{t('admin.sequence_steps.import.no_agents')}</p>
                </div>
              )}
            </div>
          </div>
        )}

        <div className="space-y-2">
          <div className="text-xs font-semibold uppercase tracking-wide text-[var(--foreground-subtle)]">
            {t('admin.sequence_steps.import.select_source_agent')}
          </div>
          <div className="relative">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-[var(--foreground-muted)]" />
            <input
              type="text"
              value={sourceSearchQuery}
              onChange={(event) => setSourceSearchQuery(event.target.value)}
              placeholder={t('admin.sequence_steps.import.search_placeholder')}
              className="w-full pl-10 pr-9 py-2 rounded-lg border border-[var(--border)] bg-transparent text-[var(--foreground)] placeholder-[var(--foreground-muted)] focus:outline-none focus:ring-2 focus:ring-[var(--accent)] focus:border-transparent"
            />
            {sourceSearchQuery && (
              <button
                type="button"
                onClick={() => setSourceSearchQuery('')}
                className="absolute right-2 top-1/2 -translate-y-1/2 p-1 rounded hover:bg-[var(--card-hover)]"
                aria-label={t('admin.common.clear')}
              >
                <X className="h-4 w-4 text-[var(--foreground-muted)]" />
              </button>
            )}
          </div>
          <div className="space-y-2 max-h-[300px] overflow-y-auto">
            {availableSourceAgents.length === 0 ? (
              <div className="text-center py-8 text-[var(--foreground-muted)]">
                <Users className="h-8 w-8 mx-auto mb-2" />
                <p>{t('admin.sequence_steps.import.no_agents')}</p>
              </div>
            ) : groupedSourceAgents.length === 0 ? (
              <div className="text-center py-8 text-[var(--foreground-muted)]">
                <Users className="h-8 w-8 mx-auto mb-2" />
                <p>{t('admin.sequence_steps.import.no_matching_agents')}</p>
              </div>
            ) : (
              groupedSourceAgents.map(group => (
                <div key={group.organizationName} className="space-y-2">
                  <div className="text-xs font-semibold uppercase tracking-wide text-[var(--foreground-subtle)]">
                    {group.organizationName}
                  </div>
                  <div className="space-y-2">
                    {group.agents.map(agent => renderAgentButton(agent, selectedSourceId, setSelectedSourceId))}
                  </div>
                </div>
              ))
            )}
          </div>
        </div>
      </div>
    </SlideOver>
  )
}

export default ImportSequenceModal
