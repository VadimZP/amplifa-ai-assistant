import { AlertCircle, Calendar, Download, FileText, MapPin, Plane, User } from 'lucide-react'
import { Badge } from './ui/Badge'
import { t } from '../lib/i18n'
import IsolatedHtmlContent from './IsolatedHtmlContent'
import { isCalendarInviteAttachment, isImageThreadAttachment, shouldShowThreadAttachment } from './threadMessageAttachmentVisibility'

interface MessageAttachment {
  id: number
  filename: string
  content_type: string
  file_size_bytes: number
  download_url: string
  view_url?: string | null
  inline?: boolean
  calendar_links?: {
    google_url: string
    outlook_url: string
  } | null
}

interface CalendarEventDateTime {
  date_time?: string | null
  time_zone?: string | null
}

interface CalendarEventDateParts {
  year: number
  month: number
  day: number
  hour: number
  minute: number
  second: number
}

interface CalendarEvent {
  source?: string
  message_type?: string | null
  title?: string | null
  start_at?: CalendarEventDateTime | null
  end_at?: CalendarEventDateTime | null
  display_start_at?: string | null
  display_end_at?: string | null
  location?: string | null
  organizer_name?: string | null
  organizer_email?: string | null
  response_requested?: boolean
  allow_new_time_proposals?: boolean
  is_out_of_date?: boolean
  calendar_links?: {
    google_url: string
    outlook_url: string
  } | null
}

interface Message {
  id: number
  type: 'incoming' | 'outgoing'
  from: string
  subject: string | null
  to_addresses?: string[] | null
  cc_addresses?: string[] | null
  body_plain: string | null
  body_html: string | null
  message_at: string
  is_bounce: boolean
  is_out_of_office: boolean
  attachments?: MessageAttachment[]
  calendar_event?: CalendarEvent | null
}

interface ThreadMessageProps {
  message: Message
  previousMessage?: Message
}

