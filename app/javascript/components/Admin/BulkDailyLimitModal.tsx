import { useEffect, useState } from 'react'
import { Gauge } from 'lucide-react'
import { SlideOver, SlideOverFooterButtons } from '../ui/SlideOver'
import { t } from '../../lib/i18n'

interface BulkDailyLimitModalProps {
  open: boolean
  onClose: () => void
  selectedMailboxCount: number
  onSubmit: (dailyLimit: number) => void
}

export function BulkDailyLimitModal({
  open,
  onClose,
  selectedMailboxCount,
  onSubmit,
}: BulkDailyLimitModalProps) {
  const [dailyLimit, setDailyLimit] = useState<string>('50')
  const [isSubmitting, setIsSubmitting] = useState(false)

  useEffect(() => {
    if (!open) {
      setDailyLimit('50')
      setIsSubmitting(false)
    }
  }, [open])

  const handleSubmit = () => {
    const limit = parseInt(dailyLimit, 10)
    if (isNaN(limit) || limit <= 0 || limit > 2000) return
    setIsSubmitting(true)
    onSubmit(limit)
  }

  const handleClose = () => {
    setDailyLimit('50')
    setIsSubmitting(false)
    onClose()
  }

  const isValidLimit = () => {
    const limit = parseInt(dailyLimit, 10)
    return !isNaN(limit) && limit > 0 && limit <= 2000
  }

  return (
    <SlideOver
      open={open}
      onClose={handleClose}
      title={t('admin.mailboxes.bulk_update.title', { count: selectedMailboxCount })}
      width="md"
      footer={
        <SlideOverFooterButtons
          primaryLabel={t('admin.mailboxes.bulk_update.apply')}
          onPrimary={handleSubmit}
          primaryDisabled={!isValidLimit()}
          primaryLoading={isSubmitting}
          secondaryLabel={t('admin.common.cancel')}
          onSecondary={handleClose}
        />
      }
    >
      <div className="p-6 space-y-6">
        <div className="text-sm text-[var(--foreground-muted)] bg-[var(--card-hover)] rounded-lg px-4 py-3">
          {t('admin.mailboxes.bulk_update.description', { count: selectedMailboxCount })}
        </div>

        <div className="space-y-4">
          <div className="flex items-center gap-3 text-[var(--foreground)]">
            <Gauge className="h-5 w-5 text-[var(--foreground-muted)]" />
            <span className="font-medium">{t('admin.mailboxes.bulk_update.new_limit_label')}</span>
          </div>

          <div className="space-y-2">
            <input
              type="number"
              min="1"
              max="2000"
              value={dailyLimit}
              onChange={(e) => setDailyLimit(e.target.value)}
              className="w-full px-4 py-3 rounded-lg border border-[var(--border)] bg-transparent text-[var(--foreground)] text-lg font-medium focus:outline-none focus:ring-2 focus:ring-[var(--accent)] focus:border-transparent"
              placeholder="50"
            />
            <p className="text-sm text-[var(--foreground-muted)]">
              {t('admin.mailboxes.bulk_update.limit_help')}
            </p>
          </div>

          <div className="flex flex-wrap gap-2">
            {[25, 50, 100, 150, 200].map((preset) => (
              <button
                key={preset}
                type="button"
                onClick={() => setDailyLimit(preset.toString())}
                className={`
                  px-3 py-1.5 rounded-lg text-sm font-medium transition-colors
                  ${dailyLimit === preset.toString()
                    ? 'bg-[var(--accent)] text-[var(--accent-foreground)]'
                    : 'bg-[var(--card-hover)] text-[var(--foreground-muted)] hover:text-[var(--foreground)] hover:bg-[var(--card-hover)]'
                  }
                `}
              >
                {preset}
              </button>
            ))}
          </div>
        </div>
      </div>
    </SlideOver>
  )
}

export default BulkDailyLimitModal
