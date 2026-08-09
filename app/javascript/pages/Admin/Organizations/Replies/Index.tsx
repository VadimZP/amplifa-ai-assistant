import { useState, useRef, useEffect } from 'react'
import { createPortal } from 'react-dom'
import { router, usePage } from '@inertiajs/react'
import { 
  Inbox, 
  MessageCircle, 
  Loader2,
  ChevronLeft,
  ChevronDown,
  AlertCircle,
  Check,
  Filter
} from 'lucide-react'
import OrganizationTabLayout from '../../../../components/Admin/OrganizationTabLayout'
import AuthenticatedLayout from '../../../../layouts/AuthenticatedLayout'
import ConversationCard from '../../../../components/ConversationCard'
import ThreadMessage from '../../../../components/ThreadMessage'
import LeadSidebar from '../../../../components/LeadSidebar'
import { Button } from '../../../../components/ui/Button'
import { SearchInput } from '../../../../components/ui/SearchInput'
import { Badge } from '../../../../components/ui/Badge'
import { t } from '../../../../lib/i18n'
import { toast } from '../../../../components/ui/Toaster'
import { useActionCableChannel } from '../../../../lib/useActionCableChannel'

interface MailPollingEvent {
  event: 'started' | 'complete' | 'no_mailboxes' | 'refresh'
  mailbox_count?: number
  failure_count?: number
  mailbox_id?: number
  new_replies_count?: number
}

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
  agent_name?: string | null
}

type InterestStatus = Conversation['interest_status']

const MANUALLY_EDITABLE_INTEREST_STATUSES: InterestStatus[] = ['interested', 'meeting_request', 'not_interested', 'wrong_person']

const normalizeSearchValue = (value?: string | null) => (value || '').normalize('NFC')

