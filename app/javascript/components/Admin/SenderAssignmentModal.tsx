import { useState, useMemo } from 'react'
import { Search, UserPlus, X } from 'lucide-react'
import { SlideOver, SlideOverFooterButtons } from '../ui/SlideOver'
import { t } from '../../lib/i18n'

interface Sender {
  id: number
  full_name: string
  email: string
  job_title: string | null
  has_profile_photo: boolean
  profile_photo_url: string | null
}

interface SenderAssignmentModalProps {
  open: boolean
  onClose: () => void
  senders: Sender[]
  selectedMailboxIds: number[]
  onAssign: (senderId: number) => void
  isBulk?: boolean
}

export function SenderAssignmentModal({
  open,
  onClose,
  senders,
  selectedMailboxIds,
  onAssign,
  isBulk = false,
}: SenderAssignmentModalProps) {
  const [searchQuery, setSearchQuery] = useState('')
  const [selectedSenderId, setSelectedSenderId] = useState<number | null>(null)
  const [isSubmitting, setIsSubmitting] = useState(false)

  const filteredSenders = useMemo(() => {
    if (!searchQuery.trim()) return senders
    const query = searchQuery.toLowerCase()
    return senders.filter(
      sender =>
        sender.full_name.toLowerCase().includes(query) ||
        sender.email.toLowerCase().includes(query) ||
        (sender.job_title && sender.job_title.toLowerCase().includes(query))
    )
  }, [senders, searchQuery])

  const handleAssign = () => {
    if (!selectedSenderId) return
    setIsSubmitting(true)
    onAssign(selectedSenderId)
  }

  const handleClose = () => {
    setSearchQuery('')
    setSelectedSenderId(null)
    setIsSubmitting(false)
    onClose()
  }

  const title = isBulk
    ? t('admin.email_domains.bulk_assign_title', { count: selectedMailboxIds.length })
    : t('admin.email_domains.assign_sender')

  return (
    <SlideOver
      open={open}
      onClose={handleClose}
      title={title}
      width="md"
      footer={
        <SlideOverFooterButtons
          primaryLabel={t('admin.email_domains.assign_sender')}
          onPrimary={handleAssign}
          primaryDisabled={!selectedSenderId}
          primaryLoading={isSubmitting}
          secondaryLabel={t('admin.common.cancel')}
          onSecondary={handleClose}
        />
      }
    >
      <div className="p-6 space-y-4">
        <div className="relative">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-[var(--foreground-muted)]" />
          <input
            type="text"
            value={searchQuery}
            onChange={e => setSearchQuery(e.target.value)}
            placeholder={t('admin.senders.filters.search')}
            className="w-full pl-10 pr-4 py-2 rounded-lg border border-[var(--border)] bg-transparent text-[var(--foreground)] placeholder-[var(--foreground-muted)] focus:outline-none focus:ring-2 focus:ring-[var(--accent)] focus:border-transparent"
          />
          {searchQuery && (
            <button
              onClick={() => setSearchQuery('')}
              className="absolute right-3 top-1/2 -translate-y-1/2 p-1 hover:bg-[var(--card-hover)] rounded"
            >
              <X className="h-4 w-4 text-[var(--foreground-muted)]" />
            </button>
          )}
        </div>

        {isBulk && (
          <div className="text-sm text-[var(--foreground-muted)] bg-[var(--card-hover)] rounded-lg px-4 py-3">
            {t('admin.email_domains.bulk_assign_description', { count: selectedMailboxIds.length })}
          </div>
        )}

        <div className="space-y-2 max-h-[400px] overflow-y-auto">
          {filteredSenders.length === 0 ? (
            <div className="text-center py-8 text-[var(--foreground-muted)]">
              <UserPlus className="h-8 w-8 mx-auto mb-2" />
              <p>{t('admin.senders.empty')}</p>
            </div>
          ) : (
            filteredSenders.map(sender => (
              <button
                key={sender.id}
                onClick={() => setSelectedSenderId(sender.id)}
                className={`
                  w-full flex items-center gap-3 p-3 rounded-lg border transition-colors
                  ${selectedSenderId === sender.id
                    ? 'border-[var(--accent)] bg-[var(--accent)]/10'
                    : 'border-[var(--border)] hover:border-[var(--foreground-subtle)] hover:bg-[var(--card-hover)]'
                  }
                `}
              >
                <div className="relative shrink-0">
                  {sender.profile_photo_url ? (
                    <img
                      src={sender.profile_photo_url}
                      alt={sender.full_name}
                      className="w-10 h-10 rounded-full object-cover"
                    />
                  ) : (
                    <div className="w-10 h-10 rounded-full bg-gradient-to-br from-[var(--accent)] to-purple-600 flex items-center justify-center text-white font-bold">
                      {sender.full_name.charAt(0)}
                    </div>
                  )}
                </div>
                <div className="flex-1 text-left">
                  <div className="font-medium text-[var(--foreground)]">
                    {sender.full_name}
                  </div>
                  <div className="text-sm text-[var(--foreground-muted)]">
                    {sender.email}
                    {sender.job_title && ` • ${sender.job_title}`}
                  </div>
                </div>
                {selectedSenderId === sender.id && (
                  <div className="w-5 h-5 rounded-full bg-[var(--accent)] flex items-center justify-center">
                    <svg className="w-3 h-3 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={3} d="M5 13l4 4L19 7" />
                    </svg>
                  </div>
                )}
              </button>
            ))
          )}
        </div>
      </div>
    </SlideOver>
  )
}

export default SenderAssignmentModal
