import { Link } from '@inertiajs/react'
import { t } from '../lib/i18n'
import { Badge } from './ui/Badge'

interface Conversation {
  id: number
  status: 'open' | 'snoozed' | 'closed'
  interest_status: 'interested' | 'meeting_request' | 'not_interested' | 'wrong_person' | null
  is_unread: boolean
  last_reply_at: string | null
  last_reply_preview: string | null
  awaiting_reply: boolean
  has_bounce: boolean
  has_out_of_office: boolean
  ooo_return_date: string | null
  lead: {
    email: string
    first_name: string | null
    last_name: string | null
    company: string | null
    linkedin_profile_photo_url: string | null
  }
}

const getInterestStatusConfig = (interestStatus: Conversation['interest_status']) => {
  if (!interestStatus) return null

  switch (interestStatus) {
    case 'interested':
      return {
        label: t('admin.organizations.replies.interest_status.interested', { defaultValue: 'Interested' }),
        dotClassName: 'bg-sky-400',
        textClassName: 'text-sky-400',
      }
    case 'meeting_request':
      return {
        label: t('admin.organizations.replies.interest_status.meeting_request', { defaultValue: 'Meeting Request' }),
        dotClassName: 'bg-[var(--success)]',
        textClassName: 'text-[var(--success)]',
      }
    case 'not_interested':
      return {
        label: t('admin.organizations.replies.interest_status.not_interested', { defaultValue: 'Not Interested' }),
        dotClassName: 'bg-[var(--error)]',
        textClassName: 'text-[var(--error)]',
      }
    case 'wrong_person':
      return {
        label: t('admin.organizations.replies.interest_status.wrong_person', { defaultValue: 'Wrong Person' }),
        dotClassName: 'bg-blue-400',
        textClassName: 'text-blue-400',
      }
  }
}

interface ConversationCardProps {
  conversation: Conversation
  organizationId: number
  organizationName?: string
  onClick?: () => void
  isSelected?: boolean
}

const formatTimeAgo = (dateString: string | null) => {
  if (!dateString) return t('admin.organizations.replies.no_time', { defaultValue: '—' })

  const date = new Date(dateString)
  const now = new Date()
  const diffInSeconds = Math.floor((now.getTime() - date.getTime()) / 1000)
  
  if (diffInSeconds < 60) return t('time.just_now')
  if (diffInSeconds < 3600) return `${Math.floor(diffInSeconds / 60)}m`
  if (diffInSeconds < 86400) return `${Math.floor(diffInSeconds / 3600)}h`
  if (diffInSeconds < 604800) return `${Math.floor(diffInSeconds / 86400)}d`
  return date.toLocaleDateString()
}