const getInterestStatusConfig = (interestStatus: InterestStatus) => {
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

const interestStatusConfirmationMessage = ({
  currentStatus,
  nextStatus,
  isAmplifaAdmin,
}: {
  currentStatus: InterestStatus
  nextStatus: Exclude<InterestStatus, null>
  isAmplifaAdmin: boolean
}) => {
  if (nextStatus === 'meeting_request' && currentStatus !== 'meeting_request') {
    return 'This will create a meeting associated with this lead. Are you sure?'
  }

  if (currentStatus === 'meeting_request' && nextStatus !== 'meeting_request') {
    return isAmplifaAdmin
      ? 'This will remove the meeting associated with this lead. Are you sure?'
      : 'This will request removal of the meeting. The meeting will be marked Pending Removal for admin review. Continue?'
  }

  return null
}

interface Message {
  id: number
  type: 'incoming' | 'outgoing'
  source: 'generated_message' | 'reply' | 'sent_reply'
  from: string
  subject: string
  to_addresses?: string[] | null
  cc_addresses?: string[] | null
  body_plain: string
  body_html: string | null
  message_at: string
  is_bounce: boolean
  is_out_of_office: boolean
}

interface SelectedDetail {
  conversation: Conversation
  thread: Message[]
  lead: any
  mailbox: any
  sender: any
}

interface SenderOption {
  id: number
  name: string
  email: string
}

interface ReplyTypeOption {
  value: string
  label: string
  count: number
  dotClassName: string
}

interface Props {
  auth: { account: any }
  organization: { id: number; name: string; ai_reply_agent_enabled: boolean }
  conversations: Conversation[]
  filters: {
    status: string
    mailbox_id?: string
    agent_id?: string
    unread_only?: string
    search?: string
    reply_type?: string
    sender_id?: string
  }
  sender_options?: SenderOption[]
  stats: {
    total: number
    open: number
    unread: number
    snoozed: number
    closed: number
    unassigned: number
    bounced: number
    out_of_office: number
    human: number
    interested: number
    meeting_request: number
    not_interested: number
    wrong_person: number
  }
  mailbox_status: {
    last_polled_at: string | null
    status: 'ok' | 'some_errors' | 'no_mailboxes'
    mailbox_count: number
    error_count: number
  }
  pagination: {
    current_page: number
    total_pages: number
    total_count: number
    per_page: number
  }
  current_tab: string
  selected_id: number | null
  selected_detail: SelectedDetail | null
  auto_open_composer?: boolean
  return_to?: string | null
  flash?: { notice?: string; alert?: string }
  layout_mode?: 'tabs' | 'full'
  base_path?: string
  reply_filter_menu_enabled?: boolean
  show_unassigned_link?: boolean
}

export default function Index({ 
  auth, 
  organization, 
  conversations, 
  filters, 
  stats, 
  sender_options = [],
  mailbox_status,
  pagination, 
  current_tab, 
  selected_id,
  selected_detail,
  return_to = null,
  flash,
  layout_mode = 'tabs',
  base_path,
  reply_filter_menu_enabled = false,
  show_unassigned_link = true
}: Props) {
  const SEARCH_DEBOUNCE_MS = 300
  const [checkingMail, setCheckingMail] = useState(false)
  const [loadingId, setLoadingId] = useState<number | null>(null)
  const [updatingInterestStatus, setUpdatingInterestStatus] = useState(false)
  const [isFilterMenuOpen, setIsFilterMenuOpen] = useState(false)
  const [filterButtonRect, setFilterButtonRect] = useState<DOMRect | null>(null)
  const [searchInput, setSearchInput] = useState(normalizeSearchValue(filters.search))
  const messagesEndRef = useRef<HTMLDivElement>(null)
  const threadContainerRef = useRef<HTMLDivElement>(null)
  const searchInputRef = useRef<HTMLInputElement>(null)
  const filterButtonRef = useRef<HTMLButtonElement>(null)
  const searchDebounceTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const lastSubmittedSearchRef = useRef(normalizeSearchValue(filters.search))
  const toastIdRef = useRef<string | number | null>(null)

  const { props } = usePage<{ csrf_token?: string }>()
  const basePath = base_path || `/admin/organizations/${organization.id}/replies`

  const reloadConversations = () => {
    router.reload({
      only: ['conversations', 'stats', 'mailbox_status', 'selected_detail', 'auto_open_composer'],
    })
  }

  useActionCableChannel<MailPollingEvent>(
    { channel: 'MailPollingChannel', organization_id: organization.id },
    {
      received: (data) => {
        if (data.event === 'started') {
          return
        }

        if (data.event === 'refresh') {
          if (!checkingMail) {
            reloadConversations()
          }
          return
        }

        if (data.event === 'complete') {
          const hasErrors = data.failure_count && data.failure_count > 0
          if (hasErrors) {
            toast.warning(t('admin.organizations.replies.mail_check_complete_with_errors'), { id: toastIdRef.current ?? undefined })
          } else {
            toast.success(t('admin.organizations.replies.mail_check_complete'), { id: toastIdRef.current ?? undefined })
          }
          setCheckingMail(false)
          toastIdRef.current = null

          reloadConversations()
          return
        }

        if (data.event === 'no_mailboxes') {
          toast.error(t('admin.organizations.replies.no_active_mailboxes'), { id: toastIdRef.current ?? undefined })
          setCheckingMail(false)
          toastIdRef.current = null
          return
        }
      },
    }
  )

  useEffect(() => {
    if (selected_detail?.thread) {
      setTimeout(() => {
        messagesEndRef.current?.scrollIntoView({ behavior: 'auto' })
      }, 0)
    }
  }, [selected_detail])

  useEffect(() => {
    const nextSearch = normalizeSearchValue(filters.search)
    if (document.activeElement === searchInputRef.current && nextSearch !== searchInput) {
      return
    }

    setSearchInput(nextSearch)
    lastSubmittedSearchRef.current = nextSearch
  }, [filters.search, searchInput])

  useEffect(() => {
    if (!isFilterMenuOpen) return

    const updatePosition = () => {
      setFilterButtonRect(filterButtonRef.current?.getBoundingClientRect() ?? null)
    }
    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') setIsFilterMenuOpen(false)
    }

    updatePosition()
    window.addEventListener('resize', updatePosition)
    window.addEventListener('scroll', updatePosition, true)
    window.addEventListener('keydown', handleKeyDown)

    return () => {
      window.removeEventListener('resize', updatePosition)
      window.removeEventListener('scroll', updatePosition, true)
      window.removeEventListener('keydown', handleKeyDown)
    }
  }, [isFilterMenuOpen])

  useEffect(() => {
    if (searchDebounceTimeoutRef.current) {
      clearTimeout(searchDebounceTimeoutRef.current)
    }

    const normalizedSearchInput = normalizeSearchValue(searchInput)

    if (normalizedSearchInput === lastSubmittedSearchRef.current) {
      return
    }

    searchDebounceTimeoutRef.current = setTimeout(() => {
      lastSubmittedSearchRef.current = normalizedSearchInput

      router.get(
        basePath,
        { ...filters, search: normalizedSearchInput || undefined, page: 1, selected_id, return_to: return_to || undefined },
        {
          preserveState: true,
          preserveScroll: true,
          replace: true,
          only: ['conversations', 'filters', 'pagination', 'auto_open_composer'],
        }
      )
    }, SEARCH_DEBOUNCE_MS)

    return () => {
      if (searchDebounceTimeoutRef.current) {
        clearTimeout(searchDebounceTimeoutRef.current)
      }
    }
  }, [
    basePath,
    filters,
    searchInput,
    selected_id,
  ])

  const handleInterestStatusChange = async (event: React.ChangeEvent<HTMLSelectElement>) => {
    if (!selected_detail || updatingInterestStatus) return

    const currentStatus = selected_detail.conversation.interest_status
    const nextStatus = event.target.value as Exclude<InterestStatus, null>
    if (!MANUALLY_EDITABLE_INTEREST_STATUSES.includes(nextStatus)) return
    if (nextStatus === currentStatus) return

    const isAmplifaAdmin = auth.account['amplifa_admin?'] === true
    const confirmationMessage = interestStatusConfirmationMessage({
      currentStatus,
      nextStatus,
      isAmplifaAdmin,
    })

    if (confirmationMessage && !window.confirm(confirmationMessage)) return

    setUpdatingInterestStatus(true)
    const toastId = toast.loading(t('admin.replies.updating_interest_status', { defaultValue: 'Updating interest status...' }))

    try {
      const csrfToken = props.csrf_token || document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content

      const response = await fetch(`${basePath}/${selected_detail.conversation.id}/update_interest_status`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          ...(csrfToken ? { 'X-CSRF-Token': csrfToken } : {}),
        },
        body: JSON.stringify({ interest_status: nextStatus })
      })

      const data = await response.json().catch(() => ({}))
      if (!response.ok) {
        throw new Error(data?.error || t('admin.replies.interest_status_update_failed', { defaultValue: 'Failed to update interest status' }))
      }

      toast.success(t('admin.replies.interest_status_updated', { defaultValue: 'Interest status updated' }), { id: toastId })
      reloadConversations()
    } catch (error) {
      const message = error instanceof Error ? error.message : t('admin.replies.interest_status_update_failed', { defaultValue: 'Failed to update interest status' })
      toast.error(message, { id: toastId })
    } finally {
      setUpdatingInterestStatus(false)
    }
  }

  const handleSearchChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setSearchInput(normalizeSearchValue(e.target.value))
  }

  const handlePageChange = (page: number) => {
    router.get(
      basePath,
      { ...filters, page, selected_id, return_to: return_to || undefined },
      { preserveState: true }
    )
  }

  const handleReplyFilterChange = (nextFilters: { reply_type?: string; sender_id?: string }) => {
    setIsFilterMenuOpen(false)

    router.get(
      basePath,
      { ...filters, ...nextFilters, page: 1, selected_id, return_to: return_to || undefined },
      { preserveState: true, replace: true }
    )
  }

  const handleSelectConversation = (id: number) => {
    if (id === selected_id) return
    
    setLoadingId(id)
    router.get(
      basePath,
      { ...filters, page: pagination.current_page, selected_id: id, return_to: return_to || undefined },
      { 
        preserveState: true, 
        preserveScroll: true,
        only: ['selected_detail', 'selected_id'],
        onFinish: () => setLoadingId(null)
      }
    )
  }

  const handleCloseDetail = () => {
    if (return_to) {
      router.visit(return_to)
      return
    }

    router.get(
      basePath,
      { ...filters, selected_id: null },
      { preserveState: true, preserveScroll: true }
    )
  }

  const renderPagination = () => {
    if (pagination.total_pages <= 1) return null
    
    const pages: Array<{ key: string; value: number | '...' }> = []
    for (let i = 1; i <= pagination.total_pages; i++) {
      if (
        i === 1 || 
        i === pagination.total_pages || 
        (i >= pagination.current_page - 1 && i <= pagination.current_page + 1)
      ) {
        pages.push({ key: `page-${i}`, value: i })
      } else if (
        (i === pagination.current_page - 2 && i > 1) || 
        (i === pagination.current_page + 2 && i < pagination.total_pages)
      ) {
        const key = i < pagination.current_page ? 'ellipsis-left' : 'ellipsis-right'
        pages.push({ key, value: '...' })
      }
    }

    return (
      <div className="flex justify-center py-4 gap-2 border-t border-[var(--border)] bg-[var(--background)] shrink-0">
        {pages.map((page) => (
          <button
            key={page.key}
            type="button"
            onClick={() => typeof page.value === 'number' && handlePageChange(page.value)}
            disabled={page.value === '...'}
            className={`
              w-7 h-7 rounded text-xs font-medium transition-colors
              ${page.value === pagination.current_page 
                ? 'bg-[var(--accent)] text-white' 
                : page.value === '...' 
                  ? 'text-[var(--foreground-muted)] cursor-default' 
                  : 'text-[var(--foreground-muted)] hover:bg-[var(--card-hover)] hover:text-[var(--foreground)]'
              }
            `}
          >
            {page.value}
          </button>
        ))}
      </div>
    )
  }

  const leadName = selected_detail?.conversation.lead 
    ? [selected_detail.conversation.lead.first_name, selected_detail.conversation.lead.last_name].filter(Boolean).join(' ') || selected_detail.conversation.lead.email
    : ''
  const headerStatusBadge = selected_detail?.conversation
    ? selected_detail.conversation.has_bounce
      ? 'bounced'
      : selected_detail.conversation.has_out_of_office
        ? 'ooo'
        : selected_detail.conversation.awaiting_reply
          ? 'reply-now'
          : null
    : null

  const headerInterestStatus = getInterestStatusConfig(selected_detail?.conversation?.interest_status ?? null)

  const canManuallyChangeInterestStatus = Boolean(selected_detail?.conversation)

  const replyTypeCounts = {
    all: stats.human ?? 0,
    interested: stats.interested ?? 0,
    meetingRequest: stats.meeting_request ?? 0,
    notInterested: stats.not_interested ?? 0,
    wrongPerson: stats.wrong_person ?? 0,
    outOfOffice: stats.out_of_office ?? 0,
  }

  const replyTypeOptions: ReplyTypeOption[] = [
    { value: 'all', label: t('admin.organizations.replies.all', { defaultValue: 'All' }), count: replyTypeCounts.all, dotClassName: 'bg-[var(--foreground-muted)]' },
    { value: 'meeting_request', label: t('admin.organizations.replies.meeting_request', { defaultValue: 'Meeting Request' }), count: replyTypeCounts.meetingRequest, dotClassName: 'bg-[var(--success)]' },
    { value: 'interested', label: t('admin.organizations.replies.interested', { defaultValue: 'Interested' }), count: replyTypeCounts.interested, dotClassName: 'bg-sky-400' },
    { value: 'not_interested', label: t('admin.organizations.replies.not_interested', { defaultValue: 'Not Interested' }), count: replyTypeCounts.notInterested, dotClassName: 'bg-[var(--error)]' },
    { value: 'wrong_person', label: t('admin.organizations.replies.wrong_person', { defaultValue: 'Wrong Person' }), count: replyTypeCounts.wrongPerson, dotClassName: 'bg-blue-400' },
    { value: 'ooo', label: t('admin.organizations.replies.ooo'), count: replyTypeCounts.outOfOffice, dotClassName: 'bg-[var(--warning)]' },
  ]
  const activeReplyType = filters.reply_type || 'all'
  const activeSenderId = filters.sender_id || 'all'
  const activeReplyTypeLabel = replyTypeOptions.find((option) => option.value === activeReplyType)?.label || replyTypeOptions[0].label
  const activeSenderLabel = activeSenderId === 'all'
    ? t('admin.organizations.replies.filter_menu.all_senders')
    : sender_options.find((sender) => sender.id.toString() === activeSenderId)?.name || t('admin.organizations.replies.filter_menu.all_senders')
  const filterSummary = activeSenderId === 'all'
    ? activeReplyTypeLabel
    : `${activeReplyTypeLabel} · ${activeSenderLabel}`

  const content = (
    <div className="flex h-full overflow-hidden bg-[var(--background)]">
        <aside className="flex h-full w-[22rem] shrink-0 flex-col border-r border-[var(--border)] bg-[var(--background-secondary)]/88">
          <div className="z-10 space-y-3 border-b border-[var(--border)] bg-[var(--background-secondary)]/92 p-4 backdrop-blur-sm">
            <div className="flex justify-between items-center">
              <div className="flex items-center gap-2 min-w-0">
                <h2 className="font-semibold text-[var(--foreground)]">{t('admin.organizations.replies.title')}</h2>
                {stats.unread > 0 && (
                  <Badge
                    size="sm"
                    aria-live="polite"
                    className="rounded-full border-red-500/30 bg-red-500/15 text-red-400 text-[10px] tracking-wide gap-1.5"
                  >
                    <span className="inline-flex size-1.5 rounded-full bg-red-400" />
                    {stats.unread}
                  </Badge>
                )}
              </div>
              <div className="flex items-center gap-2">
                {mailbox_status.last_polled_at && (
                  <span className="text-[10px] text-[var(--foreground-muted)]">
                    {new Date(mailbox_status.last_polled_at).toLocaleTimeString()}
                  </span>
                )}
              </div>
            </div>
            
            <SearchInput
              ref={searchInputRef}
              placeholder={t('admin.organizations.replies.search_placeholder')}
              value={searchInput}
              onChange={handleSearchChange}
              className="h-9 text-sm w-full"
            />

            <div className="flex items-end justify-between gap-3">
              <div className="flex-1 min-w-0">
                {reply_filter_menu_enabled ? (
                  <>
                    <span className="block text-xs font-medium text-[var(--foreground-muted)] mb-1">
                      {t('admin.organizations.replies.filter_menu.label')}
                    </span>
                    <button
                      ref={filterButtonRef}
                      type="button"
                      onClick={() => setIsFilterMenuOpen((open) => !open)}
                      className="flex w-full items-center justify-between gap-3 rounded-xl border border-[var(--input-border)] bg-[var(--input)] px-3 py-2 text-left text-xs text-[var(--foreground)] transition-all hover:border-[var(--border)] focus:border-transparent focus:outline-none focus:ring-2 focus:ring-[var(--ring)]"
                      aria-haspopup="menu"
                      aria-expanded={isFilterMenuOpen}
                    >
                      <span className="flex min-w-0 items-center gap-2">
                        <Filter className="size-3.5 shrink-0 text-[var(--foreground-muted)]" aria-hidden="true" />
                        <span className="truncate">{filterSummary}</span>
                      </span>
                      <ChevronDown className="size-3.5 shrink-0 text-[var(--foreground-muted)]" aria-hidden="true" />
                    </button>

                    {isFilterMenuOpen && filterButtonRect && typeof document !== 'undefined' && createPortal(
                      <>
                        <div
                          className="fixed inset-0 z-[100]"
                          onClick={() => setIsFilterMenuOpen(false)}
                          aria-hidden="true"
                        />
                        <div
                          className="fixed z-[101] w-[20rem] overflow-hidden rounded-2xl border border-[var(--border)] bg-[var(--card)] shadow-2xl shadow-black/30"
                          style={{
                            top: filterButtonRect.bottom + 3,
                            left: filterButtonRect.left,
                          }}
                          role="menu"
                        >
                          <div className="border-b border-[var(--border)] bg-[var(--background-secondary)]/70 px-4 py-3">
                            <p className="text-sm font-semibold text-[var(--foreground)]">
                              {t('admin.organizations.replies.filter_menu.title')}
                            </p>
                            <p className="mt-0.5 text-xs text-[var(--foreground-muted)]">
                              {t('admin.organizations.replies.filter_menu.description')}
                            </p>
                          </div>
                          <div className="grid gap-3 p-3">
                            <div className="rounded-xl border border-[var(--border)] bg-[var(--background)]/45 p-2">
                              <div className="px-2 pb-1 text-[10px] font-semibold uppercase tracking-[0.16em] text-[var(--foreground-muted)]">
                                {t('admin.organizations.replies.filter_menu.reply_type')}
                              </div>
                              <div className="space-y-1">
                                {replyTypeOptions.map((option) => {
                                  const isSelected = option.value === activeReplyType

                                  return (
                                    <button
                                      key={option.value}
                                      type="button"
                                      onClick={() => handleReplyFilterChange({ reply_type: option.value })}
                                      className={`flex w-full items-center justify-between gap-3 rounded-lg px-2.5 py-2 text-left text-xs transition-colors ${
                                        isSelected
                                          ? 'bg-[var(--accent)]/12 text-[var(--accent)]'
                                          : 'text-[var(--foreground)] hover:bg-[var(--secondary)]'
                                      }`}
                                      role="menuitemradio"
                                      aria-checked={isSelected}
                                    >
                                      <span className="flex min-w-0 items-center gap-2">
                                        <span className={`size-1.5 rounded-full ${option.dotClassName}`} />
                                        <span className="truncate">{option.label}</span>
                                      </span>
                                      <span className="flex shrink-0 items-center gap-2 text-[var(--foreground-muted)]">
                                        {option.count}
                                        {isSelected && <Check className="size-3.5 text-[var(--accent)]" aria-hidden="true" />}
                                      </span>
                                    </button>
                                  )
                                })}
                              </div>
                            </div>

                            <div className="rounded-xl border border-[var(--border)] bg-[var(--background)]/45 p-2">
                              <div className="px-2 pb-1 text-[10px] font-semibold uppercase tracking-[0.16em] text-[var(--foreground-muted)]">
                                {t('admin.organizations.replies.filter_menu.sender')}
                              </div>
                              <div className="space-y-1">
                                <button
                                  type="button"
                                  onClick={() => handleReplyFilterChange({ sender_id: 'all' })}
                                  className={`flex w-full items-center justify-between gap-3 rounded-lg px-2.5 py-2 text-left text-xs transition-colors ${
                                    activeSenderId === 'all'
                                      ? 'bg-[var(--accent)]/12 text-[var(--accent)]'
                                      : 'text-[var(--foreground)] hover:bg-[var(--secondary)]'
                                  }`}
                                  role="menuitemradio"
                                  aria-checked={activeSenderId === 'all'}
                                >
                                  <span>{t('admin.organizations.replies.filter_menu.all_senders')}</span>
                                  {activeSenderId === 'all' && <Check className="size-3.5 text-[var(--accent)]" aria-hidden="true" />}
                                </button>
                                {sender_options.map((sender) => {
                                  const senderId = sender.id.toString()
                                  const isSelected = senderId === activeSenderId

                                  return (
                                    <button
                                      key={sender.id}
                                      type="button"
                                      onClick={() => handleReplyFilterChange({ sender_id: senderId })}
                                      className={`flex w-full items-center justify-between gap-3 rounded-lg px-2.5 py-2 text-left text-xs transition-colors ${
                                        isSelected
                                          ? 'bg-[var(--accent)]/12 text-[var(--accent)]'
                                          : 'text-[var(--foreground)] hover:bg-[var(--secondary)]'
                                      }`}
                                      role="menuitemradio"
                                      aria-checked={isSelected}
                                    >
                                      <span className="min-w-0">
                                        <span className="block truncate font-medium">{sender.name}</span>
                                        <span className="block truncate text-[10px] text-[var(--foreground-muted)]">{sender.email}</span>
                                      </span>
                                      {isSelected && <Check className="size-3.5 shrink-0 text-[var(--accent)]" aria-hidden="true" />}
                                    </button>
                                  )
                                })}
                              </div>
                            </div>
                          </div>
                        </div>
                      </>,
                      document.body
                    )}
                  </>
                ) : (
                  <>
                    <label htmlFor="reply_type_filter" className="block text-xs font-medium text-[var(--foreground-muted)] mb-1">
                      {t('admin.replies.filters.reply_type', { defaultValue: 'Reply Type' })}
                    </label>
                    <select
                      id="reply_type_filter"
                      value={activeReplyType}
                      onChange={(event) => handleReplyFilterChange({ reply_type: event.target.value })}
                      className="block w-full rounded-xl border border-[var(--input-border)] bg-[var(--input)] px-3 py-2 text-xs text-[var(--foreground)] transition-all focus:border-transparent focus:outline-none focus:ring-2 focus:ring-[var(--ring)]"
                    >
                      {replyTypeOptions.map((option) => (
                        <option key={option.value} value={option.value}>
                          {option.label} ({option.count})
                        </option>
                      ))}
                    </select>
                  </>
                )}
              </div>
            </div>
            

            {show_unassigned_link && stats.unassigned > 0 && (
              <a 
                href={`${basePath}/unassigned`}
                className="flex items-center justify-between p-2 bg-amber-50 dark:bg-amber-900/20 border border-amber-200 dark:border-amber-800 rounded-lg text-amber-800 dark:text-amber-200 hover:bg-amber-100 dark:hover:bg-amber-900/30 transition-colors"
              >
                <div className="flex items-center gap-2">
                  <AlertCircle className="w-4 h-4" />
                  <span className="text-xs font-medium">{t('admin.organizations.replies.stats.unassigned')}</span>
                </div>
                <Badge variant="outline" className="bg-amber-100 dark:bg-amber-800 border-amber-300 dark:border-amber-700 text-amber-800 dark:text-amber-200">
                  {stats.unassigned}
                </Badge>
              </a>
            )}
          </div>

          <div className="min-h-0 flex-1 overflow-y-auto custom-scrollbar px-2 py-2">
            {conversations.length === 0 ? (
              <div className="p-8 text-center">
                <div className="w-12 h-12 bg-[var(--card-hover)] rounded-full flex items-center justify-center mx-auto mb-3">
                  <Inbox className="w-6 h-6 text-[var(--foreground-muted)]" />
                </div>
                <p className="text-sm text-[var(--foreground-muted)]">
                  {t('admin.organizations.replies.empty_description')}
                </p>
              </div>
            ) : (
               <div className="space-y-1.5">
                {conversations.map((conversation) => (
                  <div key={conversation.id} className="relative">
                    <ConversationCard 
                      conversation={conversation} 
                      organizationId={organization.id} 
                      onClick={() => handleSelectConversation(conversation.id)}
                      isSelected={selected_id === conversation.id}
                    />
                    {loadingId === conversation.id && (
                      <div className="absolute inset-0 bg-[var(--background)]/50 flex items-center justify-center z-10 backdrop-blur-[1px]">
                        <Loader2 className="w-6 h-6 animate-spin text-[var(--accent)]" />
                      </div>
                    )}
                  </div>
                ))}
              </div>
            )}
          </div>

          {renderPagination()}
        </aside>
        
         <main className="relative flex min-h-0 min-w-0 flex-1 flex-col bg-[var(--background)]">
          {selected_detail ? (
            <>
               <div className="z-10 flex h-20 shrink-0 items-center justify-between border-b border-[var(--border)] bg-[var(--background)]/92 px-6 backdrop-blur-sm">
                <div className="flex items-center gap-3 min-w-0">
                  {selected_detail.lead.linkedin_profile_photo_url ? (
                    <img 
                      src={selected_detail.lead.linkedin_profile_photo_url} 
                      alt={leadName}
                      className="h-10 w-10 rounded-full object-cover shrink-0"
                      onError={(e) => {
                        e.currentTarget.style.display = 'none'
                        e.currentTarget.nextElementSibling?.classList.remove('hidden')
                      }}
                    />
                  ) : null}
                  <div className={`h-10 w-10 rounded-full bg-gradient-to-br from-[var(--accent)] to-purple-600 flex items-center justify-center text-white font-bold text-lg shrink-0 ${selected_detail.lead.linkedin_profile_photo_url ? 'hidden' : ''}`}>
                    {leadName.charAt(0)}
                  </div>
                  <div className="min-w-0">
                    <h2 className="text-lg font-bold text-[var(--foreground)] truncate">
                      {leadName}
                    </h2>
                    <div className="flex items-center gap-2 text-sm text-[var(--foreground-muted)]">
                      {selected_detail.conversation.lead.company && (
                        <span className="truncate">{selected_detail.conversation.lead.company}</span>
                      )}
                      {canManuallyChangeInterestStatus ? (
                        <label className="inline-flex items-center gap-1">
                          {headerInterestStatus && <span className={`h-1.5 w-1.5 rounded-full ${headerInterestStatus.dotClassName}`} />}
                          <select
                            value={selected_detail.conversation.interest_status || ''}
                            onChange={handleInterestStatusChange}
                            disabled={updatingInterestStatus}
                            className={`h-6 rounded border border-[var(--input-border)] bg-[var(--input)] px-1.5 text-xs font-semibold ${headerInterestStatus?.textClassName || 'text-[var(--foreground-muted)]'} disabled:opacity-60`}
                          >
                            <option value="" disabled>
                              {t('customer.agents.modal.not_set', { defaultValue: 'Not set' })}
                            </option>
                            <option value="interested">
                              {t('admin.organizations.replies.interest_status.interested', { defaultValue: 'Interested' })}
                            </option>
                            <option value="meeting_request">
                              {t('admin.organizations.replies.interest_status.meeting_request', { defaultValue: 'Meeting Request' })}
                            </option>
                            <option value="not_interested">
                              {t('admin.organizations.replies.interest_status.not_interested', { defaultValue: 'Not Interested' })}
                            </option>
                            <option value="wrong_person">
                              {t('admin.organizations.replies.interest_status.wrong_person', { defaultValue: 'Wrong Person' })}
                            </option>
                          </select>
                        </label>
                      ) : headerInterestStatus ? (
                        <span className={`inline-flex items-center gap-1 text-xs font-semibold ${headerInterestStatus.textClassName}`}>
                          <span className={`h-1.5 w-1.5 rounded-full ${headerInterestStatus.dotClassName}`} />
                          {headerInterestStatus.label}
                        </span>
                      ) : null}
                      {headerStatusBadge === 'bounced' && (
                        <Badge variant="bounced" size="sm" className="text-[10px] uppercase tracking-wider">
                          {t('admin.organizations.replies.bounced')}
                        </Badge>
                      )}
                      {headerStatusBadge === 'ooo' && (
                        <Badge variant="warning" size="sm" className="text-[10px] uppercase tracking-wider">
                          {t('admin.organizations.replies.ooo')}
                          {selected_detail.conversation.ooo_return_date && (
                            <span className="ml-1 normal-case">
                              ({t('admin.organizations.replies.ooo_returns', { date: new Date(selected_detail.conversation.ooo_return_date + 'T00:00:00').toLocaleDateString('en-US', { month: 'short', day: 'numeric' }) })})
                            </span>
                          )}
                        </Badge>
                      )}
                      {headerStatusBadge === 'reply-now' && (
                        <span className="inline-flex items-center rounded-md border border-amber-400/40 bg-amber-400/15 px-1 py-0 text-[9px] font-semibold tracking-normal text-amber-500">
                          {t('admin.organizations.replies.reply_now')}
                        </span>
                      )}
                    </div>
                  </div>
                </div>
                
                <div className="flex items-center gap-2">
                  <Button
                    variant="ghost"
                    size="sm"
                    className="md:hidden"
                    onClick={handleCloseDetail}
                    icon={<ChevronLeft className="w-4 h-4" />}
                  >
                    Back
                  </Button>
                </div>
              </div>

              <div className="flex-1 min-h-0 flex flex-col">
                <div 
                  ref={threadContainerRef}
                  className="min-h-0 flex-1 overflow-y-auto custom-scrollbar bg-[var(--background-secondary)]/28 p-6 space-y-6"
                >
                {selected_detail.thread.map((message, index) => (
                  <ThreadMessage 
                    key={`${message.source}-${message.id}`} 
                    message={message} 
                    previousMessage={index > 0 ? selected_detail.thread[index - 1] : undefined}
                  />
                ))}
                  <div ref={messagesEndRef} />
                </div>
              </div>
            </>
          ) : (
            <div className="flex-1 flex flex-col items-center justify-center text-[var(--foreground-muted)] p-8">
              <div className="w-24 h-24 bg-[var(--card)] rounded-full flex items-center justify-center mb-6 border border-[var(--border)] shadow-sm">
                <MessageCircle className="w-10 h-10 text-[var(--foreground-subtle)]" />
              </div>
              <h3 className="text-xl font-semibold text-[var(--foreground)] mb-2">
                {t('admin.organizations.replies.select_conversation')}
              </h3>
              <p className="max-w-md text-center">
                {t('admin.organizations.replies.select_conversation_desc') || "Choose a conversation from the list to view the thread, lead details, and send a reply."}
              </p>
            </div>
          )}
        </main>
        
        {selected_detail && (
           <aside className="hidden h-full min-h-0 w-[24rem] shrink-0 overflow-y-auto border-l border-[var(--border)] bg-[var(--background-secondary)]/88 custom-scrollbar xl:block">
            <LeadSidebar 
              lead={selected_detail.lead} 
              mailbox={selected_detail.mailbox} 
              sender={selected_detail.sender} 
              hideIncompleteBuyingSignals
            />
          </aside>
        )}
    </div>
  )

  if (layout_mode === 'full') {
    return (
      <AuthenticatedLayout
        title={t('admin.organizations.replies.title')}
        account={auth.account}
        flash={flash}
        fullBleed={true}
        hideHeader={true}
      >
        {content}
      </AuthenticatedLayout>
    )
  }

  return (
    <OrganizationTabLayout
      organization={organization}
      currentTab={current_tab}
      account={auth.account}
      flash={flash}
      fullBleed={true}
    >
      {content}
    </OrganizationTabLayout>
  )
}
