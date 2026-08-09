import { router } from '@inertiajs/react'
import { useState, useCallback, useEffect, useMemo, useRef } from 'react'
import AuthenticatedLayout from '../../layouts/AuthenticatedLayout'
import { t } from '../../lib/i18n'
import { truncateScrapedContent } from '../../lib/truncateScrapedContent'
import { Table, TableHeader, TableBody, TableRow, TableHead, TableCell } from '../../components/ui/Table'
import { TabBar } from '../../components/ui/TabBar'
import { Badge, BadgeProps } from '../../components/ui/Badge'
import { Button } from '../../components/ui/Button'
import { SlideOver } from '../../components/ui/SlideOver'
import Textarea from '../../components/ui/Textarea'
import { CalendarCheck, Search, UserX, Meh, Smile, Building2, Clock, MapPin, Mail, User, Linkedin, Globe, ExternalLink, Brain, Trash2, Pencil, List, ChevronLeft, ChevronRight, ChevronDown, Plus, FileText, Briefcase, CheckCircle2, X } from 'lucide-react'

interface Lead {
  id: number
  first_name: string | null
  last_name: string | null
  full_name: string | null
  email: string
  job_title: string | null
  company: string | null
  assigned_agent_ids: number[]
}

interface Agent {
  id: number
  name: string
}

interface AssignableUser {
  id: number
  full_name: string
  email: string
  role: string
}

interface Meeting {
  id: number
  status: string
  meeting_type: string | null
  scheduled_at: string | null
  duration_minutes: number | null
  location: string | null
  notes: string | null
  outcome: string | null
  source: string
  created_at: string
  lead: Lead
  agent: Agent
  assigned_to_account: AssignableUser | null
  removal_comment: string | null
}

interface Pagination {
  current_page: number
  total_pages: number
  total_count: number
  per_page: number
}

interface TabCounts {
  all: number
  positive: number
  neutral: number
  scheduling: number
  scheduled: number
  no_show: number
}

interface Filters {
  status_filter?: string
  search?: string
}

interface MeetingsIndexProps {
  auth: {
    account: {
      id: number
      email: string
      first_name: string
      last_name: string
      full_name: string
      role: string
    }
  }
  meetings: Meeting[]
  assignable_users: AssignableUser[]
  agents: Agent[]
  filters: Filters
  tab_counts: TabCounts
  pagination: Pagination
  flash?: {
    notice?: string
    alert?: string
  }
}

type CreateMeetingLeadMode = 'existing' | 'new'

