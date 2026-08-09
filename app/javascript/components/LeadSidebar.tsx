import { 
  Mail as MailIcon
} from 'lucide-react'
import { Card, CardContent } from './ui/Card'
import { t } from '../lib/i18n'
import LeadDetailContent, { LeadDetailData } from './LeadDetailContent'

interface Mailbox {
  id: number
  email: string
  display_name: string | null
}

interface Sender {
  id: number
  full_name: string
  email: string
  job_title: string | null
  has_signature: boolean
}

interface LeadSidebarProps {
  lead: LeadDetailData
  mailbox: Mailbox
  sender: Sender | null
  hideIncompleteBuyingSignals?: boolean
}

export default function LeadSidebar({ lead, mailbox, sender, hideIncompleteBuyingSignals = false }: LeadSidebarProps) {
  const fullName = lead.display_name || [lead.first_name, lead.last_name].filter(Boolean).join(' ') || lead.email

  return (
    <div className="space-y-4">
      <Card className="overflow-hidden">
        <CardContent className="pt-5 pb-4">
          <div className="flex items-center gap-3">
            <div className="relative">
              {lead.linkedin_profile_photo_url ? (
                <img 
                  src={lead.linkedin_profile_photo_url} 
                  alt={fullName}
                  className="w-12 h-12 rounded-full border border-[var(--border)] object-cover"
                  onError={(e) => {
                    e.currentTarget.style.display = 'none'
                    e.currentTarget.nextElementSibling?.classList.remove('hidden')
                  }}
                />
              ) : null}
              <div className={`flex h-12 w-12 items-center justify-center rounded-full border border-[var(--border)] bg-[linear-gradient(135deg,#35cade,#69e0ee)] text-lg font-bold text-[#081419] ${lead.linkedin_profile_photo_url ? 'hidden' : ''}`}>
                {fullName.charAt(0)}
              </div>
            </div>
            <div className="min-w-0">
              <h3 className="text-lg font-semibold text-[var(--foreground)] truncate">{fullName}</h3>
              {lead.company && (
                <p className="text-sm text-[var(--foreground-muted)] truncate">{lead.company}</p>
              )}
              {lead.job_title && (
                <p className="text-sm text-[var(--foreground-subtle)] truncate">{lead.job_title}</p>
              )}
            </div>
          </div>
        </CardContent>
      </Card>

      <div className="rounded-[24px] border border-[var(--border)] bg-[var(--card)] p-4 shadow-[var(--shadow-sm)]">
        <LeadDetailContent data={lead} variant="slideover" showMessages={false} hideIncompleteBuyingSignals={hideIncompleteBuyingSignals} />
      </div>

      <div className="grid gap-3">
        {sender && (
           <div className="rounded-[20px] border border-[var(--border)] bg-[var(--card)] p-3 shadow-[var(--shadow-sm)]">
            <h4 className="text-xs font-semibold uppercase tracking-wider text-[var(--foreground-muted)] mb-2">
              {t('admin.organizations.replies.sidebar.sending_as')}
            </h4>
            <div className="flex items-center gap-2.5">
              <div className="flex h-7 w-7 items-center justify-center rounded-full bg-[var(--accent)]/12 text-[var(--accent)] font-bold text-xs">
                {sender.full_name.charAt(0)}
              </div>
              <div>
                <div className="text-sm font-medium text-[var(--foreground)]">{sender.full_name}</div>
                <div className="text-xs text-[var(--foreground-muted)]">{sender.email}</div>
              </div>
            </div>
          </div>
        )}

         <div className="rounded-[20px] border border-[var(--border)] bg-[var(--card)] p-3 shadow-[var(--shadow-sm)]">
          <h4 className="text-xs font-semibold uppercase tracking-wider text-[var(--foreground-muted)] mb-2">
            {t('admin.organizations.replies.sidebar.mailbox')}
          </h4>
          <div className="flex items-center gap-2 text-sm">
            <MailIcon className="w-4 h-4 text-[var(--foreground-muted)]" />
            <span className="text-[var(--foreground)]">{mailbox.email}</span>
          </div>
          {mailbox.display_name && (
            <div className="text-xs text-[var(--foreground-muted)] ml-6 mt-1">
              {mailbox.display_name}
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
