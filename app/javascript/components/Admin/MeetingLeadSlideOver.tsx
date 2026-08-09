import { Badge, BadgeProps } from '../ui/Badge'
import { Button } from '../ui/Button'
import LeadSidebar from '../LeadSidebar'
import { LeadDetailData } from '../LeadDetailContent'
import { SlideOver } from '../ui/SlideOver'
import { t } from '../../lib/i18n'
import { Clock, MapPin } from 'lucide-react'

interface ModalGeneratedMessage {
  id: number
  subject: string
  body: string
  status: string
  sent_at: string | null
  created_at: string
  sequence_step: {
    id: number
    position: number
    display_name: string
  } | null
}

interface ModalThreadMessage {
  id: number
  type: 'incoming' | 'outgoing'
  source: 'reply' | 'sent_reply'
  from: string
  subject: string | null
  body_plain: string | null
  body_html: string | null
  message_at: string | null
  is_bounce: boolean
  is_out_of_office: boolean
}

interface ModalConversation {
  id: number
  status: string
  mailbox: {
    id: number
    email: string
  }
  thread: ModalThreadMessage[]
}

interface ModalAgentLead {
  id: number
  status: string
  delivery_status: string
  sequence_position: number | null
  assigned_mailbox: {
    id: number
    email: string
  } | null
  generated_messages: ModalGeneratedMessage[]
  conversation: ModalConversation | null
}

export interface AdminMeetingLeadModalData {
  lead: LeadDetailData
  mailbox: {
    id: number
    email: string
    display_name: string | null
  } | null
  sender: {
    id: number
    full_name: string
    email: string
    job_title: string | null
    has_signature: boolean
  } | null
  agent_lead: ModalAgentLead
}

interface MeetingRow {
  id: number
  meeting_type: string | null
  scheduled_at: string | null
  duration_minutes: number | null
  location: string | null
  status: string
  removal_comment: string | null
  agent: {
    id: number
    name: string
    organization_id: number | null
  }
}

interface MeetingLeadSlideOverProps {
  open: boolean
  onClose: () => void
  meeting: MeetingRow | null
  loading: boolean
  error: string | null
  data: AdminMeetingLeadModalData | null
  deletingMeeting?: boolean
  decliningMeeting?: boolean
  onDeleteMeeting?: () => void
  onDeclineWithComment?: () => void
}

interface TimelineEntry {
  key: string
  timestamp: Date
  subject: string
  body: string
  from: string
  label: string
  tone: 'generated' | 'incoming' | 'outgoing'
}

const getMeetingStatusBadge = (status: string): { variant: BadgeProps['variant']; label: string } => {
  switch (status) {
    case 'scheduled':
      return { variant: 'info', label: t('admin.meetings.statuses.scheduled') }
    case 'scheduling':
      return { variant: 'info', label: t('admin.meetings.statuses.scheduling') }
    case 'completed':
      return { variant: 'success', label: t('admin.meetings.statuses.completed') }
    case 'no_show':
      return { variant: 'warning', label: t('admin.meetings.statuses.no_show') }
    case 'cancelled':
      return { variant: 'error', label: t('admin.meetings.statuses.cancelled') }
    case 'rescheduled':
      return { variant: 'default', label: t('admin.meetings.statuses.rescheduled') }
    case 'pending_removal':
      return { variant: 'warning', label: t('admin.meetings.statuses.pending_removal') }
    default:
      return { variant: 'default', label: status }
  }
}

const getDeliveryStatusBadge = (status: string): BadgeProps['variant'] => {
  switch (status) {
    case 'not_contacted':
      return 'default'
    case 'in_sequence':
      return 'info'
    case 'paused':
      return 'warning'
    case 'replied':
      return 'approved'
    case 'bounced':
      return 'bounced'
    case 'completed':
      return 'success'
    default:
      return 'default'
  }
}

const fallbackMailbox = {
  id: 0,
  email: '-',
  display_name: null
}

const buildTimeline = (data: AdminMeetingLeadModalData | null): TimelineEntry[] => {
  if (!data) return []

  const htmlToPlainText = (html: string | null): string => {
    if (!html) return ''

    if (typeof window === 'undefined') {
      return html.replace(/<[^>]*>/g, ' ').replace(/\s+/g, ' ').trim()
    }

    const doc = new DOMParser().parseFromString(html, 'text/html')
    return doc.body.textContent?.replace(/\s+/g, ' ').trim() || ''
  }

  const generatedEntries = data.agent_lead.generated_messages.map((message) => ({
    key: `generated_message:${message.id}`,
    timestamp: new Date(message.sent_at || message.created_at),
    subject: message.subject || '(no subject)',
    body: message.body,
    from: message.sequence_step ? `Sequence step ${message.sequence_step.position}` : 'Generated message',
    label: ['approved', 'draft'].includes(message.status) ? `sample message (${message.status})` : `Generated (${message.status})`,
    tone: 'generated' as const
  }))

  const conversationEntries = (data.agent_lead.conversation?.thread || []).map((message) => ({
    key: `${message.source}:${message.id}`,
    timestamp: new Date(message.message_at || 0),
    subject: message.subject || '(no subject)',
    body: message.body_plain?.trim() || htmlToPlainText(message.body_html),
    from: message.from,
    label: message.is_bounce
      ? 'Bounce'
      : message.is_out_of_office
        ? 'Out of office'
        : message.type === 'incoming'
          ? 'Incoming reply'
          : 'Sent reply',
    tone: message.type === 'incoming' ? 'incoming' as const : 'outgoing' as const
  }))

  return [...generatedEntries, ...conversationEntries].sort((left, right) => left.timestamp.getTime() - right.timestamp.getTime())
}

