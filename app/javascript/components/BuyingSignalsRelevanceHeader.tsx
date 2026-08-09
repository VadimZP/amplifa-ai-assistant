import { CircleHelp } from 'lucide-react'
import { t } from '../lib/i18n'

export function BuyingSignalsRelevanceHeader() {
  return (
    <span className="inline-flex items-center gap-1.5">
      {t('customer.agents.table.relevance')}
      <span className="group relative inline-flex" tabIndex={0} aria-label={t('customer.agents.table.relevance_tooltip_label')}>
        <CircleHelp className="h-3.5 w-3.5 text-[var(--foreground-subtle)]" aria-hidden="true" />
        <span className="pointer-events-none absolute left-1/2 top-full z-20 mt-2 w-64 max-w-[min(16rem,calc(100vw-2rem))] -translate-x-1/2 whitespace-normal break-words rounded-xl border border-[var(--border)] bg-[var(--background-elevated)] px-3 py-2 text-xs font-normal leading-5 text-[var(--foreground)] opacity-0 shadow-[var(--shadow-md)] transition-opacity group-hover:opacity-100 group-focus:opacity-100">
          {t('customer.agents.table.relevance_tooltip')}
        </span>
      </span>
    </span>
  )
}