const getStatusBadge = (status: string): { variant: BadgeProps['variant']; label: string } => {
  switch (status) {
    case 'scheduled':
      return { variant: 'info', label: t('admin.meetings.statuses.scheduled') }
    case 'scheduling':
      return { variant: 'info', label: t('admin.meetings.statuses.scheduling') }
    case 'completed':
      return { variant: 'success', label: t('admin.meetings.statuses.completed') }
    case 'positive':
      return { variant: 'success', label: t('meetings.outcomes.positive') }
    case 'neutral':
      return { variant: 'default', label: t('meetings.outcomes.neutral') }
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

const canRequestRemoval = (meeting: Meeting) => ['scheduled', 'scheduling', 'rescheduled'].includes(meeting.status)
const canEditMeetingTime = (_meeting: Meeting) => true
const hasMeetingTimePassed = (meeting: Meeting) => meeting.scheduled_at !== null && new Date(meeting.scheduled_at).getTime() <= Date.now()
const canMarkMeetingStatus = (meeting: Meeting) => ['scheduled', 'scheduling', 'rescheduled'].includes(meeting.status) && (meeting.scheduled_at === null || hasMeetingTimePassed(meeting))
const canChangeMeetingOutcome = (meeting: Meeting) => canMarkMeetingStatus(meeting) || ['positive', 'neutral', 'no_show'].includes(meeting.status)

const getCsrfToken = () => document.querySelector('meta[name="csrf-token"]')?.getAttribute('content')
  || (document.querySelector('input[name="authenticity_token"]') as HTMLInputElement | null)?.value
  || ''

const toDateTimeLocalValue = (dateString: string | null) => {
  if (!dateString) return ''

  const date = new Date(dateString)
  if (Number.isNaN(date.getTime())) return ''

  const timezoneOffset = date.getTimezoneOffset() * 60_000
  return new Date(date.getTime() - timezoneOffset).toISOString().slice(0, 16)
}

const toIsoDateTime = (value: string) => {
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return null

  return date.toISOString()
}

const leadOptionLabel = (lead: Lead) => lead.full_name || lead.email

interface ModalGeneratedMessage {
  id: number
  subject: string
  body: string
  status: string
  sent_at: string | null
  created_at: string
}

interface ModalAgentLead {
  id: number
  delivery_status: string
  sequence_position: number
  agent: { id: number; name: string; status: string }
  generated_messages: ModalGeneratedMessage[]
}

interface ModalThreadMessage {
  id: number
  type: 'incoming' | 'outgoing'
  source: 'generated_message' | 'reply' | 'sent_reply'
  from: string
  subject: string
  body_plain: string | null
  body_html: string | null
  message_at: string
  is_bounce: boolean
  is_out_of_office: boolean
}

interface ModalConversation {
  id: number
  status: string
  mailbox: { id: number; email: string }
  thread: ModalThreadMessage[]
}

interface LeadModalData {
  id: number
  email: string
  display_name: string
  first_name: string | null
  last_name: string | null
  full_name: string | null
  company: string | null
  company_website: string | null
  job_title: string | null
  location: string | null
  linkedin_url: string | null
  timezone: string | null
  blacklisted: boolean
  blacklist_reason: string | null
  custom_fields: Record<string, unknown> | null
  disc_profile: string | null
  disc_profile_data: { confidence?: number; reasoning?: string } | null
  disc_profile_assessed_at: string | null
  disc_profile_source: string | null
  linkedin_scraped_at: string | null
  linkedin_scraped_data: {
    headline?: string
    summary?: string
  } | null
  linkedin_headline: string | null
  linkedin_summary: string | null
  linkedin_profile_photo_url: string | null
  linkedin_posts_scraped_at: string | null
  linkedin_posts: Array<{ text: string; url: string; date: string }> | null
  company_website_scraped_at: string | null
  company_website_content: string | null
  person?: { id: number; display_name: string | null } | null
  email_provider: string | null
  agent_leads: ModalAgentLead[]
  conversations: ModalConversation[]
  meeting_declined_comments: Array<{
    id: number
    body: string
    created_at: string
    account: {
      id: number
      full_name: string
    }
  }>
}

interface TimelineMessage {
  key: string
  timestamp: Date
  subject: string
  body: string
  from: string
  tone: 'incoming' | 'outgoing' | 'generated'
  label: string
}

const buildTimeline = (data: LeadModalData | null): TimelineMessage[] => {
  if (!data) return []

  const htmlToPlainText = (html: string | null): string => {
    if (!html) return ''

    if (typeof window === 'undefined') {
      return html.replace(/<[^>]*>/g, ' ').replace(/\s+/g, ' ').trim()
    }

    const doc = new DOMParser().parseFromString(html, 'text/html')
    return doc.body.textContent?.replace(/\s+/g, ' ').trim() || ''
  }

  const generated = data.agent_leads.flatMap(agentLead =>
    agentLead.generated_messages.map(message => ({
      key: `generated_message:${message.id}`,
      timestamp: new Date(message.sent_at || message.created_at),
      subject: message.subject || t('customer.agents.modal.messages.no_subject'),
      body: message.body,
      from: t('customer.agents.modal.messages.generated_for', {
        agent: agentLead.agent.name
      }),
      tone: 'generated' as const,
      label: t('customer.agents.modal.messages.generated_label', {
        status: message.status
      })
    }))
  )

  const thread = data.conversations.flatMap(conversation =>
    conversation.thread.map(message => ({
      key: `${message.source}:${message.id}`,
      timestamp: new Date(message.message_at),
      subject: message.subject || t('customer.agents.modal.messages.no_subject'),
      body: message.body_plain?.trim() || htmlToPlainText(message.body_html),
      from: message.from,
      tone: message.type === 'incoming' ? 'incoming' as const : 'outgoing' as const,
      label: message.is_bounce
        ? t('customer.agents.modal.messages.bounce')
        : message.is_out_of_office
          ? t('customer.agents.modal.messages.ooo')
          : t('customer.agents.modal.messages.conversation')
    }))
  )

  const unique = new Map<string, TimelineMessage>()
  ;[...generated, ...thread].forEach((entry) => {
    if (!unique.has(entry.key)) unique.set(entry.key, entry)
  })

  return [...unique.values()].sort((a, b) => a.timestamp.getTime() - b.timestamp.getTime())
}

function OutcomeButton({
  type,
  isActive,
  onClick,
  title,
  disabled = false,
}: {
  type: 'no_show' | 'neutral' | 'positive'
  isActive: boolean
  onClick: (event: React.MouseEvent<HTMLButtonElement>) => void
  title: string
  disabled?: boolean
}) {
  const icons = {
    no_show: UserX,
    neutral: Meh,
    positive: Smile,
  }
  const activeColors = {
    no_show: 'text-amber-300 bg-amber-400/25 ring-1 ring-amber-400/30',
    neutral: 'text-white bg-white/25 ring-1 ring-white/20',
    positive: 'text-emerald-400 bg-emerald-400/25 ring-1 ring-emerald-400/30',
  }

  const Icon = icons[type]

  return (
    <div className="relative flex items-center">
      <button
        type="button"
        onClick={onClick}
        disabled={disabled}
        aria-label={title}
        className={`
          peer size-8 rounded-full flex items-center justify-center transition-all duration-150
          ${isActive
            ? activeColors[type]
            : 'text-[var(--foreground-subtle)] hover:text-[var(--foreground-muted)] hover:bg-white/5 disabled:opacity-40 disabled:hover:bg-transparent disabled:hover:text-[var(--foreground-subtle)]'
          }
          disabled:cursor-not-allowed
        `}
      >
        <Icon className="size-[18px]" strokeWidth={1.5} />
      </button>
      <span className="pointer-events-none absolute bottom-full left-1/2 z-10 mb-2 -translate-x-1/2 whitespace-nowrap rounded-md border border-[var(--border)] bg-[var(--card)] px-2 py-1 text-[11px] font-medium text-[var(--foreground)] opacity-0 shadow-lg transition-opacity duration-100 peer-hover:opacity-100 peer-focus-visible:opacity-100">
        {title}
      </span>
    </div>
  )
}


export default function Index({
  auth,
  meetings,
  assignable_users,
  agents,
  filters,
  tab_counts,
  pagination,
  flash,
}: MeetingsIndexProps) {
  const account = auth.account
  const [searchValue, setSearchValue] = useState(filters.search || '')
  const [selectedMeeting, setSelectedMeeting] = useState<Meeting | null>(null)
  const [isModalOpen, setIsModalOpen] = useState(false)
  const [loadingLead, setLoadingLead] = useState(false)
  const [modalError, setModalError] = useState<string | null>(null)
  const [modalData, setModalData] = useState<LeadModalData | null>(null)
  const [requestingRemovalId, setRequestingRemovalId] = useState<number | null>(null)
  const [removeMeetingCandidate, setRemoveMeetingCandidate] = useState<Meeting | null>(null)
  const [editMeetingCandidate, setEditMeetingCandidate] = useState<Meeting | null>(null)
  const [updatingMeetingStatusId, setUpdatingMeetingStatusId] = useState<number | null>(null)
  const [meetingTimeInput, setMeetingTimeInput] = useState('')
  const [meetingTimeError, setMeetingTimeError] = useState<string | null>(null)
  const [savingMeetingTime, setSavingMeetingTime] = useState(false)
  const [isEditingMeetingNotes, setIsEditingMeetingNotes] = useState(false)
  const [meetingNotesInput, setMeetingNotesInput] = useState('')
  const [meetingNotesError, setMeetingNotesError] = useState<string | null>(null)
  const [savingMeetingNotes, setSavingMeetingNotes] = useState(false)
  const [quickEditMeetingTimeInput, setQuickEditMeetingTimeInput] = useState('')
  const [quickEditMeetingTimeError, setQuickEditMeetingTimeError] = useState<string | null>(null)
  const [savingQuickEditMeetingTime, setSavingQuickEditMeetingTime] = useState(false)
  const [assigningMeetingId, setAssigningMeetingId] = useState<number | null>(null)
  const [removeMeetingComment, setRemoveMeetingComment] = useState('')
  const [removeMeetingError, setRemoveMeetingError] = useState<string | null>(null)
  const [isCreateMeetingModalOpen, setIsCreateMeetingModalOpen] = useState(false)
  const [createMeetingLeadMode, setCreateMeetingLeadMode] = useState<CreateMeetingLeadMode>('existing')
  const [leadSearchQuery, setLeadSearchQuery] = useState('')
  const [leadSearchResults, setLeadSearchResults] = useState<Lead[]>([])
  const [leadSearchHasMore, setLeadSearchHasMore] = useState(false)
  const [selectedCreateLeadId, setSelectedCreateLeadId] = useState<number | null>(null)
  const [selectedCreateLead, setSelectedCreateLead] = useState<Lead | null>(null)
  const [isLeadComboboxOpen, setIsLeadComboboxOpen] = useState(false)
  const [activeLeadResultIndex, setActiveLeadResultIndex] = useState<number | null>(null)
  const [isSearchingLeads, setIsSearchingLeads] = useState(false)
  const [isCreatingMeeting, setIsCreatingMeeting] = useState(false)
  const [createMeetingError, setCreateMeetingError] = useState<string | null>(null)
  const [createMeetingForm, setCreateMeetingForm] = useState({
    agent_id: agents[0]?.id.toString() || '',
    scheduled_at: '',
    notes: ''
  })
  const [newLeadForm, setNewLeadForm] = useState({
    name: '',
    email: '',
    company: '',
    role: ''
  })
  const leadComboboxRef = useRef<HTMLDivElement | null>(null)
  const leadComboboxInputRef = useRef<HTMLInputElement | null>(null)
  const leadSearchAbortControllerRef = useRef<AbortController | null>(null)

  const clearSelectedCreateLead = () => {
    setSelectedCreateLeadId(null)
    setSelectedCreateLead(null)
    setLeadSearchQuery('')
    setLeadSearchResults([])
    setLeadSearchHasMore(false)
    setIsLeadComboboxOpen(false)
    setActiveLeadResultIndex(null)
    requestAnimationFrame(() => leadComboboxInputRef.current?.focus())
  }


  const activeTab = filters.status_filter || 'all'

  const tabs = [
    { id: 'all', label: t('meetings.tabs.all'), count: tab_counts.all, icon: List },
    { id: 'positive', label: t('meetings.tabs.positive'), count: tab_counts.positive, icon: Smile },
    { id: 'neutral', label: t('meetings.tabs.neutral'), count: tab_counts.neutral, icon: Meh },
    { id: 'scheduling', label: t('admin.meetings.statuses.scheduling'), count: tab_counts.scheduling, icon: Clock },
    { id: 'scheduled', label: t('admin.meetings.statuses.scheduled'), count: tab_counts.scheduled, icon: CalendarCheck },
    { id: 'no_show', label: t('admin.meetings.statuses.no_show'), count: tab_counts.no_show, icon: UserX },
  ]

  const navigate = useCallback((params: Record<string, string>) => {
    router.get('/meetings', params, {
      preserveState: true,
      preserveScroll: true,
    })
  }, [])

  const handleTabChange = (tabId: string) => {
    const params: Record<string, string> = {}
    if (tabId !== 'all') params.status_filter = tabId
    if (filters.search) params.search = filters.search
    navigate(params)
  }

  const handleSearch = () => {
    const params: Record<string, string> = {}
    if (filters.status_filter) params.status_filter = filters.status_filter
    if (searchValue.trim()) params.search = searchValue.trim()
    navigate(params)
  }

  const handleSearchKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter') handleSearch()
  }

  const handleSetOutcome = async (meetingId: number, outcome: 'positive' | 'neutral' | 'no_show') => {
    if (updatingMeetingStatusId === meetingId) return

    setUpdatingMeetingStatusId(meetingId)

    try {
      const response = await fetch(`/meetings/${meetingId}/set_outcome`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': getCsrfToken(),
        },
        body: JSON.stringify({ outcome }),
      })

      const payload = await response.json() as { success?: boolean; error?: string; meeting?: Meeting }
      if (!response.ok || !payload.meeting) {
        throw new Error(payload.error || t('meetings.outcome_update_failed'))
      }

      updateSelectedMeeting(payload.meeting)
      router.reload({ only: ['meetings', 'tab_counts', 'pagination'] })
    } catch (error) {
      window.alert(error instanceof Error ? error.message : t('meetings.outcome_update_failed'))
    } finally {
      setUpdatingMeetingStatusId(null)
    }
  }

  const updateSelectedMeeting = (meeting: Meeting) => {
    setSelectedMeeting(current => current?.id === meeting.id ? meeting : current)
  }

  const assignableUsersForMeeting = (meeting: Meeting) => {
    const assignedAccount = meeting.assigned_to_account
    if (!assignedAccount) return assignable_users

    return assignable_users.some((account) => account.id === assignedAccount.id)
      ? assignable_users
      : [assignedAccount, ...assignable_users]
  }

  const updateMeetingTime = async (meeting: Meeting, inputValue: string) => {
    const scheduledAt = toIsoDateTime(inputValue)
    if (!scheduledAt) {
      return { error: t('meetings.invalid_time') }
    }

    try {
      const response = await fetch(`/meetings/${meeting.id}/reschedule`, {
        method: 'POST',
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'X-CSRF-Token': getCsrfToken(),
        },
        body: JSON.stringify({ scheduled_at: scheduledAt })
      })

      const payload = await response.json() as { success?: boolean; error?: string; meeting?: Meeting }
      if (!response.ok || !payload.meeting) {
        throw new Error(payload.error || t('meetings.meeting_time_update_failed'))
      }

      updateSelectedMeeting(payload.meeting)
      router.reload({ only: ['meetings', 'tab_counts', 'pagination'] })
      return { meeting: payload.meeting }
    } catch (error) {
      return { error: error instanceof Error ? error.message : t('meetings.meeting_time_update_failed') }
    }
  }

  const handleSaveMeetingTime = async () => {
    if (!selectedMeeting || !canEditMeetingTime(selectedMeeting)) return

    setSavingMeetingTime(true)
    setMeetingTimeError(null)

    const result = await updateMeetingTime(selectedMeeting, meetingTimeInput)

    if (result.meeting) {
      setMeetingTimeInput(toDateTimeLocalValue(result.meeting.scheduled_at))
    } else if (result.error) {
      setMeetingTimeError(result.error)
    }

    setSavingMeetingTime(false)
  }

  const handleSaveMeetingNotes = async () => {
    if (!selectedMeeting || savingMeetingNotes) return

    setSavingMeetingNotes(true)
    setMeetingNotesError(null)

    try {
      const response = await fetch(`/meetings/${selectedMeeting.id}/update_notes`, {
        method: 'PATCH',
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'X-CSRF-Token': getCsrfToken(),
        },
        body: JSON.stringify({ notes: meetingNotesInput })
      })

      const payload = await response.json() as { success?: boolean; error?: string; meeting?: Meeting }
      if (!response.ok || !payload.meeting) {
        throw new Error(payload.error || t('meetings.notes_update_failed'))
      }

      updateSelectedMeeting(payload.meeting)
      setMeetingNotesInput(payload.meeting.notes || '')
      setIsEditingMeetingNotes(false)
      router.reload({ only: ['meetings'] })
    } catch (error) {
      setMeetingNotesError(error instanceof Error
        ? error.message
        : t('meetings.notes_update_failed'))
    } finally {
      setSavingMeetingNotes(false)
    }
  }

  const handleMeetingNotesKeyDown = (event: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (event.key === 'Enter' && !event.shiftKey) {
      event.preventDefault()
      void handleSaveMeetingNotes()
    }

    if (event.key === 'Escape') {
      setMeetingNotesInput(selectedMeeting?.notes || '')
      setMeetingNotesError(null)
      setIsEditingMeetingNotes(false)
    }
  }

  const handleSaveQuickEditMeetingTime = async () => {
    if (!editMeetingCandidate || !canEditMeetingTime(editMeetingCandidate)) return

    setSavingQuickEditMeetingTime(true)
    setQuickEditMeetingTimeError(null)

    const result = await updateMeetingTime(editMeetingCandidate, quickEditMeetingTimeInput)

    if (result.meeting) {
      setEditMeetingCandidate(null)
    } else if (result.error) {
      setQuickEditMeetingTimeError(result.error)
    }

    setSavingQuickEditMeetingTime(false)
  }

  const handleRequestRemoval = async (meeting: Meeting): Promise<boolean> => {
    if (requestingRemovalId === meeting.id || !canRequestRemoval(meeting)) return false

    setRequestingRemovalId(meeting.id)
    setRemoveMeetingError(null)

    try {
      const response = await fetch(`/meetings/${meeting.id}/request_removal`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': getCsrfToken(),
          'Accept': 'application/json'
        },
        body: JSON.stringify({ comment: removeMeetingComment.trim() })
      })

      const payload = await response.json() as { success?: boolean; error?: string; meeting?: Meeting }

      if (!response.ok) {
        throw new Error(payload.error || t('meetings.request_removal_failed'))
      }

      router.reload({ only: ['meetings', 'tab_counts', 'pagination'] })
      if (payload.meeting) {
        updateSelectedMeeting(payload.meeting)
      }
      return true
    } catch (error) {
      setRemoveMeetingError(
        error instanceof Error
          ? error.message
          : t('meetings.request_removal_failed')
      )
      return false
    } finally {
      setRequestingRemovalId(null)
    }
  }

  const handleAssignMeeting = async (meeting: Meeting, assignedToAccountId: string) => {
    const currentAssignedId = meeting.assigned_to_account?.id?.toString() || ''
    if (assigningMeetingId === meeting.id || assignedToAccountId === currentAssignedId) return

    setAssigningMeetingId(meeting.id)

    try {
      const response = await fetch(`/meetings/${meeting.id}/assign`, {
        method: 'POST',
        headers: {
          Accept: 'application/json',
          'Content-Type': 'application/json',
          'X-CSRF-Token': getCsrfToken(),
        },
        body: JSON.stringify({ assigned_to_account_id: assignedToAccountId || null })
      })

      const payload = await response.json() as { success?: boolean; error?: string; meeting?: Meeting }
      if (!response.ok || !payload.meeting) {
        throw new Error(payload.error || t('meetings.assign.failed'))
      }

      updateSelectedMeeting(payload.meeting)
      router.reload({ only: ['meetings'] })
    } catch (error) {
      window.alert(error instanceof Error
        ? error.message
        : t('meetings.assign.failed'))
    } finally {
      setAssigningMeetingId(null)
    }
  }

  const openCreateMeetingModal = () => {
    setCreateMeetingLeadMode('existing')
    setLeadSearchQuery('')
    setLeadSearchResults([])
    setLeadSearchHasMore(false)
    setSelectedCreateLeadId(null)
    setSelectedCreateLead(null)
    setIsLeadComboboxOpen(false)
    setActiveLeadResultIndex(null)
    setCreateMeetingError(null)
    setCreateMeetingForm({
      agent_id: agents[0]?.id.toString() || '',
      scheduled_at: '',
      notes: ''
    })
    setNewLeadForm({ name: '', email: '', company: '', role: '' })
    setIsCreateMeetingModalOpen(true)
  }

  const closeCreateMeetingModal = () => {
    if (isCreatingMeeting) return
    leadSearchAbortControllerRef.current?.abort()
    setIsCreateMeetingModalOpen(false)
  }

  const searchLeadsForMeeting = useCallback(async ({
    query,
    offset = 0,
    append = false
  }: {
    query: string
    offset?: number
    append?: boolean
  }) => {
    const trimmedQuery = query.trim()

    if (!trimmedQuery) {
      leadSearchAbortControllerRef.current?.abort()
      setLeadSearchResults([])
      setLeadSearchHasMore(false)
      setActiveLeadResultIndex(null)
      setIsSearchingLeads(false)
      return
    }

    leadSearchAbortControllerRef.current?.abort()
    const abortController = new AbortController()
    leadSearchAbortControllerRef.current = abortController
    setIsSearchingLeads(true)
    setCreateMeetingError(null)

    try {
      const params = new URLSearchParams({ q: trimmedQuery, offset: offset.toString() })
      const response = await fetch(`/meetings/search_leads?${params.toString()}`, {
        headers: { Accept: 'application/json' },
        signal: abortController.signal
      })
      const payload = await response.json() as { leads?: Lead[]; has_more?: boolean; error?: string }

      if (!response.ok) {
        throw new Error(payload.error || t('meetings.create.search_failed'))
      }

      const nextLeads = payload.leads || []
      setLeadSearchResults(current => append ? [...current, ...nextLeads] : nextLeads)
      setLeadSearchHasMore(Boolean(payload.has_more))
      setActiveLeadResultIndex(null)
      setIsLeadComboboxOpen(true)
    } catch (error) {
      if (abortController.signal.aborted) return
      setCreateMeetingError(error instanceof Error ? error.message : t('meetings.create.search_failed'))
    } finally {
      if (!abortController.signal.aborted) {
        setIsSearchingLeads(false)
      }
    }
  }, [])

  const selectLeadForMeeting = (lead: Lead) => {
    leadSearchAbortControllerRef.current?.abort()
    setSelectedCreateLeadId(lead.id)
    setSelectedCreateLead(lead)
    setLeadSearchQuery(leadOptionLabel(lead))
    setLeadSearchResults([lead])
    setLeadSearchHasMore(false)
    setIsLeadComboboxOpen(false)
    setActiveLeadResultIndex(null)

    const assignedAgentId = lead.assigned_agent_ids.find((agentId) => agents.some((agent) => agent.id === agentId))
    if (assignedAgentId) {
      setCreateMeetingForm(current => ({ ...current, agent_id: assignedAgentId.toString() }))
    }
  }

  const handleLeadComboboxKeyDown = (event: React.KeyboardEvent<HTMLInputElement>) => {
    if (event.key === 'Escape') {
      setIsLeadComboboxOpen(false)
      setActiveLeadResultIndex(null)
      return
    }

    if (event.key === 'ArrowDown') {
      event.preventDefault()
      setIsLeadComboboxOpen(true)
      setActiveLeadResultIndex(current => {
        if (leadSearchResults.length === 0) return null
        return current === null ? 0 : Math.min(current + 1, leadSearchResults.length - 1)
      })
      return
    }

    if (event.key === 'ArrowUp') {
      event.preventDefault()
      setActiveLeadResultIndex(current => {
        if (leadSearchResults.length === 0) return null
        return current === null ? leadSearchResults.length - 1 : Math.max(current - 1, 0)
      })
      return
    }

    if (event.key === 'Enter' && activeLeadResultIndex !== null) {
      event.preventDefault()
      const activeLead = leadSearchResults[activeLeadResultIndex]
      if (activeLead) selectLeadForMeeting(activeLead)
    }
  }

  const handleCreateMeeting = async (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    if (isCreatingMeeting) return

    setIsCreatingMeeting(true)
    setCreateMeetingError(null)

    const leadPayload = createMeetingLeadMode === 'new'
      ? { lead: newLeadForm }
      : { lead_id: selectedCreateLeadId }

    try {
      const response = await fetch('/meetings', {
        method: 'POST',
        headers: {
          Accept: 'application/json',
          'Content-Type': 'application/json',
          'X-CSRF-Token': getCsrfToken()
        },
        body: JSON.stringify({
          ...leadPayload,
          agent_id: createMeetingForm.agent_id,
          scheduled_at: createMeetingForm.scheduled_at || null,
          notes: createMeetingForm.notes
        })
      })

      const payload = await response.json() as { success?: boolean; error?: string }

      if (!response.ok || !payload.success) {
        throw new Error(payload.error || t('meetings.create.failed'))
      }

      setIsCreateMeetingModalOpen(false)
      router.reload({ only: ['meetings', 'tab_counts', 'pagination'] })
    } catch (error) {
      setCreateMeetingError(error instanceof Error ? error.message : t('meetings.create.failed'))
    } finally {
      setIsCreatingMeeting(false)
    }
  }

  useEffect(() => {
    setMeetingTimeInput(toDateTimeLocalValue(selectedMeeting?.scheduled_at ?? null))
    setMeetingTimeError(null)
    setMeetingNotesInput(selectedMeeting?.notes || '')
    setMeetingNotesError(null)
    setIsEditingMeetingNotes(false)
  }, [selectedMeeting])

  useEffect(() => {
    if (!createMeetingForm.agent_id && agents[0]) {
      setCreateMeetingForm(current => ({ ...current, agent_id: agents[0].id.toString() }))
    }
  }, [agents, createMeetingForm.agent_id])

  useEffect(() => {
    if (!isCreateMeetingModalOpen || createMeetingLeadMode !== 'existing') return

    const trimmedQuery = leadSearchQuery.trim()
    if (!trimmedQuery || selectedCreateLeadId) {
      if (!trimmedQuery) {
        leadSearchAbortControllerRef.current?.abort()
        setLeadSearchResults([])
        setLeadSearchHasMore(false)
        setActiveLeadResultIndex(null)
        setIsSearchingLeads(false)
      }
      return
    }

    const timeout = window.setTimeout(() => {
      void searchLeadsForMeeting({ query: trimmedQuery })
    }, 300)

    return () => window.clearTimeout(timeout)
  }, [createMeetingLeadMode, isCreateMeetingModalOpen, leadSearchQuery, searchLeadsForMeeting, selectedCreateLeadId])

  useEffect(() => {
    if (!isCreateMeetingModalOpen || createMeetingLeadMode !== 'existing') return

    const handleMouseDown = (event: MouseEvent) => {
      if (!leadComboboxRef.current?.contains(event.target as Node)) {
        setIsLeadComboboxOpen(false)
        setActiveLeadResultIndex(null)
      }
    }

    document.addEventListener('mousedown', handleMouseDown)
    return () => document.removeEventListener('mousedown', handleMouseDown)
  }, [createMeetingLeadMode, isCreateMeetingModalOpen])

  useEffect(() => {
    setQuickEditMeetingTimeInput(toDateTimeLocalValue(editMeetingCandidate?.scheduled_at ?? null))
    setQuickEditMeetingTimeError(null)
  }, [editMeetingCandidate])

  useEffect(() => {
    if (!removeMeetingCandidate) return

    setRemoveMeetingComment('')
    setRemoveMeetingError(null)

    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        setRemoveMeetingCandidate(null)
      }
    }

    window.addEventListener('keydown', handleKeyDown)
    return () => {
      window.removeEventListener('keydown', handleKeyDown)
    }
  }, [removeMeetingCandidate])

  useEffect(() => {
    if (!editMeetingCandidate) return

    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        setEditMeetingCandidate(null)
      }
    }

    window.addEventListener('keydown', handleKeyDown)
    return () => {
      window.removeEventListener('keydown', handleKeyDown)
    }
  }, [editMeetingCandidate])

  useEffect(() => {
    const fetchLead = async () => {
      if (!selectedMeeting?.id || !isModalOpen) return

      setLoadingLead(true)
      setModalError(null)

      try {
        const response = await fetch(`/meetings/${selectedMeeting.id}/lead_modal`, {
          headers: {
            Accept: 'application/json',
            'X-Requested-With': 'XMLHttpRequest'
          }
        })

        if (!response.ok) {
          throw new Error(`Failed with status ${response.status}`)
        }

        const payload = await response.json() as LeadModalData
        setModalData(payload)
      } catch {
      setModalError(t('customer.agents.modal.load_error'))
      } finally {
        setLoadingLead(false)
      }
    }

    fetchLead()
  }, [selectedMeeting, isModalOpen])

  const openMeetingPreparation = (meeting: Meeting) => {
    setSelectedMeeting(meeting)
    setModalData(null)
    setIsModalOpen(true)
  }

  const goToPage = (page: number) => {
    const params: Record<string, string> = { page: page.toString() }
    if (filters.status_filter) params.status_filter = filters.status_filter
    if (filters.search) params.search = filters.search
    navigate(params)
  }

  const formatDate = (dateString: string | null) => {
    if (!dateString) return '-'
    return new Date(dateString).toLocaleDateString(document.documentElement.lang || undefined, {
      month: 'short',
      day: 'numeric',
      year: 'numeric',
    })
  }

  const formatTime = (dateString: string | null) => {
    if (!dateString) return '-'
    return new Date(dateString).toLocaleTimeString(document.documentElement.lang || undefined, {
      hour: '2-digit',
      minute: '2-digit',
      hour12: false,
    })
  }

  const formatTableDateTime = (dateString: string | null) => {
    if (!dateString) {
      return t('meetings.no_time_set')
    }

    return `${formatDate(dateString)} · ${formatTime(dateString)}`
  }

  const getLeadName = (lead: Lead) => {
    return lead.full_name || lead.email
  }

  const timeline = useMemo(() => buildTimeline(modalData), [modalData])

  const formatDateTime = (dateString: string | null) => {
    if (!dateString) return '-'
    return new Date(dateString).toLocaleDateString(document.documentElement.lang || undefined, {
      month: 'short',
      day: 'numeric',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit'
    })
  }

  const meetingTypeLabel = selectedMeeting?.meeting_type
    ? t(`admin.meetings.types.${selectedMeeting.meeting_type}`)
    : '-'
  const canSaveMeetingTime = Boolean(
    selectedMeeting
      && canEditMeetingTime(selectedMeeting)
      && meetingTimeInput
      && meetingTimeInput !== toDateTimeLocalValue(selectedMeeting.scheduled_at)
  )
  const canSaveQuickEditMeetingTime = Boolean(
    editMeetingCandidate
      && canEditMeetingTime(editMeetingCandidate)
      && quickEditMeetingTimeInput
      && quickEditMeetingTimeInput !== toDateTimeLocalValue(editMeetingCandidate.scheduled_at)
  )

  return (
    <AuthenticatedLayout
      title={t('meetings.title')}
      subtitle={t('meetings.subtitle')}
      account={account}
      flash={flash}
      headerActions={(
        <div className="flex items-center gap-2">
          <Button
            type="button"
            variant="primary"
            size="md"
            onClick={openCreateMeetingModal}
            icon={<Plus className="h-4 w-4" />}
          >
            {t('meetings.create.button')}
          </Button>
          {pagination.total_pages > 1 && (
            <div className="flex items-center gap-1.5">
              <button
                type="button"
                onClick={() => goToPage(pagination.current_page - 1)}
                disabled={pagination.current_page === 1}
                className="flex size-8 items-center justify-center rounded-lg border border-[var(--border)] text-[var(--foreground-muted)] transition-colors hover:bg-[var(--card-hover)] hover:text-[var(--foreground)] disabled:opacity-40 disabled:cursor-not-allowed"
              >
                <ChevronLeft className="size-4" />
              </button>
              <span className="min-w-[3ch] text-center text-xs tabular-nums text-[var(--foreground-muted)]">
                {pagination.current_page}/{pagination.total_pages}
              </span>
              <button
                type="button"
                onClick={() => goToPage(pagination.current_page + 1)}
                disabled={pagination.current_page === pagination.total_pages}
                className="flex size-8 items-center justify-center rounded-lg border border-[var(--border)] text-[var(--foreground-muted)] transition-colors hover:bg-[var(--card-hover)] hover:text-[var(--foreground)] disabled:opacity-40 disabled:cursor-not-allowed"
              >
                <ChevronRight className="size-4" />
              </button>
            </div>
          )}
        </div>
      )}
    >
      {/* Tabs + Pagination + Search Row */}
      <div className="mb-6 flex items-center justify-between gap-4">
        <TabBar
          tabs={tabs}
          activeTab={activeTab}
          onTabChange={handleTabChange}
        />

        <div className="flex h-10 w-[320px] items-center gap-2 rounded-xl border border-[var(--input-border)] bg-[var(--input)] px-3.5 py-1.5 shadow-[inset_0_1px_0_rgba(255,255,255,0.03)] transition-all duration-150 focus-within:border-[var(--ring)] focus-within:ring-4 focus-within:ring-[rgba(53,202,222,0.12)]">
          <Search
            className="shrink-0 text-[var(--foreground-muted)]"
            size={16}
            strokeWidth={2}
          />
          <input
            type="text"
            value={searchValue}
            onChange={(e) => setSearchValue(e.target.value)}
            onKeyDown={handleSearchKeyDown}
            onBlur={handleSearch}
            placeholder={t('meetings.search_placeholder')}
            className="flex-1 min-w-0 bg-transparent border-none outline-none text-sm leading-5 text-[var(--foreground)] placeholder:text-[var(--foreground-muted)] focus:outline-none focus:ring-0"
          />
        </div>
      </div>

      {/* Meetings Table */}
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>{t('meetings.table.name')}</TableHead>
            <TableHead>{t('meetings.table.agent')}</TableHead>
            <TableHead>{t('meetings.table.meeting_date_time')}</TableHead>
            <TableHead>{t('meetings.table.status')}</TableHead>
            <TableHead>{t('meetings.table.assign')}</TableHead>
            <TableHead className="!text-center w-px">{t('meetings.table.outcome')}</TableHead>
            <TableHead className="w-px">{''}</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {meetings.length === 0 ? (
            <TableRow>
              <TableCell colSpan={7} className="text-center py-12">
                <div className="flex flex-col items-center gap-4">
                  <CalendarCheck className="h-12 w-12 text-[var(--foreground-subtle)]" />
                  <span className="text-[var(--foreground-muted)]">
                    {t('meetings.empty')}
                  </span>
                </div>
              </TableCell>
            </TableRow>
          ) : (
            meetings.map((meeting) => {
              const statusBadge = getStatusBadge(meeting.status)

              return (
                <TableRow key={meeting.id} onClick={() => openMeetingPreparation(meeting)} className="cursor-pointer">
                <TableCell variant="primary">
                  <div className="space-y-0.5">
                    <div className="text-sm font-medium text-[var(--foreground)]">{getLeadName(meeting.lead)}</div>
                    <div
                      className="max-w-[220px] truncate text-xs text-[var(--foreground-subtle)]"
                      title={meeting.lead.job_title || '-'}
                    >
                      {meeting.lead.job_title || '-'}
                    </div>
                    <div
                      className="max-w-[220px] truncate text-xs text-[var(--foreground-muted)]"
                      title={meeting.lead.company || '-'}
                    >
                      {meeting.lead.company || '-'}
                    </div>
                  </div>
                </TableCell>
                <TableCell>
                  <div className="max-w-[160px] truncate text-sm text-[var(--foreground-muted)]" title={meeting.agent.name}>
                    {meeting.agent.name}
                  </div>
                </TableCell>
                <TableCell>
                  <div className="flex items-center gap-2">
                    <span>{formatTableDateTime(meeting.scheduled_at)}</span>
                    {canEditMeetingTime(meeting) && (
                      <button
                        type="button"
                        onClick={(event) => {
                          event.stopPropagation()
                          setEditMeetingCandidate(meeting)
                        }}
                        className="inline-flex size-7 items-center justify-center rounded-md text-[var(--foreground-subtle)] transition-colors hover:bg-white/5 hover:text-[var(--foreground)]"
                        title={meeting.scheduled_at
                          ? t('meetings.edit_time')
                          : t('meetings.set_time')}
                        aria-label={meeting.scheduled_at
                          ? t('meetings.edit_time')
                          : t('meetings.set_time')}
                      >
                        <Pencil className="h-4 w-4" />
                      </button>
                    )}
                  </div>
                </TableCell>
                <TableCell>
                  <Badge size="sm" variant={statusBadge.variant}>
                    {statusBadge.label}
                  </Badge>
                </TableCell>
                <TableCell onClick={(event) => event.stopPropagation()}>
                  <div className="relative min-w-[220px]">
                    <select
                      value={meeting.assigned_to_account?.id?.toString() || ''}
                      disabled={assigningMeetingId === meeting.id}
                      onChange={(event) => {
                        void handleAssignMeeting(meeting, event.target.value)
                      }}
                      className="w-full appearance-none rounded-xl border border-[var(--input-border)] bg-[var(--input)] py-2 pl-3.5 pr-9 text-sm text-[var(--foreground)] shadow-[inset_0_1px_0_rgba(255,255,255,0.03)] focus:outline-none focus:ring-2 focus:ring-[var(--accent)] disabled:cursor-not-allowed disabled:opacity-60"
                      aria-label={t('meetings.assign.label')}
                    >
                      <option value="">{t('meetings.assign.unassigned')}</option>
                      {assignableUsersForMeeting(meeting).map((accountOption) => (
                        <option key={accountOption.id} value={accountOption.id}>
                          {accountOption.full_name}
                        </option>
                      ))}
                    </select>
                    <div className="pointer-events-none absolute inset-y-0 right-0 flex items-center px-2 text-[var(--foreground-subtle)]">
                      <ChevronDown className="h-4 w-4" aria-hidden="true" />
                    </div>
                    <div className="mt-1 truncate text-[11px] text-[var(--foreground-subtle)]" title={meeting.assigned_to_account?.email || ''}>
                      {meeting.assigned_to_account?.email || t('meetings.assign.help')}
                    </div>
                  </div>
                </TableCell>
                <TableCell className="!overflow-visible">
                  <div className="flex items-center justify-center gap-1">
                    <OutcomeButton
                      type="no_show"
                      isActive={meeting.status === 'no_show'}
                      disabled={!canChangeMeetingOutcome(meeting) || updatingMeetingStatusId === meeting.id}
                      onClick={(event) => {
                        event.stopPropagation()
                        void handleSetOutcome(meeting.id, 'no_show')
                      }}
                      title={t('meetings.mark_no_show')}
                    />
                    <OutcomeButton
                      type="neutral"
                      isActive={meeting.status === 'neutral'}
                      disabled={!canChangeMeetingOutcome(meeting) || updatingMeetingStatusId === meeting.id}
                      onClick={(event) => {
                        event.stopPropagation()
                        void handleSetOutcome(meeting.id, 'neutral')
                      }}
                      title={t('meetings.outcomes.neutral')}
                    />
                    <OutcomeButton
                      type="positive"
                      isActive={meeting.status === 'positive'}
                      disabled={!canChangeMeetingOutcome(meeting) || updatingMeetingStatusId === meeting.id}
                      onClick={(event) => {
                        event.stopPropagation()
                        void handleSetOutcome(meeting.id, 'positive')
                      }}
                      title={t('meetings.outcomes.positive')}
                    />
                  </div>
                </TableCell>
                <TableCell>
                  <button
                    type="button"
                    onClick={(event) => {
                      event.stopPropagation()
                      if (!canRequestRemoval(meeting)) return
                      setRemoveMeetingCandidate(meeting)
                    }}
                    disabled={requestingRemovalId === meeting.id || !canRequestRemoval(meeting)}
                    aria-label={t('meetings.request_removal')}
                    className="flex size-8 items-center justify-center rounded-full text-[var(--foreground-subtle)] transition-all duration-150 hover:bg-white/5 hover:text-[var(--foreground-muted)] disabled:opacity-40 disabled:cursor-not-allowed disabled:hover:bg-transparent disabled:hover:text-[var(--foreground-subtle)]"
                  >
                    <Trash2 className="size-[16px]" strokeWidth={1.75} />
                  </button>
                </TableCell>
                </TableRow>
              )
            })
          )}
        </TableBody>
      </Table>

      {isCreateMeetingModalOpen && (
        <div className="fixed inset-0 z-50 overflow-y-auto">
          <div className="flex min-h-screen items-center justify-center p-4">
            <button
              type="button"
              aria-label={t('common.cancel')}
              className="fixed inset-0 bg-black/60 backdrop-blur-sm"
              onClick={closeCreateMeetingModal}
            />

            <form
              onSubmit={handleCreateMeeting}
              className="relative z-10 w-full max-w-2xl rounded-2xl border border-[var(--border)] bg-[var(--card)] p-6 shadow-2xl"
            >
              <div className="mb-5">
                <h3 className="text-xl font-semibold text-[var(--foreground)]">
                  {t('meetings.create.title')}
                </h3>
                <p className="mt-1 text-sm text-[var(--foreground-muted)]">
                  {t('meetings.create.description')}
                </p>
              </div>

              {createMeetingError && (
                <div className="mb-4 rounded-xl border border-[var(--error)]/25 bg-[var(--error)]/10 px-3 py-2 text-sm text-[var(--error)]">
                  {createMeetingError}
                </div>
              )}

              <div className="mb-5 flex w-fit shrink-0 rounded-lg border border-[var(--border)] bg-[var(--bg-subtle)] p-0.5">
                {(['existing', 'new'] as CreateMeetingLeadMode[]).map((mode) => (
                  <button
                    key={mode}
                    type="button"
                    onClick={() => setCreateMeetingLeadMode(mode)}
                    className={`rounded-md px-3 py-1 text-xs font-medium transition-all ${createMeetingLeadMode === mode
                      ? 'bg-white text-black shadow-sm'
                      : 'text-[var(--foreground-muted)] hover:text-[var(--foreground)]'
                    }`}
                  >
                    {mode === 'existing'
                      ? t('meetings.create.existing_lead')
                      : t('meetings.create.new_lead')}
                  </button>
                ))}
              </div>

              {createMeetingLeadMode === 'existing' ? (
                <div className="space-y-3">
                  <div className="relative" ref={leadComboboxRef}>
                    <div className="relative">
                      <Search className="pointer-events-none absolute left-3.5 top-1/2 h-4 w-4 -translate-y-1/2 text-[var(--foreground-subtle)]" aria-hidden="true" />
                      <input
                        ref={leadComboboxInputRef}
                        id="meeting-lead-search"
                        type="text"
                        role="combobox"
                        aria-autocomplete="list"
                        aria-controls="meeting-lead-search-results"
                        aria-expanded={isLeadComboboxOpen}
                        aria-activedescendant={activeLeadResultIndex === null ? undefined : `meeting-lead-option-${leadSearchResults[activeLeadResultIndex]?.id}`}
                        aria-label={t('meetings.create.search_leads')}
                        value={leadSearchQuery}
                        onChange={(event) => {
                          setLeadSearchQuery(event.target.value)
                          setSelectedCreateLeadId(null)
                          setSelectedCreateLead(null)
                          setIsLeadComboboxOpen(true)
                          setActiveLeadResultIndex(null)
                          if (!event.target.value.trim()) {
                            setLeadSearchResults([])
                            setLeadSearchHasMore(false)
                          }
                        }}
                        onFocus={() => setIsLeadComboboxOpen(true)}
                        onKeyDown={handleLeadComboboxKeyDown}
                        className="h-10 w-full rounded-xl border border-[var(--input-border)] bg-[var(--input)] py-0 pl-10 pr-20 text-sm text-[var(--foreground)] outline-none focus:border-[var(--ring)] focus:ring-2 focus:ring-[rgba(53,202,222,0.12)]"
                        placeholder={t('meetings.create.search_placeholder')}
                      />
                      {selectedCreateLead && (
                        <button
                          type="button"
                          tabIndex={-1}
                          aria-label={t('meetings.create.clear_selection')}
                          onMouseDown={(event) => event.preventDefault()}
                          onClick={clearSelectedCreateLead}
                          className="absolute right-3 top-1/2 inline-flex size-6 -translate-y-1/2 items-center justify-center rounded-full bg-white text-black shadow-sm ring-1 ring-black/10 transition-transform hover:scale-105 hover:bg-white focus:outline-none focus:ring-2 focus:ring-[var(--accent)]"
                        >
                          <X className="h-3.5 w-3.5" strokeWidth={2.5} aria-hidden="true" />
                        </button>
                      )}
                      {isSearchingLeads && (
                        <span className={`absolute top-1/2 -translate-y-1/2 text-xs text-[var(--foreground-muted)] ${selectedCreateLead ? 'right-11' : 'right-3.5'}`}>
                          {t('common.loading')}
                        </span>
                      )}
                    </div>

                    {isLeadComboboxOpen && (
                      <div
                        id="meeting-lead-search-results"
                        role="listbox"
                        className="absolute left-0 right-0 top-full z-20 mt-2 max-h-72 overflow-y-auto rounded-xl border border-[var(--border)] bg-[var(--background)] p-2 shadow-xl custom-scrollbar"
                      >
                        {!leadSearchQuery.trim() ? (
                          <p className="px-2 py-3 text-sm text-[var(--foreground-muted)]">
                            {t('meetings.create.no_leads')}
                          </p>
                        ) : leadSearchResults.length === 0 && !isSearchingLeads ? (
                          <p className="px-2 py-3 text-sm text-[var(--foreground-muted)]">
                            {t('meetings.create.no_results')}
                          </p>
                        ) : leadSearchResults.map((lead, index) => (
                          <button
                            key={lead.id}
                            id={`meeting-lead-option-${lead.id}`}
                            type="button"
                            role="option"
                            aria-selected={selectedCreateLeadId === lead.id || activeLeadResultIndex === index}
                            onMouseDown={(event) => event.preventDefault()}
                            onMouseEnter={() => setActiveLeadResultIndex(index)}
                            onClick={() => selectLeadForMeeting(lead)}
                            className={`flex w-full items-start justify-between gap-3 rounded-lg px-3 py-2 text-left transition-colors ${selectedCreateLeadId === lead.id || activeLeadResultIndex === index
                              ? 'bg-[var(--accent)]/20 text-[var(--foreground)]'
                              : 'text-[var(--foreground-muted)] hover:bg-white/[0.04] hover:text-[var(--foreground)]'
                            }`}
                          >
                            <span>
                              <span className="block text-sm font-medium">{leadOptionLabel(lead)}</span>
                              <span className="block text-xs">{lead.email}</span>
                            </span>
                            <span className="max-w-[220px] truncate text-xs">{lead.company || lead.job_title || ''}</span>
                          </button>
                        ))}

                        {leadSearchHasMore && (
                          <button
                            type="button"
                            onMouseDown={(event) => event.preventDefault()}
                            onClick={() => void searchLeadsForMeeting({
                              query: leadSearchQuery,
                              offset: leadSearchResults.length,
                              append: true
                            })}
                            disabled={isSearchingLeads}
                            className="mt-1 w-full rounded-lg px-3 py-2 text-center text-sm font-medium text-[var(--accent)] transition-colors hover:bg-white/[0.04] disabled:opacity-60"
                          >
                            {t('meetings.create.see_more')}
                          </button>
                        )}
                      </div>
                    )}
                  </div>

                  {selectedCreateLead && (
                    <section className="rounded-[22px] border border-[var(--accent)]/30 bg-[var(--accent)]/[0.06] p-4 shadow-[var(--shadow-sm)]">
                      <div className="mb-3 flex items-center gap-2 text-xs font-semibold uppercase tracking-[0.18em] text-[var(--accent)]">
                        <CheckCircle2 className="h-4 w-4" aria-hidden="true" />
                        {t('meetings.create.selected_lead')}
                      </div>
                      <div className="grid gap-3 text-sm sm:grid-cols-2">
                        <div className="flex items-start gap-2">
                          <User className="mt-0.5 h-4 w-4 text-[var(--foreground-muted)]" aria-hidden="true" />
                          <div className="min-w-0">
                            <p className="text-xs text-[var(--foreground-subtle)]">{t('meetings.create.name_placeholder')}</p>
                            <p className="truncate text-[var(--foreground)]">{leadOptionLabel(selectedCreateLead)}</p>
                          </div>
                        </div>
                        <div className="flex items-start gap-2">
                          <Mail className="mt-0.5 h-4 w-4 text-[var(--foreground-muted)]" aria-hidden="true" />
                          <div className="min-w-0">
                            <p className="text-xs text-[var(--foreground-subtle)]">{t('meetings.create.email_placeholder')}</p>
                            <p className="truncate text-[var(--foreground)]">{selectedCreateLead.email}</p>
                          </div>
                        </div>
                        <div className="flex items-start gap-2">
                          <Building2 className="mt-0.5 h-4 w-4 text-[var(--foreground-muted)]" aria-hidden="true" />
                          <div className="min-w-0">
                            <p className="text-xs text-[var(--foreground-subtle)]">{t('meetings.create.company_placeholder')}</p>
                            <p className="truncate text-[var(--foreground)]">{selectedCreateLead.company || t('meetings.create.not_available')}</p>
                          </div>
                        </div>
                        <div className="flex items-start gap-2">
                          <Briefcase className="mt-0.5 h-4 w-4 text-[var(--foreground-muted)]" aria-hidden="true" />
                          <div className="min-w-0">
                            <p className="text-xs text-[var(--foreground-subtle)]">{t('meetings.create.role_placeholder')}</p>
                            <p className="truncate text-[var(--foreground)]">{selectedCreateLead.job_title || t('meetings.create.not_available')}</p>
                          </div>
                        </div>
                      </div>
                    </section>
                  )}
                </div>
              ) : (
                <div className="grid gap-3 sm:grid-cols-2">
                  <input
                    type="text"
                    value={newLeadForm.name}
                    onChange={(event) => setNewLeadForm(current => ({ ...current, name: event.target.value }))}
                    className="h-10 rounded-xl border border-[var(--input-border)] bg-[var(--input)] px-3.5 text-sm text-[var(--foreground)] outline-none focus:border-[var(--ring)]"
                    placeholder={t('meetings.create.name_placeholder')}
                  />
                  <input
                    type="email"
                    required={createMeetingLeadMode === 'new'}
                    value={newLeadForm.email}
                    onChange={(event) => setNewLeadForm(current => ({ ...current, email: event.target.value }))}
                    className="h-10 rounded-xl border border-[var(--input-border)] bg-[var(--input)] px-3.5 text-sm text-[var(--foreground)] outline-none focus:border-[var(--ring)]"
                    placeholder={t('meetings.create.email_placeholder')}
                  />
                  <input
                    type="text"
                    value={newLeadForm.company}
                    onChange={(event) => setNewLeadForm(current => ({ ...current, company: event.target.value }))}
                    className="h-10 rounded-xl border border-[var(--input-border)] bg-[var(--input)] px-3.5 text-sm text-[var(--foreground)] outline-none focus:border-[var(--ring)]"
                    placeholder={t('meetings.create.company_placeholder')}
                  />
                  <input
                    type="text"
                    value={newLeadForm.role}
                    onChange={(event) => setNewLeadForm(current => ({ ...current, role: event.target.value }))}
                    className="h-10 rounded-xl border border-[var(--input-border)] bg-[var(--input)] px-3.5 text-sm text-[var(--foreground)] outline-none focus:border-[var(--ring)]"
                    placeholder={t('meetings.create.role_placeholder')}
                  />
                </div>
              )}

              <div className="mt-6 border-t border-[var(--border)] pt-5">
                <h4 className="text-xs font-semibold uppercase tracking-[0.14em] text-[var(--foreground-subtle)]">
                  {t('meetings.create.meeting_details')}
                </h4>
              </div>

              <div className="mt-5 grid gap-3 sm:grid-cols-2">
                <select
                  value={createMeetingForm.agent_id}
                  required
                  onChange={(event) => setCreateMeetingForm(current => ({ ...current, agent_id: event.target.value }))}
                  className="h-10 rounded-xl border border-[var(--input-border)] bg-[var(--input)] px-3.5 text-sm text-[var(--foreground)] outline-none focus:border-[var(--ring)]"
                >
                  <option value="">{t('meetings.create.agent_placeholder')}</option>
                  {agents.map((agent) => (
                    <option key={agent.id} value={agent.id}>{agent.name}</option>
                  ))}
                </select>
                <input
                  type="datetime-local"
                  value={createMeetingForm.scheduled_at}
                  onChange={(event) => setCreateMeetingForm(current => ({ ...current, scheduled_at: event.target.value }))}
                  className="h-10 rounded-xl border border-[var(--input-border)] bg-[var(--input)] px-3.5 text-sm text-[var(--foreground)] outline-none focus:border-[var(--ring)]"
                />
              </div>

              <div className="mt-3">
                <Textarea
                  value={createMeetingForm.notes}
                  onChange={(event) => setCreateMeetingForm(current => ({ ...current, notes: event.target.value }))}
                  rows={3}
                  placeholder={t('meetings.create.notes_placeholder')}
                />
              </div>

              <div className="mt-6 flex justify-end gap-3">
                <button
                  type="button"
                  onClick={closeCreateMeetingModal}
                  disabled={isCreatingMeeting}
                  className="rounded-xl border border-[var(--border)] px-4 py-2 text-sm text-[var(--foreground-muted)] transition-colors hover:bg-white/[0.04] hover:text-[var(--foreground)] disabled:opacity-60"
                >
                  {t('common.cancel')}
                </button>
                <Button
                  type="submit"
                  variant="primary"
                  disabled={isCreatingMeeting || !createMeetingForm.agent_id || (createMeetingLeadMode === 'existing' && !selectedCreateLeadId)}
                  loading={isCreatingMeeting}
                >
                  {isCreatingMeeting ? t('customer_settings.common.saving') : t('meetings.create.submit')}
                </Button>
              </div>
            </form>
          </div>
        </div>
      )}



      <SlideOver
        open={isModalOpen}
        onClose={() => setIsModalOpen(false)}
        width={1180}
        className="max-w-[72vw] bg-[var(--background-secondary)]"
      >
        {loadingLead ? (
          <div className="flex h-full items-center justify-center text-[var(--foreground-muted)]">
            {t('common.loading')}
          </div>
        ) : modalError ? (
          <div className="flex h-full items-center justify-center p-8 text-center text-sm text-[var(--foreground-muted)]">
            {modalError}
          </div>
        ) : modalData && selectedMeeting ? (
          <div className="grid h-full min-h-0 grid-cols-5 bg-[var(--background-secondary)]/72">
            <aside className="col-span-2 min-h-0 overflow-y-auto border-r border-[var(--border)] bg-[var(--background-secondary)]/96 p-6 custom-scrollbar">
              <h2 className="text-[24px] font-semibold tracking-[-0.02em] text-[var(--foreground)]">
                {t('meetings.preparation.title')}
              </h2>

              <div className="mt-4 rounded-[26px] border border-white/[0.08] bg-[linear-gradient(180deg,#232932_0%,#1c2128_100%)] p-4 shadow-[var(--shadow-md)]">
                <div className="mb-2 flex items-center justify-between gap-2">
                  <p className="text-sm font-semibold text-[var(--foreground)]">
                    {meetingTypeLabel}
                  </p>
                  <Badge size="sm" variant={selectedMeeting.status === 'pending_removal' ? 'warning' : 'info'}>
                    {t(`admin.meetings.statuses.${selectedMeeting.status}`)}
                  </Badge>
                </div>
                <div className="space-y-2 text-xs text-[var(--foreground-muted)]">
                  <div className="flex items-start gap-2">
                    <Clock className="mt-0.5 h-4 w-4" />
                    <span>{t('meetings.preparation.scheduled_for')}: {formatDateTime(selectedMeeting.scheduled_at)}</span>
                  </div>
                  <div className="flex items-start gap-2">
                    <CalendarCheck className="mt-0.5 h-4 w-4" />
                    <span>{t('meetings.preparation.booked_at')}: {formatDateTime(selectedMeeting.created_at)}</span>
                  </div>
                  <div className="flex items-start gap-2">
                    <Clock className="mt-0.5 h-4 w-4" />
                    <span>{t('meetings.preparation.duration')}: {selectedMeeting.duration_minutes ? t('meetings.duration_minutes_short', { count: selectedMeeting.duration_minutes }) : '-'}</span>
                  </div>
                  <div className="flex items-start gap-2">
                    <MapPin className="mt-0.5 h-4 w-4" />
                    <span>{t('meetings.preparation.location')}: {selectedMeeting.location || '-'}</span>
                  </div>
                  <div className="flex items-start gap-2">
                    <User className="mt-0.5 h-4 w-4" />
                    <span>
                      {t('meetings.preparation.assigned_to')}: {selectedMeeting.assigned_to_account?.full_name || t('meetings.assign.unassigned')}
                    </span>
                  </div>
                </div>

                <div className="mt-4 border-t border-white/[0.08] pt-4">
                  <label className="block text-xs font-semibold uppercase tracking-wide text-[var(--foreground-muted)]" htmlFor="meeting-outcome-select">
                    {t('meetings.table.outcome')}
                  </label>
                  <div className="relative mt-2">
                    <select
                      id="meeting-outcome-select"
                      value={selectedMeeting.outcome || ''}
                      disabled={!canChangeMeetingOutcome(selectedMeeting) || updatingMeetingStatusId === selectedMeeting.id}
                      onChange={(event) => {
                        const nextOutcome = event.target.value as 'positive' | 'neutral' | 'no_show'
                        if (nextOutcome) void handleSetOutcome(selectedMeeting.id, nextOutcome)
                      }}
                      className="h-10 w-full appearance-none rounded-xl border border-[var(--input-border)] bg-[var(--input)] px-3.5 pr-9 text-sm text-[var(--foreground)] outline-none focus:border-[var(--ring)] focus:ring-2 focus:ring-[rgba(53,202,222,0.12)] disabled:cursor-not-allowed disabled:opacity-60"
                      aria-label={t('meetings.change_outcome')}
                    >
                      <option value="">{t('meetings.select_outcome')}</option>
                      <option value="positive">{t('meetings.outcomes.positive')}</option>
                      <option value="neutral">{t('meetings.outcomes.neutral')}</option>
                      <option value="no_show">{t('meetings.mark_no_show')}</option>
                    </select>
                    <div className="pointer-events-none absolute inset-y-0 right-0 flex items-center px-3 text-[var(--foreground-subtle)]">
                      <ChevronDown className="h-4 w-4" aria-hidden="true" />
                    </div>
                  </div>
                </div>

                <div className="mt-4 rounded-[20px] border border-white/[0.08] bg-black/20 p-3 text-sm">
                  <div className="flex items-center justify-between gap-2">
                    <div className="flex items-center gap-2 text-[11px] font-semibold uppercase tracking-wide text-[var(--foreground-subtle)]">
                      <FileText className="h-3.5 w-3.5" aria-hidden="true" />
                      {t('meetings.preparation.notes')}
                    </div>
                    <button
                      type="button"
                      onClick={() => {
                        setMeetingNotesInput(selectedMeeting.notes || '')
                        setMeetingNotesError(null)
                        setIsEditingMeetingNotes(true)
                      }}
                      disabled={savingMeetingNotes}
                      className="inline-flex size-7 items-center justify-center rounded-full text-[var(--foreground-subtle)] transition-colors hover:bg-white/10 hover:text-[var(--foreground)] disabled:cursor-not-allowed disabled:opacity-50"
                      aria-label={t('meetings.edit_notes')}
                      title={t('meetings.edit_notes')}
                    >
                      <Pencil className="h-3.5 w-3.5" aria-hidden="true" />
                    </button>
                  </div>
                  {isEditingMeetingNotes ? (
                    <div className="mt-2">
                      <Textarea
                        value={meetingNotesInput}
                        onChange={(event) => setMeetingNotesInput(event.target.value)}
                        onKeyDown={handleMeetingNotesKeyDown}
                        rows={3}
                        disabled={savingMeetingNotes}
                        placeholder={t('meetings.create.notes_placeholder')}
                        autoFocus
                      />
                      <div className="mt-2 flex items-center justify-between gap-2">
                        <p className="text-xs text-[var(--foreground-subtle)]">
                          {savingMeetingNotes
                            ? t('common.loading')
                            : t('meetings.notes_enter_to_save')}
                        </p>
                        <button
                          type="button"
                          onClick={() => void handleSaveMeetingNotes()}
                          disabled={savingMeetingNotes || meetingNotesInput === (selectedMeeting.notes || '')}
                          className="rounded-lg border border-white/[0.08] px-2.5 py-1 text-xs font-medium text-[var(--foreground)] transition-colors hover:bg-white/10 disabled:cursor-not-allowed disabled:opacity-50"
                        >
                          {t('common.save')}
                        </button>
                      </div>
                      {meetingNotesError && (
                        <p className="mt-2 text-xs text-red-400">{meetingNotesError}</p>
                      )}
                    </div>
                  ) : (
                    <p className="mt-2 whitespace-pre-wrap text-[var(--foreground)]">
                      {selectedMeeting.notes || t('meetings.no_notes')}
                    </p>
                  )}
                </div>

                {selectedMeeting.removal_comment && (
                  <div className="mt-4 rounded-[20px] border border-amber-500/25 bg-amber-500/10 p-3 text-sm">
                    <div className="text-[11px] font-semibold uppercase tracking-wide text-amber-300">
                      {t('meetings.preparation.removal_comment')}
                    </div>
                    <p className="mt-2 whitespace-pre-wrap text-[var(--foreground)]">
                      {selectedMeeting.removal_comment}
                    </p>
                  </div>
                )}

                {canEditMeetingTime(selectedMeeting) && (
                  <div className="mt-4 border-t border-white/[0.08] pt-4">
                    <label className="block text-xs font-semibold uppercase tracking-wide text-[var(--foreground-muted)]" htmlFor="meeting-time-input">
                      {t('meetings.meeting_time')}
                    </label>
                    <div className="mt-2 flex items-center gap-2">
                      <input
                        id="meeting-time-input"
                        type="datetime-local"
                        value={meetingTimeInput}
                        onChange={(event) => setMeetingTimeInput(event.target.value)}
                        className="h-10 w-full rounded-xl border border-[var(--input-border)] bg-[var(--input)] px-3.5 text-sm text-[var(--foreground)] outline-none focus:border-[var(--ring)] focus:ring-2 focus:ring-[rgba(53,202,222,0.12)]"
                      />
                      <button
                        type="button"
                        onClick={handleSaveMeetingTime}
                        disabled={!canSaveMeetingTime || savingMeetingTime}
                        className="inline-flex h-10 items-center rounded-xl border border-[var(--border)] px-3.5 text-sm text-[var(--foreground)] transition-colors hover:bg-white/[0.05] disabled:cursor-not-allowed disabled:opacity-50"
                      >
                        {savingMeetingTime
                          ? t('common.loading')
                          : t('common.save')}
                      </button>
                    </div>
                    {meetingTimeError && (
                      <p className="mt-2 text-xs text-red-400">{meetingTimeError}</p>
                    )}
                  </div>
                )}
              </div>

              <div className="mt-6 rounded-[24px] border border-[var(--border)] bg-[var(--card)] p-4 shadow-[var(--shadow-sm)]">
                <div className="mb-3 text-xs font-semibold uppercase tracking-[0.18em] text-[var(--foreground-subtle)]">
                  {t('meetings.preparation.lead_snapshot')}
                </div>
                <div className="space-y-3 text-sm">
                <div className="flex items-start gap-2">
                  <User className="mt-0.5 h-4 w-4 text-[var(--foreground-muted)]" />
                  <div>
                    <p className="text-[var(--foreground)]">{modalData.display_name || modalData.email}</p>
                    <p className="text-xs text-[var(--foreground-muted)]">{modalData.job_title || '-'}</p>
                  </div>
                </div>
                <div className="flex items-start gap-2">
                  <Mail className="mt-0.5 h-4 w-4 text-[var(--foreground-muted)]" />
                  <div>
                    <p className="text-[var(--foreground)]">{modalData.email}</p>
                    <p className="text-xs text-[var(--foreground-muted)]">{modalData.timezone || '-'}</p>
                  </div>
                </div>
                <div className="flex items-start gap-2">
                  <Building2 className="mt-0.5 h-4 w-4 text-[var(--foreground-muted)]" />
                  <div>
                    <p className="text-[var(--foreground)]">{modalData.company || '-'}</p>
                    <p className="text-xs text-[var(--foreground-muted)]">{selectedMeeting.agent.name}</p>
                  </div>
                </div>
                </div>
              </div>

              <div className="mt-6 space-y-4">
                <div className="rounded-[22px] border border-[var(--border)] bg-[var(--card)] p-4 shadow-[var(--shadow-sm)]">
                  <div className="mb-2 flex items-center gap-2">
                    <User className="h-4 w-4 text-[var(--foreground-muted)]" />
                    <p className="text-xs font-semibold uppercase tracking-wide text-[var(--foreground-muted)]">
                      {t('meetings.preparation.lead_summary')}
                    </p>
                  </div>
                  <div className="space-y-2 text-sm">
                    <p className="text-[var(--foreground)]">{modalData.display_name || modalData.email}</p>
                    <p className="text-[var(--foreground-muted)]">{modalData.job_title || '-'}</p>
                    <p className="text-[var(--foreground-muted)]">{modalData.location || '-'}</p>
                    {modalData.blacklisted && (
                      <p className="text-xs text-red-400">
                        {t('meetings.preparation.blacklisted')}{modalData.blacklist_reason ? `: ${modalData.blacklist_reason}` : ''}
                      </p>
                    )}
                  </div>
                </div>

                <div className="rounded-[22px] border border-[var(--border)] bg-[var(--card)] p-4 shadow-[var(--shadow-sm)]">
                  <div className="mb-2 flex items-center gap-2">
                    <Building2 className="h-4 w-4 text-[var(--foreground-muted)]" />
                    <p className="text-xs font-semibold uppercase tracking-wide text-[var(--foreground-muted)]">
                      {t('meetings.preparation.company_summary')}
                    </p>
                  </div>
                  <p className="text-sm text-[var(--foreground)]">{modalData.company || '-'}</p>
                  {modalData.company_website && (
                    <a
                      href={modalData.company_website.startsWith('http') ? modalData.company_website : `https://${modalData.company_website}`}
                      target="_blank"
                      rel="noreferrer"
                      className="mt-2 inline-flex items-center gap-1 text-xs text-[var(--accent)] hover:underline"
                    >
                      <Globe className="h-3.5 w-3.5" />
                      {modalData.company_website}
                      <ExternalLink className="h-3 w-3" />
                    </a>
                  )}
                  {modalData.company_website_content && (() => {
                    const { visibleContent, hiddenCharacters, isTruncated } = truncateScrapedContent(modalData.company_website_content)

                    return (
                      <>
                        <p className="mt-2 whitespace-pre-wrap text-xs text-[var(--foreground-muted)]">
                          {visibleContent}
                        </p>
                        {isTruncated && (
                          <p className="mt-1 text-[11px] text-[var(--foreground-subtle)]">
                            {t('meetings.preparation.scraped_content_hidden', { count: hiddenCharacters })}
                          </p>
                        )}
                      </>
                    )
                  })()}
                </div>

                <div className="rounded-[22px] border border-[var(--border)] bg-[var(--card)] p-4 shadow-[var(--shadow-sm)]">
                  <div className="mb-2 flex items-center gap-2">
                    <Linkedin className="h-4 w-4 text-[var(--foreground-muted)]" />
                    <p className="text-xs font-semibold uppercase tracking-wide text-[var(--foreground-muted)]">
                      {t('meetings.preparation.linkedin_profile')}
                    </p>
                  </div>
                  {modalData.linkedin_url ? (
                    <a
                      href={modalData.linkedin_url}
                      target="_blank"
                      rel="noreferrer"
                      className="inline-flex items-center gap-1 text-xs text-[var(--accent)] hover:underline"
                    >
                      {t('meetings.preparation.view_linkedin')}
                      <ExternalLink className="h-3 w-3" />
                    </a>
                  ) : (
                    <p className="text-xs text-[var(--foreground-muted)]">{t('meetings.preparation.no_linkedin')}</p>
                  )}
                  {modalData.linkedin_headline && (
                    <p className="mt-2 text-xs text-[var(--foreground)]">{modalData.linkedin_headline}</p>
                  )}
                  {modalData.linkedin_summary && (
                    <p className="mt-2 whitespace-pre-wrap text-xs text-[var(--foreground-muted)]">{modalData.linkedin_summary}</p>
                  )}
                </div>

                <div className="rounded-[22px] border border-[var(--border)] bg-[var(--card)] p-4 shadow-[var(--shadow-sm)]">
                  <div className="mb-2 flex items-center gap-2">
                    <Brain className="h-4 w-4 text-[var(--foreground-muted)]" />
                    <p className="text-xs font-semibold uppercase tracking-wide text-[var(--foreground-muted)]">
                      {t('meetings.preparation.enrichment')}
                    </p>
                  </div>
                  <div className="space-y-1 text-xs text-[var(--foreground-muted)]">
                    <p>{t('meetings.preparation.disc_label')}: <span className="text-[var(--foreground)]">{modalData.disc_profile || '-'}</span></p>
                    {modalData.disc_profile_data?.confidence && (
                      <p>{t('meetings.preparation.confidence_label')}: <span className="text-[var(--foreground)]">{Math.round(modalData.disc_profile_data.confidence * 100)}%</span></p>
                    )}
                    <p>{t('meetings.preparation.linkedin_posts_label')}: <span className="text-[var(--foreground)]">{modalData.linkedin_posts?.length || 0}</span></p>
                  </div>
                  {modalData.custom_fields && Object.keys(modalData.custom_fields).length > 0 && (
                    <div className="mt-2 border-t border-[var(--border)] pt-2 space-y-1">
                      {Object.entries(modalData.custom_fields).slice(0, 6).map(([key, value]) => (
                        <p key={key} className="text-xs text-[var(--foreground-muted)]">
                          {key.replace(/_/g, ' ')}: <span className="text-[var(--foreground)]">{typeof value === 'object' ? JSON.stringify(value) : String(value)}</span>
                        </p>
                      ))}
                    </div>
                  )}
                </div>
              </div>
            </aside>

            <section className="col-span-3 min-h-0 overflow-y-auto bg-[var(--background)]/45 p-6 custom-scrollbar">
              {modalData.meeting_declined_comments.length > 0 && (
                <div className="mb-6">
                  <h3 className="mb-3 text-sm font-semibold uppercase tracking-wide text-[var(--foreground-muted)]">
                    {t('meetings.preparation.declined_comments')}
                  </h3>

                  <div className="space-y-3">
                    {modalData.meeting_declined_comments.map((comment) => (
                      <article key={comment.id} className="rounded-[22px] border border-[var(--border)] bg-[var(--card)] p-4 shadow-[var(--shadow-sm)]">
                        <div className="mb-2 flex flex-wrap items-center gap-2 text-xs">
                          <Badge size="sm" variant="warning">
                            {t('meetings.preparation.declined_comment_label')}
                          </Badge>
                          <span className="text-[var(--foreground-muted)]">{formatDateTime(comment.created_at)}</span>
                        </div>
                        <p className="text-xs text-[var(--foreground-muted)]">{comment.account.full_name}</p>
                        <p className="mt-2 whitespace-pre-wrap text-sm text-[var(--foreground)]">{comment.body}</p>
                      </article>
                    ))}
                  </div>
                </div>
              )}

              <div className="sticky top-0 z-10 -mx-6 mb-6 border-b border-[var(--border)] bg-[var(--background)]/92 px-6 pb-4 pt-1 backdrop-blur-sm">
              <h3 className="text-sm font-semibold uppercase tracking-[0.18em] text-[var(--foreground-muted)]">
                {t('meetings.preparation.message_history')}
              </h3>
              <p className="mt-2 text-sm text-[var(--foreground-subtle)]">
                {t('meetings.preparation.message_history_description')}
              </p>
              </div>

              {timeline.length === 0 ? (
                <div className="rounded-[24px] border border-dashed border-[var(--border)] bg-[var(--card)] px-4 py-10 text-center text-sm text-[var(--foreground-muted)]">
                  {t('customer.agents.modal.messages.empty')}
                </div>
              ) : (
                <div className="space-y-4">
                  {timeline.map((entry) => (
                    <article key={entry.key} className="rounded-[24px] border border-[var(--border)] bg-[var(--card)] p-4 shadow-[var(--shadow-sm)]">
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
                      <p className="mt-2 whitespace-pre-wrap text-sm text-[var(--foreground)]">{entry.body || t('customer.agents.modal.messages.empty_body')}</p>
                    </article>
                  ))}
                </div>
              )}
            </section>
          </div>
        ) : null}
      </SlideOver>

      {removeMeetingCandidate && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm p-4">
          <div className="w-full max-w-md rounded-[28px] border border-white/[0.08] bg-[var(--background-secondary)] shadow-[0_28px_60px_rgba(0,0,0,0.36)]">
            <div
              role="dialog"
              aria-modal="true"
              aria-labelledby="remove-meeting-modal-title"
              aria-describedby="remove-meeting-modal-description"
            >
              <div className="border-b border-[var(--border)] px-7 py-6">
                <h2 id="remove-meeting-modal-title" className="text-lg font-semibold text-[var(--foreground)]">
                  {t('meetings.remove_modal.title')}
                </h2>
                <p id="remove-meeting-modal-description" className="mt-2 text-sm text-[var(--foreground-muted)]">
                  {t('meetings.remove_modal.description')}
                </p>
              </div>
              <div className="px-7 py-6">
                <Textarea
                  id="remove-meeting-comment"
                  label={t('meetings.remove_modal.comment_label')}
                  placeholder={t('meetings.remove_modal.comment_placeholder')}
                  value={removeMeetingComment}
                  onChange={(event) => setRemoveMeetingComment(event.target.value)}
                  maxLength={1000}
                  autoResize
                />
                <div className="mt-2 flex items-center justify-between gap-3 text-xs text-[var(--foreground-subtle)]">
                  <span>{t('meetings.remove_modal.comment_help')}</span>
                  <span>{t('meetings.remove_modal.character_count', { count: removeMeetingComment.length, max: 1000 })}</span>
                </div>
                {removeMeetingError && (
                  <p className="mt-3 text-xs text-red-400">{removeMeetingError}</p>
                )}
              </div>
              <div className="flex justify-end gap-3 border-t border-[var(--border)] bg-[var(--background-secondary)]/94 px-7 py-5">
                <button
                  type="button"
                  onClick={() => {
                    setRemoveMeetingCandidate(null)
                    setRemoveMeetingComment('')
                    setRemoveMeetingError(null)
                  }}
                  className="inline-flex items-center rounded-xl border border-[var(--border)] bg-transparent px-4 py-2 text-sm font-medium text-[var(--foreground-muted)] transition-colors hover:bg-white/[0.05] hover:text-[var(--foreground)]"
                >
                {t('common.cancel')}
                </button>
                <button
                  type="button"
                  onClick={async () => {
                    const meeting = removeMeetingCandidate
                    if (!meeting) return

                    const succeeded = await handleRequestRemoval(meeting)
                    if (succeeded) {
                      setRemoveMeetingCandidate(null)
                      setRemoveMeetingComment('')
                      setRemoveMeetingError(null)
                    }
                  }}
                  disabled={requestingRemovalId === removeMeetingCandidate.id}
                  className="inline-flex items-center rounded-xl border border-amber-500/25 bg-amber-500/12 px-4 py-2 text-sm font-medium text-amber-300 disabled:cursor-not-allowed disabled:opacity-60"
                >
                  {requestingRemovalId === removeMeetingCandidate.id
                    ? t('common.loading')
                    : t('meetings.request_removal')}
                </button>
              </div>
            </div>
          </div>
        </div>
      )}

      {editMeetingCandidate && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm p-4">
          <div className="w-full max-w-md rounded-[28px] border border-white/[0.08] bg-[var(--background-secondary)] shadow-[0_28px_60px_rgba(0,0,0,0.36)]">
            <div
              role="dialog"
              aria-modal="true"
              aria-labelledby="edit-meeting-time-modal-title"
              aria-describedby="edit-meeting-time-modal-description"
            >
              <div className="border-b border-[var(--border)] px-7 py-6">
                <h2 id="edit-meeting-time-modal-title" className="text-lg font-semibold text-[var(--foreground)]">
                  {editMeetingCandidate.scheduled_at
                  ? t('meetings.edit_time')
                  : t('meetings.set_time')}
                </h2>
                <p id="edit-meeting-time-modal-description" className="mt-2 text-sm text-[var(--foreground-muted)]">
                  {getLeadName(editMeetingCandidate.lead)}
                </p>
              </div>
              <div className="px-7 py-6">
                <label className="block text-xs font-semibold uppercase tracking-wide text-[var(--foreground-muted)]" htmlFor="quick-edit-meeting-time-input">
                {t('meetings.table.meeting_date_time')}
                </label>
                <input
                  id="quick-edit-meeting-time-input"
                  type="datetime-local"
                  value={quickEditMeetingTimeInput}
                  onChange={(event) => setQuickEditMeetingTimeInput(event.target.value)}
                    className="mt-2 h-10 w-full rounded-xl border border-[var(--input-border)] bg-[var(--input)] px-3.5 text-sm text-[var(--foreground)] outline-none focus:border-[var(--ring)] focus:ring-2 focus:ring-[rgba(53,202,222,0.12)]"
                />
                {quickEditMeetingTimeError && (
                  <p className="mt-2 text-xs text-red-400">{quickEditMeetingTimeError}</p>
                )}
              </div>
              <div className="flex justify-end gap-3 border-t border-[var(--border)] bg-[var(--background-secondary)]/94 px-7 py-5">
                <button
                  type="button"
                  onClick={() => setEditMeetingCandidate(null)}
                  className="inline-flex items-center rounded-xl border border-[var(--border)] bg-transparent px-4 py-2 text-sm font-medium text-[var(--foreground-muted)] transition-colors hover:bg-white/[0.05] hover:text-[var(--foreground)]"
                >
                {t('common.cancel')}
                </button>
                <button
                  type="button"
                  onClick={() => {
                    void handleSaveQuickEditMeetingTime()
                  }}
                  disabled={!canSaveQuickEditMeetingTime || savingQuickEditMeetingTime}
                  className="inline-flex items-center rounded-xl border border-[var(--accent)]/20 bg-[var(--accent)]/12 px-4 py-2 text-sm font-medium text-[var(--foreground)] disabled:cursor-not-allowed disabled:opacity-60"
                >
                  {savingQuickEditMeetingTime
                    ? t('common.loading')
                    : t('common.save')}
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </AuthenticatedLayout>
  )
}