export default function ConversationCard({ conversation, organizationId, organizationName, onClick, isSelected }: ConversationCardProps) {
  const leadName = [conversation.lead.first_name, conversation.lead.last_name].filter(Boolean).join(' ') || conversation.lead.email
  const statusBadge = conversation.has_bounce
    ? 'bounced'
    : conversation.has_out_of_office
      ? 'ooo'
    : conversation.awaiting_reply
        ? 'reply-now'
        : null

  const interestStatusConfig = getInterestStatusConfig(conversation.interest_status)

  const Content = (
    <div className={`
      relative border-l-2 px-4 py-4 transition-all duration-200
      ${isSelected
        ? 'border-l-[var(--accent)] bg-white/[0.05]'
        : 'border-l-transparent hover:bg-white/[0.03]'
      }
    `}>
      <div className="flex flex-col gap-1">
        <div className="flex items-center gap-3 w-full">
          <div className={`h-2 w-2 shrink-0 rounded-full ${conversation.is_unread ? 'bg-[var(--accent)] shadow-[0_0_0_4px_rgba(53,202,222,0.14)]' : 'bg-transparent'}`} />
          
          <div className="relative shrink-0">
            {conversation.lead.linkedin_profile_photo_url ? (
              <img 
                src={conversation.lead.linkedin_profile_photo_url} 
                alt={leadName}
                className="h-9 w-9 rounded-full object-cover shrink-0"
                onError={(e) => {
                  e.currentTarget.style.display = 'none'
                  e.currentTarget.nextElementSibling?.classList.remove('hidden')
                }}
              />
            ) : null}
              <div className={`flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-[linear-gradient(135deg,#35cade,#69e0ee)] text-sm font-bold text-[#081419] ${conversation.lead.linkedin_profile_photo_url ? 'hidden' : ''}`}>
              {leadName.charAt(0)}
            </div>
          </div>

          <div className="flex-1 min-w-0">
            <div className="flex justify-between items-center">
                <span className={`truncate text-sm font-semibold ${conversation.is_unread ? 'text-[var(--foreground)]' : 'text-[var(--foreground-muted)]'}`}>
                {leadName}
              </span>
              <div className="flex items-center gap-2 shrink-0">
                {statusBadge === 'bounced' && (
                  <Badge variant="bounced" size="sm" className="text-[10px] uppercase tracking-wider">
                    {t('admin.organizations.replies.bounced')}
                  </Badge>
                )}
                {statusBadge === 'ooo' && (
                  <Badge variant="warning" size="sm" className="text-[10px] uppercase tracking-wider">
                    {t('admin.organizations.replies.ooo')}
                    {conversation.ooo_return_date && (
                      <span className="ml-1 normal-case">
                        ({t('admin.organizations.replies.ooo_returns', { date: new Date(conversation.ooo_return_date + 'T00:00:00').toLocaleDateString('en-US', { month: 'short', day: 'numeric' }) })})
                      </span>
                    )}
                  </Badge>
                )}
                {statusBadge === 'reply-now' && (
                  <span className="inline-flex items-center rounded-md border border-amber-400/40 bg-amber-400/15 px-1 py-0 text-[9px] font-semibold tracking-normal text-amber-500">
                    {t('admin.organizations.replies.reply_now')}
                  </span>
                )}
                <span className="text-xs text-[var(--foreground-subtle)] whitespace-nowrap">
                  {formatTimeAgo(conversation.last_reply_at)}
                </span>
              </div>
            </div>
            {(conversation.lead.company || interestStatusConfig || organizationName) && (
              <div className="flex items-center gap-2 text-xs text-[var(--foreground-subtle)] min-w-0">
                {organizationName && (
                  <span className="inline-flex shrink-0 items-center gap-1 rounded-full border border-[var(--accent)]/15 bg-[var(--accent)]/10 px-2 py-1 text-[10px] font-semibold text-[var(--accent)]">
                    {organizationName}
                  </span>
                )}
                {conversation.lead.company && (
                  <span className="truncate flex-1">{conversation.lead.company}</span>
                )}
                {interestStatusConfig && (
                  <span className={`inline-flex shrink-0 items-center gap-1 text-[11px] font-semibold ${interestStatusConfig.textClassName}`}>
                    <span className={`h-1.5 w-1.5 rounded-full ${interestStatusConfig.dotClassName}`} />
                    {interestStatusConfig.label}
                  </span>
                )}
              </div>
            )}
          </div>
        </div>

        <div className="ml-5 mt-1 line-clamp-2 text-[13px] leading-5 text-[var(--foreground-subtle)]">
          {conversation.last_reply_preview || t('admin.organizations.replies.no_preview')}
        </div>
      </div>
    </div>
  )

  if (onClick) {
    return (
      <button 
        type="button"
        onClick={onClick}
        className="block w-full text-left focus:outline-none focus:ring-2 focus:ring-[var(--accent)] focus:ring-inset"
      >
        {Content}
      </button>
    )
  }

  return (
    <Link 
      href={`/admin/organizations/${organizationId}/replies/${conversation.id}`}
      className="block group focus:outline-none focus:ring-2 focus:ring-[var(--accent)] focus:ring-inset"
    >
      {Content}
    </Link>
  )
}
