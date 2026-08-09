import { t } from '../lib/i18n'
import { renderBuyingSignalsMarkdown } from '../lib/renderBuyingSignalsMarkdown'

interface BuyingSignalsHighlightsProps {
  highlights: string[]
}

export function BuyingSignalsHighlights({ highlights }: BuyingSignalsHighlightsProps) {
  const summary = highlights.map(highlight => highlight.trim()).find(Boolean)
  if (!summary) return null

  return (
    <div className="rounded-[20px] border border-[var(--accent)]/20 bg-[var(--accent)]/8 p-4">
      <p className="text-xs uppercase tracking-wide text-[var(--foreground-subtle)]">
        {t('customer.agents.buying_signals.highlights')}
      </p>
      <div className="mt-2">
        {renderBuyingSignalsMarkdown(summary)}
      </div>
    </div>
  )
}
