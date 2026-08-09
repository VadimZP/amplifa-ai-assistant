import { useRef, useState } from 'react'
import { createPortal } from 'react-dom'
import { Brain, Globe, Linkedin, MessageSquare, Sparkles } from 'lucide-react'
import { Badge, type BadgeProps } from '../ui/Badge'
import { SimpleProgressBar } from '../ui/ProgressBar'
import { renderBuyingSignalsMarkdown } from '../../lib/renderBuyingSignalsMarkdown'

export interface EnrichmentStatusItem {
  has_url: boolean
  scraped: boolean
  fresh: boolean
  error: string | null
}

export interface EnrichmentStatus {
  linkedin: EnrichmentStatusItem
  linkedin_posts: EnrichmentStatusItem & { post_count: number }
  company_website: EnrichmentStatusItem
  disc: { assessed: boolean; profile: string | null }
  buying_signals: {
    enabled: boolean
    state: 'fresh' | 'stale' | 'missing'
    generated_at: string | null
    summary_markdown?: string
  }
}

export interface PreviewProgress {
  status: 'in_progress' | 'completed' | 'error'
  in_progress: boolean
  progress_percent: number
  current_phase: string | null
  current_phase_label: string | null
  current_target_name: string | null
  preview_data?: unknown | null
}

interface LeadStatusLead {
  lead: {
    preferred_locale?: string | null
    enrichment_status: EnrichmentStatus
  }
}

interface SequenceLeadStatusStripProps {
  selectedLead: LeadStatusLead | null
  previewProgress: PreviewProgress | null
  usesBuyingSignalsPlaceholder: boolean
  enrichBeforePreview: boolean
  onEnrichBeforePreviewChange: (enabled: boolean) => void
  onOpenLeadDetail?: () => void
}

interface BuyingSignalsPopoverPosition {
  top: number
  left: number
  width: number
}

const BUYING_SIGNALS_POPOVER_CLOSE_DELAY_MS = 180

const getStatusBadge = (hasUrl: boolean, scraped: boolean, fresh: boolean, error: string | null) => {
  if (error) return { variant: 'error' as BadgeProps['variant'], label: 'Error' }
  if (!hasUrl) return { variant: 'draft' as BadgeProps['variant'], label: 'No URL' }
  if (!scraped) return { variant: 'warning' as BadgeProps['variant'], label: 'Pending' }
  if (!fresh) return { variant: 'warning' as BadgeProps['variant'], label: 'Stale' }
  return { variant: 'success' as BadgeProps['variant'], label: 'Fresh' }
}

const getBuyingSignalsBadge = (state: EnrichmentStatus['buying_signals']['state']) => {
  switch (state) {
    case 'fresh':
      return { variant: 'success' as BadgeProps['variant'], label: 'Fresh' }
    case 'stale':
      return { variant: 'warning' as BadgeProps['variant'], label: 'Stale' }
    case 'missing':
      return { variant: 'draft' as BadgeProps['variant'], label: 'Missing' }
  }
}

export function sequenceLeadNeedsEnrichment(enrichmentStatus: EnrichmentStatus | undefined, usesBuyingSignalsPlaceholder: boolean) {
  return Boolean(
    enrichmentStatus && (
      (enrichmentStatus.linkedin.has_url && (!enrichmentStatus.linkedin.scraped || enrichmentStatus.linkedin.error)) ||
      (enrichmentStatus.linkedin_posts.has_url && (!enrichmentStatus.linkedin_posts.scraped || enrichmentStatus.linkedin_posts.error)) ||
      (enrichmentStatus.company_website.has_url && (!enrichmentStatus.company_website.scraped || enrichmentStatus.company_website.error)) ||
      !enrichmentStatus.disc.assessed ||
      (usesBuyingSignalsPlaceholder && enrichmentStatus.buying_signals.enabled && enrichmentStatus.buying_signals.state === 'missing')
    )
  )
}

