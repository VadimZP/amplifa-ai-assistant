import { useRef, useEffect } from 'react'
import { Link, router } from '@inertiajs/react'
import { 
  ArrowLeft, 
  CheckCircle, 
  Clock, 
  RotateCcw,
  User
} from 'lucide-react'
import OrganizationTabLayout from '../../../../components/Admin/OrganizationTabLayout'
import ThreadMessage from '../../../../components/ThreadMessage'
import LeadSidebar from '../../../../components/LeadSidebar'
import { Button } from '../../../../components/ui/Button'
import { Badge } from '../../../../components/ui/Badge'
import { t } from '../../../../lib/i18n'

interface Props {
  auth: { account: any }
  organization: { id: number; name: string }
  conversation: any
  thread: Message[]
  lead: any
  mailbox: any
  sender: any
  current_tab: string
  flash?: { notice?: string; alert?: string }
}

interface Message {
  id: number
  type: 'incoming' | 'outgoing'
  source: 'generated_message' | 'reply' | 'sent_reply'
  from: string
  subject: string | null
  to_addresses?: string[] | null
  cc_addresses?: string[] | null
  body_plain: string | null
  body_html: string | null
  message_at: string
  is_bounce: boolean
  is_out_of_office: boolean
}

export default function Show({ 
  auth, 
  organization, 
  conversation, 
  thread, 
  lead, 
  mailbox, 
  sender,
  current_tab, 
  flash 
}: Props) {
  const messagesEndRef = useRef<HTMLDivElement>(null)

  const scrollToBottom = () => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' })
  }

  useEffect(() => {
    scrollToBottom()
  }, [thread])

  const handleClose = () => {
    router.post(`/admin/organizations/${organization.id}/replies/${conversation.id}/close`)
  }

  const handleReopen = () => {
    router.post(`/admin/organizations/${organization.id}/replies/${conversation.id}/reopen`)
  }

  const handleSnooze = (option: 'tomorrow' | 'next_week' | 'next_month') => {
    router.post(`/admin/organizations/${organization.id}/replies/${conversation.id}/snooze`, { 
      snooze_option: option 
    })
  }

  const leadName = [lead.first_name, lead.last_name].filter(Boolean).join(' ') || lead.email

  return (
    <OrganizationTabLayout
      organization={organization}
      currentTab={current_tab}
      account={auth.account}
      flash={flash}
    >
      <div className="flex flex-col lg:flex-row gap-6 h-[calc(100vh-14rem)]">
        {/* Left Column: Thread */}
        <div className="flex-1 flex flex-col min-h-0 bg-[var(--background)] rounded-xl border border-[var(--border)] overflow-hidden">
          {/* Thread Header */}
          <div className="shrink-0 p-4 border-b border-[var(--border)] flex items-center justify-between bg-[var(--card)]">
            <div className="flex items-center gap-4">
              <Link 
                href={`/admin/organizations/${organization.id}/replies`}
                className="p-2 hover:bg-[var(--card-hover)] rounded-full transition-colors text-[var(--foreground-muted)]"
              >
                <ArrowLeft className="w-5 h-5" />
              </Link>
              
              <div className="flex items-center gap-3">
                {lead.linkedin_profile_photo_url ? (
                  <img 
                    src={lead.linkedin_profile_photo_url} 
                    alt={leadName}
                    className="w-10 h-10 rounded-full object-cover"
                    onError={(e) => {
                      e.currentTarget.style.display = 'none'
                      e.currentTarget.nextElementSibling?.classList.remove('hidden')
                    }}
                  />
                ) : null}
                <div className={`w-10 h-10 rounded-full bg-[var(--card-hover)] flex items-center justify-center text-[var(--foreground-muted)] ${lead.linkedin_profile_photo_url ? 'hidden' : ''}`}>
                  <User className="w-5 h-5" />
                </div>
                <div>
                  <div className="flex items-center gap-3">
                    <h2 className="text-lg font-semibold text-[var(--foreground)]">{leadName}</h2>
                    <Badge variant={
                      conversation.status === 'open' ? 'warning' :
                      conversation.status === 'closed' ? 'success' : 'default'
                    }>
                      {t(`admin.organizations.replies.status.${conversation.status}`)}
                    </Badge>
                  </div>
                  {lead.company && (
                    <div className="flex items-center gap-2 text-sm text-[var(--foreground-muted)]">
                      <span className="truncate">{lead.company}</span>
                    </div>
                  )}
                </div>
              </div>
            </div>

            <div className="flex items-center gap-2">
              {conversation.status !== 'closed' && (
                <Button 
                  variant="secondary" 
                  size="sm" 
                  icon={<CheckCircle className="w-4 h-4" />}
                  onClick={handleClose}
                >
                  {t('admin.organizations.replies.actions.close')}
                </Button>
              )}
              
              {conversation.status === 'closed' && (
                <Button 
                  variant="secondary" 
                  size="sm" 
                  icon={<RotateCcw className="w-4 h-4" />}
                  onClick={handleReopen}
                >
                  {t('admin.organizations.replies.actions.reopen')}
                </Button>
              )}

              {conversation.status !== 'closed' && (
                <div className="relative group">
                  <Button variant="ghost" size="sm" icon={<Clock className="w-4 h-4" />}>
                    {t('admin.organizations.replies.actions.snooze')}
                  </Button>
                  
                  <div className="absolute right-0 top-full mt-1 w-48 bg-[var(--card)] border border-[var(--border)] rounded-lg shadow-lg py-1 hidden group-hover:block z-50">
                    <button 
                      onClick={() => handleSnooze('tomorrow')}
                      className="w-full text-left px-4 py-2 text-sm hover:bg-[var(--card-hover)] text-[var(--foreground)]"
                    >
                      {t('admin.organizations.replies.snooze.tomorrow')}
                    </button>
                    <button 
                      onClick={() => handleSnooze('next_week')}
                      className="w-full text-left px-4 py-2 text-sm hover:bg-[var(--card-hover)] text-[var(--foreground)]"
                    >
                      {t('admin.organizations.replies.snooze.next_week')}
                    </button>
                    <button 
                      onClick={() => handleSnooze('next_month')}
                      className="w-full text-left px-4 py-2 text-sm hover:bg-[var(--card-hover)] text-[var(--foreground)]"
                    >
                      {t('admin.organizations.replies.snooze.next_month')}
                    </button>
                  </div>
                </div>
              )}
            </div>
          </div>

          {/* Messages Area */}
          <div className="flex-1 overflow-y-auto p-6 scroll-smooth">
            {thread.map((message, index) => (
              <ThreadMessage 
                key={`${message.source}-${message.id}`} 
                message={message} 
                previousMessage={index > 0 ? thread[index - 1] : undefined} 
              />
            ))}
            <div ref={messagesEndRef} />
          </div>
        </div>

        {/* Right Column: Sidebar */}
        <div className="w-full lg:w-96 shrink-0 overflow-y-auto custom-scrollbar pr-2">
          <LeadSidebar 
            lead={lead} 
            mailbox={mailbox} 
            sender={sender} 
            hideIncompleteBuyingSignals
          />
        </div>
      </div>
    </OrganizationTabLayout>
  )
}