const formatDateTime = (value: string | null) => {
  if (!value) return '-'

  return new Date(value).toLocaleDateString('en-US', {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit'
  })
}

export default function MeetingLeadSlideOver({
  open,
  onClose,
  meeting,
  loading,
  error,
  data,
  deletingMeeting = false,
  decliningMeeting = false,
  onDeleteMeeting,
  onDeclineWithComment
}: MeetingLeadSlideOverProps) {
  const timeline = buildTimeline(data)
  const statusBadge = meeting ? getMeetingStatusBadge(meeting.status) : null
  const meetingTypeLabel = meeting?.meeting_type
    ? t(`admin.meetings.types.${meeting.meeting_type}`)
    : '-'

  return (
    <SlideOver
      open={open}
      onClose={onClose}
      width={1080}
      className="bg-[var(--background)]"
    >
      {loading ? (
        <div className="flex h-full items-center justify-center text-[var(--foreground-muted)]">
          {t('common.loading')}
        </div>
      ) : error ? (
        <div className="flex h-full items-center justify-center p-8 text-center text-sm text-[var(--foreground-muted)]">
          {error}
        </div>
      ) : meeting && data ? (
        <div className="grid h-full min-h-0 grid-cols-5">
          <aside className="col-span-2 min-h-0 overflow-y-auto border-r border-[var(--border)] bg-[var(--card)] custom-scrollbar">
            <div className="p-5">
              <LeadSidebar lead={data.lead} mailbox={data.mailbox || fallbackMailbox} sender={data.sender} />
            </div>
          </aside>

          <section className="col-span-3 min-h-0 overflow-y-auto p-5 custom-scrollbar">
            <div className="mb-5 rounded-lg border border-[var(--border)] bg-[var(--card)] p-4">
              <div className="flex flex-wrap items-center gap-2">
                <h3 className="mr-2 text-base font-semibold text-[var(--foreground)]">{data.lead.display_name}</h3>
                {statusBadge && <Badge variant={statusBadge.variant}>{statusBadge.label}</Badge>}
                <Badge variant="default">{meetingTypeLabel}</Badge>
                <Badge variant={getDeliveryStatusBadge(data.agent_lead.delivery_status)}>
                  {data.agent_lead.delivery_status}
                </Badge>
              </div>

              <div className="mt-4 grid gap-3 text-sm text-[var(--foreground-muted)] md:grid-cols-2">
                <div className="flex items-start gap-2">
                  <Clock className="mt-0.5 h-4 w-4" />
                  <span>Scheduled for {formatDateTime(meeting.scheduled_at)}</span>
                </div>
                <div className="flex items-start gap-2">
                  <Clock className="mt-0.5 h-4 w-4" />
                  <span>Duration {meeting.duration_minutes ? `${meeting.duration_minutes} min` : '-'}</span>
                </div>
                <div className="flex items-start gap-2 md:col-span-2">
                  <MapPin className="mt-0.5 h-4 w-4" />
                  <span>{meeting.location || 'No location provided'}</span>
                </div>
              </div>

              {meeting.removal_comment && (
                <div className="mt-4 rounded-xl border border-amber-500/25 bg-amber-500/10 p-3">
                  <div className="text-[11px] font-semibold uppercase tracking-wide text-amber-300">
                    {t('admin.meetings.show.removal_comment', { defaultValue: 'Removal request comment' })}
                  </div>
                  <p className="mt-2 whitespace-pre-wrap text-sm text-[var(--foreground)]">
                    {meeting.removal_comment}
                  </p>
                </div>
              )}

              {meeting.status === 'pending_removal' && (
                <div className="mt-4 flex flex-wrap gap-2">
                  <Button
                    type="button"
                    size="sm"
                    variant="destructive"
                    loading={deletingMeeting}
                    onClick={onDeleteMeeting}
                  >
                    Delete Meeting
                  </Button>
                  <Button
                    type="button"
                    size="sm"
                    variant="secondary"
                    loading={decliningMeeting}
                    onClick={onDeclineWithComment}
                  >
                    Decline with Comment
                  </Button>
                </div>
              )}
            </div>

            <h3 className="mb-3 text-sm font-semibold uppercase tracking-wide text-[var(--foreground-muted)]">Conversation history</h3>

            {timeline.length === 0 ? (
              <div className="rounded-lg border border-dashed border-[var(--border)] px-4 py-8 text-center text-sm text-[var(--foreground-muted)]">
                No conversation history yet.
              </div>
            ) : (
              <div className="space-y-3">
                {timeline.map((entry) => (
                  <article key={entry.key} className="rounded-lg border border-[var(--border)] bg-[var(--card)] p-4">
                    <div className="mb-2 flex flex-wrap items-center gap-2 text-xs">
                      <Badge
                        size="sm"
                        variant={entry.tone === 'incoming' ? 'success' : entry.tone === 'generated' ? 'info' : 'default'}
                      >
                        {entry.label}
                      </Badge>
                      <span className="text-[var(--foreground-muted)]">{formatDateTime(entry.timestamp.toISOString())}</span>
                    </div>
                    <p className="text-sm font-semibold text-[var(--foreground)]">{entry.subject}</p>
                    <p className="mt-1 text-xs text-[var(--foreground-muted)]">{entry.from}</p>
                    <p className="mt-2 whitespace-pre-wrap text-sm text-[var(--foreground)]">{entry.body || '(empty body)'}</p>
                  </article>
                ))}
              </div>
            )}
          </section>
        </div>
      ) : null}
    </SlideOver>
  )
}