export default function SequenceLeadStatusStrip({
  selectedLead,
  previewProgress,
  usesBuyingSignalsPlaceholder,
  enrichBeforePreview,
  onEnrichBeforePreviewChange,
  onOpenLeadDetail
}: SequenceLeadStatusStripProps) {
  const [isBuyingSignalsPopoverOpen, setIsBuyingSignalsPopoverOpen] = useState(false)
  const [buyingSignalsPopoverPosition, setBuyingSignalsPopoverPosition] = useState<BuyingSignalsPopoverPosition | null>(null)
  const buyingSignalsPopoverTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const buyingSignalsTriggerRef = useRef<HTMLButtonElement | null>(null)

  if (!selectedLead) return null

  const enrichmentStatus = selectedLead.lead.enrichment_status
  const linkedinStatus = getStatusBadge(
    enrichmentStatus.linkedin.has_url,
    enrichmentStatus.linkedin.scraped,
    enrichmentStatus.linkedin.fresh,
    enrichmentStatus.linkedin.error
  )
  const linkedinPostsStatus = getStatusBadge(
    enrichmentStatus.linkedin_posts.has_url,
    enrichmentStatus.linkedin_posts.scraped,
    enrichmentStatus.linkedin_posts.fresh,
    enrichmentStatus.linkedin_posts.error
  )
  const websiteStatus = getStatusBadge(
    enrichmentStatus.company_website.has_url,
    enrichmentStatus.company_website.scraped,
    enrichmentStatus.company_website.fresh,
    enrichmentStatus.company_website.error
  )
  const buyingSignalsStatus = enrichmentStatus.buying_signals.enabled
    ? getBuyingSignalsBadge(enrichmentStatus.buying_signals.state)
    : null
  const discStatus = enrichmentStatus.disc.assessed
    ? { variant: 'success' as BadgeProps['variant'], label: enrichmentStatus.disc.profile || 'DISC' }
    : { variant: 'draft' as BadgeProps['variant'], label: 'Pending' }
  const showPreviewProgress = Boolean(previewProgress?.in_progress)
  const previewProgressLabel = previewProgress?.current_phase_label || 'Generating preview...'
  const previewProgressValue = previewProgress?.progress_percent ?? 0
  const needsEnrichment = sequenceLeadNeedsEnrichment(enrichmentStatus, usesBuyingSignalsPlaceholder)
  const detailButtonClasses = `flex items-center gap-1 rounded px-1 py-0.5 transition-colors ${onOpenLeadDetail ? 'hover:bg-[var(--card-hover)]' : ''}`
  const detailButtonTitle = onOpenLeadDetail ? 'Open enrichment details' : undefined

  const openBuyingSignalsPopover = () => {
    if (buyingSignalsPopoverTimeoutRef.current) {
      clearTimeout(buyingSignalsPopoverTimeoutRef.current)
      buyingSignalsPopoverTimeoutRef.current = null
    }

    if (buyingSignalsTriggerRef.current) {
      const rect = buyingSignalsTriggerRef.current.getBoundingClientRect()
      setBuyingSignalsPopoverPosition({
        top: rect.bottom + 8,
        left: Math.min(rect.left, window.innerWidth - 360 - 16),
        width: 360
      })
    }

    setIsBuyingSignalsPopoverOpen(true)
  }

  const closeBuyingSignalsPopoverWithDelay = () => {
    if (buyingSignalsPopoverTimeoutRef.current) {
      clearTimeout(buyingSignalsPopoverTimeoutRef.current)
    }

    buyingSignalsPopoverTimeoutRef.current = setTimeout(() => {
      setIsBuyingSignalsPopoverOpen(false)
      buyingSignalsPopoverTimeoutRef.current = null
    }, BUYING_SIGNALS_POPOVER_CLOSE_DELAY_MS)
  }

  const openLeadDetail = () => onOpenLeadDetail?.()

  return showPreviewProgress ? (
    <div className="flex flex-col gap-1">
      <span className="text-[10px] text-[var(--foreground-muted)]">
        {previewProgressLabel}
      </span>
      <SimpleProgressBar value={previewProgressValue} max={100} />
    </div>
  ) : (
    <div className="flex flex-col gap-1">
      <div className="flex flex-wrap items-center gap-2">
        {selectedLead.lead.preferred_locale && (
          <button
            type="button"
            onClick={openLeadDetail}
            className={detailButtonClasses}
            title={detailButtonTitle}
          >
            <Globe className="h-3.5 w-3.5 text-violet-400" />
            <span className="text-[10px] text-[var(--foreground-muted)]">Locale</span>
            <Badge
              variant="default"
              size="sm"
              className="h-5 px-1.5 text-[10px] rounded-full tracking-wide"
            >
              {selectedLead.lead.preferred_locale}
            </Badge>
          </button>
        )}
        <button
          type="button"
          onClick={openLeadDetail}
          className={detailButtonClasses}
          title={detailButtonTitle}
        >
          <Linkedin className="h-3.5 w-3.5 text-blue-400" />
          <span className="text-[10px] text-[var(--foreground-muted)]">LinkedIn</span>
          <Badge
            variant={linkedinStatus.variant}
            size="sm"
            className="h-5 px-1.5 text-[10px] rounded-full tracking-wide"
          >
            {linkedinStatus.label}
          </Badge>
        </button>
        <button
          type="button"
          onClick={openLeadDetail}
          className={detailButtonClasses}
          title={detailButtonTitle}
        >
          <MessageSquare className="h-3.5 w-3.5 text-blue-300" />
          <span className="text-[10px] text-[var(--foreground-muted)]">Posts</span>
          <Badge
            variant={linkedinPostsStatus.variant}
            size="sm"
            className="h-5 px-1.5 text-[10px] rounded-full tracking-wide"
          >
            {linkedinPostsStatus.label}
          </Badge>
        </button>
        <button
          type="button"
          onClick={openLeadDetail}
          className={detailButtonClasses}
          title={detailButtonTitle}
        >
          <Globe className="h-3.5 w-3.5 text-green-400" />
          <span className="text-[10px] text-[var(--foreground-muted)]">Website</span>
          <Badge
            variant={websiteStatus.variant}
            size="sm"
            className="h-5 px-1.5 text-[10px] rounded-full tracking-wide"
          >
            {websiteStatus.label}
          </Badge>
        </button>
        {buyingSignalsStatus && (
          <div
            onMouseEnter={openBuyingSignalsPopover}
            onMouseLeave={closeBuyingSignalsPopoverWithDelay}
          >
            <button
              ref={buyingSignalsTriggerRef}
              type="button"
              onClick={openLeadDetail}
              className={detailButtonClasses}
            >
              <Sparkles className="h-3.5 w-3.5 text-amber-400" />
              <span className="text-[10px] text-[var(--foreground-muted)]">Signals</span>
              <Badge
                variant={buyingSignalsStatus.variant}
                size="sm"
                className="h-5 px-1.5 text-[10px] rounded-full tracking-wide"
              >
                {buyingSignalsStatus.label}
              </Badge>
            </button>

            {enrichmentStatus.buying_signals.summary_markdown?.trim() &&
              buyingSignalsPopoverPosition &&
              createPortal(
                <div
                  className={`fixed z-[120] rounded-lg border border-[var(--border)] bg-[var(--card)] p-3 text-xs shadow-lg transition-opacity ${isBuyingSignalsPopoverOpen ? 'opacity-100 visible' : 'opacity-0 invisible'}`}
                  style={{
                    top: buyingSignalsPopoverPosition.top,
                    left: buyingSignalsPopoverPosition.left,
                    width: buyingSignalsPopoverPosition.width
                  }}
                  onMouseEnter={openBuyingSignalsPopover}
                  onMouseLeave={closeBuyingSignalsPopoverWithDelay}
                >
                  <p className="mb-1 font-medium text-[var(--foreground)]">Buying signals summary</p>
                  {enrichmentStatus.buying_signals.generated_at && (
                    <p className="mb-2 text-[10px] text-[var(--foreground-muted)]">
                      Created {new Date(enrichmentStatus.buying_signals.generated_at).toLocaleDateString()}
                    </p>
                  )}
                  <div className="max-h-72 overflow-y-auto text-[var(--foreground-muted)] [&_a]:text-[var(--accent)] [&_p]:mb-2 [&_ul]:list-disc [&_ul]:pl-4">
                    {renderBuyingSignalsMarkdown(enrichmentStatus.buying_signals.summary_markdown)}
                  </div>
                </div>,
                document.body
              )}
          </div>
        )}
        <button
          type="button"
          onClick={openLeadDetail}
          className={detailButtonClasses}
          title={detailButtonTitle}
        >
          <Brain className="h-3.5 w-3.5 text-purple-400" />
          <span className="text-[10px] text-[var(--foreground-muted)]">DISC</span>
          <Badge
            variant={discStatus.variant}
            size="sm"
            className="h-5 px-1.5 text-[10px] rounded-full tracking-wide"
          >
            {discStatus.label}
          </Badge>
        </button>
      </div>
      {needsEnrichment && (
        <label className="flex items-center gap-1.5 text-[10px] text-[var(--foreground-muted)] select-none whitespace-nowrap">
          <input
            type="checkbox"
            checked={enrichBeforePreview}
            onChange={(e) => onEnrichBeforePreviewChange(e.target.checked)}
            className="h-3.5 w-3.5 rounded border-[var(--input-border)] bg-[var(--input)] text-[var(--accent)] focus:ring-[var(--accent)]"
          />
          <span>Enrich before generating preview</span>
        </label>
      )}
    </div>
  )
}
