import { useState, useEffect, useCallback, useRef } from 'react'
import { SlideOver } from './ui/SlideOver'
import { SlideOverHeader } from './ui/SlideOverHeader'
import { SimpleProgressBar } from './ui/ProgressBar'
import { t } from '../lib/i18n'
import { AlertCircle, Loader2 } from 'lucide-react'
import LeadDetailContent, { LeadDetailData } from './LeadDetailContent'
import { useActionCableChannel } from '../lib/useActionCableChannel'

interface LeadGenerationProgress {
  status: 'not_started' | 'enriching' | 'generating' | 'completed' | 'error'
  in_progress: boolean
  progress_percent: number
  current_phase: string | null
  current_phase_label: string | null
  current_target_name: string | null
  current_step_name: string | null
  generated_count: number
  total_count: number
  error_count: number
  generation_error?: string | null
  lead_data: Partial<LeadDetailData> | null
}

interface LeadDetailSlideOverProps {
  open: boolean
  onClose: () => void
  leadId: number | null
  agentLeadId: number | null
  organizationId: number | null
}

export default function LeadDetailSlideOver({
  open,
  onClose,
  leadId,
  agentLeadId,
  organizationId
}: LeadDetailSlideOverProps) {
  const [data, setData] = useState<LeadDetailData | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [generatingFor, setGeneratingFor] = useState<number | null>(null)
  const [enrichingType, setEnrichingType] = useState<string | null>(null)
  const [actionError, setActionError] = useState<string | null>(null)
  const [generationProgress, setGenerationProgress] = useState<LeadGenerationProgress | null>(null)
  const completionHandledRef = useRef(false)
  const buyingSignalsCableReceivedRef = useRef(false)
  const missedAsyncBroadcastTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null)

  const fetchData = useCallback(async () => {
    if (!leadId || !organizationId || !open) return null

    setLoading(true)
    setError(null)
    
    try {
      const searchParams = new URLSearchParams()
      if (agentLeadId) searchParams.set('agent_lead_id', String(agentLeadId))

      const response = await fetch(`/admin/organizations/${organizationId}/leads/${leadId}/modal?${searchParams.toString()}`, {
        headers: {
          'Accept': 'application/json',
          'X-Requested-With': 'XMLHttpRequest'
        }
      })

      if (!response.ok) {
        throw new Error(`Error ${response.status}: ${response.statusText}`)
      }

      const jsonData = await response.json()
      setData(jsonData)
      return jsonData as LeadDetailData
    } catch (err) {
      console.error('Failed to fetch lead data:', err)
      setError(err instanceof Error ? err.message : 'Failed to load data')
      return null
    } finally {
      setLoading(false)
    }
  }, [agentLeadId, leadId, organizationId, open])

  const clearMissedAsyncBroadcastFallback = useCallback(() => {
    if (missedAsyncBroadcastTimeoutRef.current) {
      clearTimeout(missedAsyncBroadcastTimeoutRef.current)
      missedAsyncBroadcastTimeoutRef.current = null
    }
  }, [])

  const startMissedAsyncBroadcastFallback = useCallback((expectedAgentLeadId: number) => {
    clearMissedAsyncBroadcastFallback()

    missedAsyncBroadcastTimeoutRef.current = setTimeout(async () => {
      missedAsyncBroadcastTimeoutRef.current = null
      if (buyingSignalsCableReceivedRef.current) return

      const latestData = await fetchData()
      if (buyingSignalsCableReceivedRef.current) return
      if (latestData?.buying_signals_summary_status === 'processing') return

      setActionError('Buying signals enrichment did not start. It may already be running for this company and agent.')
      setGeneratingFor(current => current === expectedAgentLeadId ? null : current)
      setGenerationProgress(null)
      setEnrichingType(current => current === 'buying_signals' ? null : current)
      setTimeout(() => setActionError(null), 5000)
    }, 5000)
  }, [clearMissedAsyncBroadcastFallback, fetchData])

  useEffect(() => {
      if (open && leadId && organizationId) {
        fetchData()
    } else if (!open) {
      setData(null)
      setError(null)
      setGenerationProgress(null)
      completionHandledRef.current = false
      buyingSignalsCableReceivedRef.current = false
      clearMissedAsyncBroadcastFallback()
    }
  }, [open, leadId, organizationId, fetchData, clearMissedAsyncBroadcastFallback])

  useEffect(() => clearMissedAsyncBroadcastFallback, [clearMissedAsyncBroadcastFallback])

  useActionCableChannel<LeadGenerationProgress>(
    { channel: 'LeadGenerationChannel', agent_lead_id: generatingFor },
    {
      received: (progressData) => {
        buyingSignalsCableReceivedRef.current = true
        clearMissedAsyncBroadcastFallback()
        setGenerationProgress(progressData)

        if (progressData.status === 'error') {
          setActionError(progressData.generation_error || t('admin.leads.modal.enrichment.error', { defaultValue: 'Enrichment failed' }))
          setGeneratingFor(null)
          setGenerationProgress(null)
          setEnrichingType(null)
          setTimeout(() => setActionError(null), 5000)
          return
        }
        
        if (progressData.status === 'completed' && !completionHandledRef.current) {
          completionHandledRef.current = true
          
          if (progressData.lead_data) {
            setData(prev => prev ? { ...prev, ...progressData.lead_data } : prev)
          }
          
          setTimeout(() => {
            fetchData()
            setGeneratingFor(null)
            setGenerationProgress(null)
            setEnrichingType(null)
          }, 500)
        }
      }
    }
  )

  const generateMessages = async (agentLeadId: number) => {
    if (!organizationId || !leadId) return
    
    setGeneratingFor(agentLeadId)
    setActionError(null)
    completionHandledRef.current = false
    setGenerationProgress({
      status: 'enriching',
      in_progress: true,
      progress_percent: 0,
      current_phase: null,
      current_phase_label: t('admin.leads.modal.progress.starting', { defaultValue: 'Starting...' }),
      current_target_name: null,
      current_step_name: null,
      generated_count: 0,
      total_count: 0,
      error_count: 0,
      lead_data: null
    })
    
    try {
      const response = await fetch(`/admin/organizations/${organizationId}/leads/${leadId}/generate_messages`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'X-CSRF-Token': (document.querySelector('meta[name="csrf-token"]') as HTMLMetaElement)?.content || ''
        },
        body: JSON.stringify({ agent_lead_id: agentLeadId })
      })
      
      if (!response.ok) {
        throw new Error('Failed to generate messages')
      }
    } catch (err) {
      console.error('Error generating messages:', err)
      setActionError(t('admin.leads.modal.messages.error', { defaultValue: 'Generation failed' }))
      setGeneratingFor(null)
      setGenerationProgress(null)
      setTimeout(() => setActionError(null), 3000)
    }
  }

  const triggerEnrichment = async (enrichmentType: string) => {
    if (!organizationId || !leadId) return
    setEnrichingType(enrichmentType)
    setActionError(null)
    const isAsyncBuyingSignals = enrichmentType === 'buying_signals'
    let keepEnrichingState = false

    if (isAsyncBuyingSignals) {
      if (!agentLeadId) {
        setActionError('Buying signals enrichment requires an agent context')
        setEnrichingType(null)
        setTimeout(() => setActionError(null), 5000)
        return
      }

      buyingSignalsCableReceivedRef.current = false
      clearMissedAsyncBroadcastFallback()
      setGeneratingFor(agentLeadId)
      completionHandledRef.current = false
      setGenerationProgress({
        status: 'enriching',
        in_progress: true,
        progress_percent: 0,
        current_phase: 'buying_signals',
        current_phase_label: 'Starting buying signals enrichment...',
        current_target_name: data?.display_name || null,
        current_step_name: null,
        generated_count: 0,
        total_count: 0,
        error_count: 0,
        lead_data: null,
        generation_error: null
      })
    }

    try {
      const response = await fetch(`/admin/organizations/${organizationId}/leads/${leadId}/trigger_enrichment`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'X-CSRF-Token': (document.querySelector('meta[name="csrf-token"]') as HTMLMetaElement)?.content || ''
        },
        body: JSON.stringify({ enrichment_type: enrichmentType, agent_lead_id: agentLeadId })
      })
      
      const jsonData = await response.json()
      
      if (!response.ok || !jsonData.success) {
        throw new Error(jsonData.error || 'Failed to trigger enrichment')
      }

      if (jsonData.async && jsonData.agent_lead_id) {
        setGeneratingFor(jsonData.agent_lead_id)
        if (isAsyncBuyingSignals) {
          startMissedAsyncBroadcastFallback(jsonData.agent_lead_id)
        }
        keepEnrichingState = true
        return
      }
      
      if (jsonData.lead) {
        setData(jsonData.lead)
      } else {
        await fetchData()
      }
    } catch (err) {
      console.error('Error triggering enrichment:', err)
      const errorMessage = err instanceof Error ? err.message : 'Enrichment failed'
      setActionError(errorMessage)
      if (isAsyncBuyingSignals) {
        clearMissedAsyncBroadcastFallback()
        setGeneratingFor(null)
        setGenerationProgress(null)
        fetchData()
      }
      setTimeout(() => setActionError(null), 5000)
    } finally {
      if (!keepEnrichingState) {
        setEnrichingType(null)
      }
    }
  }

  const Skeleton = ({ className = "h-4 w-full" }: { className?: string }) => (
    <div className={`animate-pulse bg-white/10 rounded ${className}`} />
  )

  const renderContent = () => {
    if (loading && !data) {
      return (
        <div className="p-6 space-y-8">
          <div className="space-y-4">
            <Skeleton className="h-8 w-1/2" />
            <Skeleton className="h-4 w-1/3" />
          </div>
          <div className="space-y-2">
            <Skeleton className="h-4 w-full" />
            <Skeleton className="h-4 w-full" />
            <Skeleton className="h-4 w-2/3" />
          </div>
        </div>
      )
    }

    if (error) {
      return (
        <div className="p-6 flex flex-col items-center justify-center h-full text-center space-y-4">
          <AlertCircle className="size-12 text-red-500" />
          <div className="space-y-2">
            <h3 className="text-lg font-medium text-white">Error Loading Data</h3>
            <p className="text-neutral-400 max-w-xs mx-auto">{error}</p>
          </div>
          <button 
            onClick={fetchData}
            className="px-4 py-2 bg-white/10 hover:bg-white/20 text-white rounded-lg transition-colors"
          >
            Retry
          </button>
        </div>
      )
    }

    if (!data) return null

    return (
      <div className="flex flex-col">
        <SlideOverHeader 
          title={data.display_name}
          badge={{ 
            label: 'Contact', 
            variant: 'default' 
          }}
          gradient="blue"
          onClose={onClose}
          avatarUrl={data.linkedin_profile_photo_url}
        />

        {generationProgress?.in_progress && (
          <div className="mx-6 mt-4 p-4 bg-[var(--card)] border border-[var(--border)] rounded-lg space-y-3">
            <div className="flex items-center justify-between text-sm">
              <div className="flex items-center gap-2 text-[var(--foreground)]">
                <Loader2 className="w-4 h-4 animate-spin text-[var(--primary)]" />
                <span>
                  {generationProgress.current_phase_label || t('admin.leads.modal.progress.generating', { defaultValue: 'Generating messages...' })}
                </span>
              </div>
              <span className="text-[var(--foreground-muted)]">
                {generationProgress.progress_percent}%
              </span>
            </div>
            <SimpleProgressBar value={generationProgress.progress_percent} max={100} />
            {generationProgress.total_count > 0 && (
              <div className="flex items-center justify-between text-xs text-[var(--foreground-muted)]">
                <span>
                  {t('admin.leads.modal.progress.messages_generated', {
                    generated: generationProgress.generated_count,
                    total: generationProgress.total_count,
                    defaultValue: `${generationProgress.generated_count} of ${generationProgress.total_count} messages`
                  })}
                </span>
                {generationProgress.error_count > 0 && (
                  <span className="text-[var(--error)]">
                    {t('admin.leads.modal.progress.errors', { count: generationProgress.error_count, defaultValue: `${generationProgress.error_count} errors` })}
                  </span>
                )}
              </div>
            )}
          </div>
        )}

        <div className="p-6 pb-20">
          <LeadDetailContent
            data={data}
            onEnrichment={triggerEnrichment}
            onGenerateMessages={generateMessages}
            enrichingType={enrichingType}
            generatingFor={generatingFor}
            actionError={actionError}
            variant="slideover"
          />
        </div>
      </div>
    )
  }

  return (
    <SlideOver
      open={open}
      onClose={onClose}
      width="lg"
      className="bg-[#101012]"
    >
      {renderContent()}
    </SlideOver>
  )
}