export default function ThreadMessage({ message, previousMessage }: ThreadMessageProps) {
  const isIncoming = message.type === 'incoming'
  const showSubject = !previousMessage || message.subject !== previousMessage.subject
  const visibleToAddresses = message.to_addresses || []
  const visibleCcAddresses = message.cc_addresses || []
  const hasExtraRecipients = visibleToAddresses.length > 0 || visibleCcAddresses.length > 0
  const shouldShowHeader = (showSubject && Boolean(message.subject)) || hasExtraRecipients
  const hasHtmlBody = Boolean(message.body_html)
  const attachments = (message.attachments || []).filter((attachment) => !attachment.inline && shouldShowThreadAttachment(attachment))
  const calendarEvent = message.calendar_event
  const formattedCalendarEventRange = calendarEvent ? formatCalendarEventRange(calendarEvent) : null
  
  const formattedDate = new Intl.DateTimeFormat('en-US', {
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: 'numeric'
  }).format(new Date(message.message_at))

  const calendarEventCardClassName = `mt-4 rounded-xl border px-3 py-3 ${
    isIncoming
      ? 'border-zinc-300 bg-white text-zinc-900'
      : 'border-white/20 bg-white/10 text-white'
  }`

  const calendarEventMetaClassName = isIncoming ? 'text-zinc-600' : 'text-white/70'
  const calendarEventAccentClassName = isIncoming ? 'text-zinc-800' : 'text-white'
  const calendarLinkClassName = `font-medium underline-offset-2 hover:underline ${
    isIncoming ? 'text-zinc-700' : 'text-white/90'
  }`

  return (
    <div className={`mb-6 flex flex-col gap-2 ${isIncoming ? 'items-start' : 'items-end'} group`}>
      <div className={`flex max-w-[80%] items-center gap-2 text-xs text-[var(--foreground-subtle)] ${isIncoming ? 'flex-row' : 'flex-row-reverse'}`}>
        <span className="font-medium text-[var(--foreground-muted)]">{message.from}</span>
        <span>•</span>
        <span>{formattedDate}</span>
        
        {message.is_bounce && (
          <Badge variant="error" size="sm" className="ml-2">
            <AlertCircle className="w-3 h-3 mr-1" />
            {t('admin.organizations.replies.bounced')}
          </Badge>
        )}
        
        {message.is_out_of_office && (
          <Badge variant="warning" size="sm" className="ml-2">
            <Plane className="w-3 h-3 mr-1" />
            {t('admin.organizations.replies.ooo')}
          </Badge>
        )}
      </div>

      <div className={`
        relative max-w-[85%] rounded-[24px] border px-5 py-4 text-sm leading-relaxed shadow-[var(--shadow-sm)]
        ${isIncoming 
          ? 'bg-white border-white/30 rounded-tl-md text-[#101418]' 
          : 'bg-[linear-gradient(135deg,#2abed2,#35cade)] border-[rgba(53,202,222,0.45)] text-[#081419] rounded-tr-md selection:bg-white/20'
        }
      `}>
        {shouldShowHeader && (
          <div className={`mb-3 border-b pb-2 text-xs font-medium ${isIncoming ? 'border-zinc-200 text-zinc-500' : 'border-black/10 text-black/55'}`}>
            {message.subject && (showSubject || hasExtraRecipients) && (
              <div>{message.subject}</div>
            )}

            {hasExtraRecipients && (
              <div className="mt-1 space-y-1 font-normal text-[11px] leading-relaxed">
                {visibleToAddresses.length > 0 && (
                  <div>
                    <span className="font-medium">{t('admin.organizations.replies.to_label', { defaultValue: 'To' })}:</span>{' '}
                    <span>{visibleToAddresses.join(', ')}</span>
                  </div>
                )}

                {visibleCcAddresses.length > 0 && (
                  <div>
                    <span className="font-medium">{t('admin.organizations.replies.cc_label', { defaultValue: 'Cc' })}:</span>{' '}
                    <span>{visibleCcAddresses.join(', ')}</span>
                  </div>
                )}
              </div>
            )}
          </div>
        )}
        
        {hasHtmlBody ? (
          <IsolatedHtmlContent
            className={`max-w-none break-words ${isIncoming ? 'text-zinc-900' : 'text-[#081419]'}`}
            html={message.body_html || ''}
          />
        ) : (
          <div className={`max-w-none break-words whitespace-pre-wrap ${isIncoming ? 'text-zinc-900' : 'text-[#081419]'}`}>
            {message.body_plain || ''}
          </div>
        )}

        {calendarEvent && (
          <div className={calendarEventCardClassName}>
            <div className="flex items-start justify-between gap-3">
              <div className="flex min-w-0 items-start gap-2">
                <Calendar className="mt-0.5 h-4 w-4 shrink-0" />
                <div className="min-w-0">
                  <div className="truncate text-sm font-semibold">
                    {calendarEvent.title || message.subject || 'Calendar event'}
                  </div>
                  <div className={`mt-1 text-xs ${calendarEventMetaClassName}`}>
                    {calendarEventTypeLabel(calendarEvent.message_type)}
                  </div>
                </div>
              </div>

              {calendarEvent.is_out_of_date && (
                <Badge variant="warning" size="sm">
                  Updated
                </Badge>
              )}
            </div>

            <div className={`mt-3 space-y-2 text-xs ${calendarEventMetaClassName}`}>
              {formattedCalendarEventRange && (
                <div>
                  <span className={`font-medium ${calendarEventAccentClassName}`}>When:</span>{' '}
                  {formattedCalendarEventRange}
                </div>
              )}

              {calendarEvent.location && (
                <div className="flex items-start gap-2">
                  <MapPin className="mt-0.5 h-3.5 w-3.5 shrink-0" />
                  <span>{calendarEvent.location}</span>
                </div>
              )}

              {calendarEventOrganizer(calendarEvent, message.from) && (
                <div className="flex items-start gap-2">
                  <User className="mt-0.5 h-3.5 w-3.5 shrink-0" />
                  <span>{calendarEventOrganizer(calendarEvent, message.from)}</span>
                </div>
              )}

              {calendarEvent.calendar_links && (
                <div className={`flex flex-wrap items-center gap-x-3 gap-y-1 border-t pt-2 ${isIncoming ? 'border-zinc-200' : 'border-white/15'}`}>
                  <span>Add to calendar:</span>
                  <a
                    href={calendarEvent.calendar_links.google_url}
                    target="_blank"
                    rel="noreferrer"
                    className={calendarLinkClassName}
                  >
                    Google Calendar
                  </a>
                  <a
                    href={calendarEvent.calendar_links.outlook_url}
                    target="_blank"
                    rel="noreferrer"
                    className={calendarLinkClassName}
                  >
                    Outlook
                  </a>
                </div>
              )}
            </div>
          </div>
        )}

        {attachments.length > 0 && (
          <div className={`mt-4 space-y-2 border-t pt-3 ${isIncoming ? 'border-zinc-300' : 'border-white/20'}`}>
            {attachments.map((attachment) => {
              const isImage = isImageThreadAttachment(attachment)
              const Icon = isCalendarInviteAttachment(attachment) ? Calendar : FileText
              const hasCalendarLinks = Boolean(attachment.calendar_links)
              const attachmentCardClassName = isIncoming
                ? 'rounded-xl border border-zinc-300 bg-white px-3 py-2 text-zinc-900'
                : 'rounded-xl bg-[linear-gradient(135deg,rgba(255,255,255,0.78),rgba(42,190,210,0.36),rgba(255,255,255,0.82))] p-px shadow-[0_6px_18px_rgba(8,20,25,0.10)]'
              const attachmentInnerClassName = isIncoming
                ? ''
                : 'rounded-[calc(0.75rem-1px)] bg-white px-3 py-2 text-zinc-950'
              const attachmentLinkClassName = 'flex items-center justify-between gap-3 rounded-lg transition-colors hover:bg-zinc-50'
              const attachmentMetaClassName = isIncoming ? 'border-zinc-200 text-zinc-600' : 'border-zinc-200 text-zinc-600'
              const attachmentCalendarLinkClassName = 'font-medium text-zinc-800 underline-offset-2 hover:underline'
              return (
                <div key={attachment.id} className={attachmentCardClassName}>
                  <div className={attachmentInnerClassName}>
                    {isImage ? (
                      <a href={attachment.download_url} className="block rounded-lg transition-colors hover:bg-zinc-50">
                        <img
                          src={attachment.view_url || attachment.download_url}
                          alt={attachment.filename}
                          className="max-h-80 w-auto max-w-full rounded-lg border border-zinc-200 object-contain"
                        />
                      </a>
                    ) : (
                      <a href={attachment.download_url} className={attachmentLinkClassName}>
                        <span className="flex min-w-0 items-center gap-2">
                          <Icon className="h-4 w-4 shrink-0" />
                          <span className="truncate text-sm font-medium">{attachment.filename}</span>
                        </span>
                        <Download className="h-4 w-4 shrink-0" />
                      </a>
                    )}

                    {hasCalendarLinks && attachment.calendar_links && (
                      <div className={`mt-2 flex flex-wrap items-center gap-x-3 gap-y-1 border-t pt-2 text-xs ${attachmentMetaClassName}`}>
                        <span>Add to calendar:</span>
                        <a
                          href={attachment.calendar_links.google_url}
                          target="_blank"
                          rel="noreferrer"
                          className={attachmentCalendarLinkClassName}
                        >
                          Google Calendar
                        </a>
                        <a
                          href={attachment.calendar_links.outlook_url}
                          target="_blank"
                          rel="noreferrer"
                          className={attachmentCalendarLinkClassName}
                        >
                          Outlook
                        </a>
                      </div>
                    )}
                  </div>
                </div>
              )
            })}
          </div>
        )}
      </div>
    </div>
  )
}

function calendarEventTypeLabel(messageType?: string | null) {
  switch (messageType) {
  case 'meetingRequest':
    return 'Meeting request'
  case 'meetingCancelled':
    return 'Meeting cancelled'
  case 'meetingAccepted':
    return 'Meeting accepted'
  case 'meetingTentativelyAccepted':
    return 'Tentatively accepted'
  case 'meetingDeclined':
    return 'Meeting declined'
  default:
    return 'Calendar event'
  }
}

function calendarEventOrganizer(calendarEvent: CalendarEvent, fallbackFrom: string) {
  const organizer = calendarEvent.organizer_name || calendarEvent.organizer_email || fallbackFrom
  return organizer || null
}

function formatCalendarEventRange(calendarEvent: CalendarEvent) {
  const localTimeRange = formatCalendarEventRangeInLocalTime(calendarEvent)
  if (localTimeRange) return localTimeRange

  const startParts = parseCalendarEventDateParts(calendarEvent.start_at?.date_time)
  const endParts = parseCalendarEventDateParts(calendarEvent.end_at?.date_time)
  const start = formatCalendarEventDateTime(startParts)
  const includeEndDate = !startParts || !endParts || !sameCalendarEventDay(startParts, endParts)
  const end = formatCalendarEventDateTime(endParts, { includeDate: includeEndDate })
  const timeZone = calendarEvent.start_at?.time_zone || calendarEvent.end_at?.time_zone

  if (!start && !end) return null

  const range = start && end ? `${start} – ${end}` : start || end
  return [range, timeZone].filter(Boolean).join(' · ')
}

function formatCalendarEventRangeInLocalTime(calendarEvent: CalendarEvent) {
  const start = parseResolvedCalendarEventDateTime(calendarEvent.display_start_at)
  if (!start) return null

  const end = parseResolvedCalendarEventDateTime(calendarEvent.display_end_at)
  const includeEndDate = !end || !sameLocalCalendarDay(start, end)
  const startText = formatResolvedCalendarEventDateTime(start)
  const endText = end ? formatResolvedCalendarEventDateTime(end, { includeDate: includeEndDate }) : null
  const range = startText && endText ? `${startText} – ${endText}` : startText || endText
  const localTimeZone = formatLocalTimeZoneLabel(end || start)

  return [range, localTimeZone].filter(Boolean).join(' · ')
}

function formatCalendarEventDateTime(
  value?: CalendarEventDateParts | null,
  options: { includeDate?: boolean } = {}
) {
  if (!value) return null

  // Microsoft Graph event times are floating wall-clock values paired with a
  // timezone label. We anchor the parsed components in UTC only to preserve
  // those wall-clock fields for display without converting them into the
  // viewer's local timezone.
  const anchoredDate = new Date(Date.UTC(
    value.year,
    value.month - 1,
    value.day,
    value.hour,
    value.minute,
    value.second
  ))

  return new Intl.DateTimeFormat('en-US', {
    month: options.includeDate == false ? undefined : 'short',
    day: options.includeDate == false ? undefined : 'numeric',
    hour: 'numeric',
    minute: '2-digit',
    timeZone: 'UTC'
  }).format(anchoredDate)
}

function formatResolvedCalendarEventDateTime(
  value?: Date | null,
  options: { includeDate?: boolean } = {}
) {
  if (!value) return null

  return new Intl.DateTimeFormat('en-US', {
    month: options.includeDate == false ? undefined : 'short',
    day: options.includeDate == false ? undefined : 'numeric',
    hour: 'numeric',
    minute: '2-digit'
  }).format(value)
}

function formatLocalTimeZoneLabel(value: Date) {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZoneName: 'short'
  }).formatToParts(value)

  return parts.find((part) => part.type === 'timeZoneName')?.value || null
}

function parseResolvedCalendarEventDateTime(value?: string | null) {
  if (!value) return null

  const parsed = new Date(value)
  return Number.isNaN(parsed.getTime()) ? null : parsed
}

function parseCalendarEventDateParts(value?: string | null) {
  if (!value) return null

  const match = value.match(
    /^(?<year>\d{4})-(?<month>\d{2})-(?<day>\d{2})T(?<hour>\d{2}):(?<minute>\d{2})(?::(?<second>\d{2})(?:\.\d+)?)?$/
  )

  if (!match?.groups) return null

  const year = Number(match.groups.year)
  const month = Number(match.groups.month) - 1
  const day = Number(match.groups.day)
  const hour = Number(match.groups.hour)
  const minute = Number(match.groups.minute)
  const second = Number(match.groups.second || 0)

  return { year, month: month + 1, day, hour, minute, second }
}

function sameCalendarEventDay(left: CalendarEventDateParts, right: CalendarEventDateParts) {
  return left.year === right.year && left.month === right.month && left.day === right.day
}

function sameLocalCalendarDay(left: Date, right: Date) {
  return left.getFullYear() === right.getFullYear() &&
    left.getMonth() === right.getMonth() &&
    left.getDate() === right.getDate()
}
