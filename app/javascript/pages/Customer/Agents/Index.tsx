import { FormEvent, ReactNode, useEffect, useMemo, useRef, useState } from 'react'
import { Link, router } from '@inertiajs/react'
import { AlertCircle, Briefcase, Building2, ChevronDown, Clock, Download, Globe, Linkedin, Mail, MapPin, MessageSquare, Pause, Play, Search, X } from 'lucide-react'
import AuthenticatedLayout from '../../../layouts/AuthenticatedLayout'
import { getPlaybookGradient } from '../../../layouts/PlaybookLayout'
import { t } from '../../../lib/i18n'
import { renderBuyingSignalsMarkdown } from '../../../lib/renderBuyingSignalsMarkdown'
import { Badge, BadgeProps } from '../../../components/ui/Badge'
import { Button } from '../../../components/ui/Button'
import { toast } from '../../../components/ui/Toaster'

import { BuyingSignalsHighlights } from '../../../components/BuyingSignalsHighlights'
import { BuyingSignalsRelevanceHeader } from '../../../components/BuyingSignalsRelevanceHeader'
import { SlideOver } from '../../../components/ui/SlideOver'
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '../../../components/ui/Table'

interface Agent {
  id: number
  name: string
  playbook_id: number | null
  status: string
  playbook_approved: boolean
}

interface Lead {
  id: number
  email: string
  first_name: string | null
  last_name: string | null
  full_name: string | null
  display_name: string
  company: string | null
  job_title: string | null
  blacklisted: boolean
  blacklist_reason_category: string | null
  interest_tag: 'interested' | 'meeting_request' | 'not_interested' | 'wrong_person' | null
}

interface AgentLead {
  id: number
  delivery_status: string
  sequence_position: number
  total_messages_sent: number
  last_sent_at: string | null
  next_send_at: string | null
  replied_at: string | null
  meeting_booked_at: string | null
  currently_out_of_office: boolean
  out_of_office_return_date: string | null
  created_at: string
  agent: Agent
  lead: Lead
  assigned_mailbox?: { id: number; email: string } | null
  buying_signals_relevance_rating: number | null
}

interface Filters {
  agent_id: string | null
  status: string | null
  search: string | null
}

interface Pagination {
  current_page: number
  total_pages: number
  total_count: number
  per_page: number
}

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
  has_meeting: boolean
  agent: { id: number; name: string; status: string }
  assigned_mailbox?: { id: number; email: string } | null
  generated_messages: ModalGeneratedMessage[]
}

interface ModalThreadMessage {
  id: number
  type: 'incoming' | 'outgoing'
  source: 'generated_message' | 'reply' | 'sent_reply'
  from: string
  subject: string
  body_plain: string
  message_at: string
  is_bounce: boolean
  is_out_of_office: boolean
}

interface ModalConversation {
  id: number
  status: string
  interest_status: 'interested' | 'meeting_request' | 'not_interested' | 'wrong_person' | null
  mailbox: { id: number; email: string }
  thread: ModalThreadMessage[]
}

type CustomerInterestTag = Lead['interest_tag']
type ManualInterestStatus = Exclude<CustomerInterestTag, null>

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
  linkedin_profile_photo_url: string | null
  linkedin_headline: string | null
  linkedin_summary: string | null
  disc_profile: string | null
  disc_profile_data?: { confidence?: number; reasoning?: string } | null
  disc_profile_source?: string | null
  buying_signals_summary_status: string | null
  buying_signals_markdown: string
  buying_signals_highlights: string[]
  buying_signals_relevance_rating: number | null
  buying_signals_generated_at: string | null
  company_website_summary: string | null
  company_website_content: string | null
  linkedin_posts: Array<{ text: string; url: string; date: string }> | null
  custom_fields: Record<string, unknown> | null
  linkedin_scraped_at: string | null
  linkedin_posts_scraped_at: string | null
  company_website_scraped_at: string | null
  disc_profile_assessed_at: string | null
  agent_leads: ModalAgentLead[]
  conversations: ModalConversation[]
}

interface DownloadableAgent {
  id: number
  name: string
}

interface Props {
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
  agent_leads: AgentLead[]
  agents: Agent[]
  downloadable_agents: DownloadableAgent[]
  status_options: string[]
  status_counts: Record<string, number>
  sent_today_count: number
  filters: Filters
  pagination: Pagination
  can_manage_campaigns?: boolean
  flash?: { notice?: string; alert?: string }
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

type ModalTab = 'messages' | 'buying_signals'

const AGENT_GRADIENT_STYLES: Record<string, string> = {
  orange: 'bg-gradient-to-r from-orange-500/25 to-amber-500/25 text-orange-300 ring-1 ring-orange-500/20',
  green: 'bg-gradient-to-r from-emerald-500/25 to-teal-500/25 text-emerald-300 ring-1 ring-emerald-500/20',
  blue: 'bg-gradient-to-r from-blue-500/25 to-indigo-500/25 text-blue-300 ring-1 ring-blue-500/20',
  purple: 'bg-gradient-to-r from-purple-500/25 to-violet-500/25 text-purple-300 ring-1 ring-purple-500/20',
}

const agentGradientStyle = (playbookId: number | null): string => {
  const color = playbookId ? getPlaybookGradient(playbookId) : 'blue'
  return AGENT_GRADIENT_STYLES[color] || AGENT_GRADIENT_STYLES.blue
}

const AGENT_DOT_COLORS: Record<string, string> = {
  orange: 'bg-orange-400',
  green: 'bg-emerald-400',
  blue: 'bg-blue-400',
  purple: 'bg-purple-400',
}

const AGENT_ICON_COLORS: Record<string, string> = {
  orange: 'text-orange-400',
  green: 'text-emerald-400',
  blue: 'text-blue-400',
  purple: 'text-purple-400',
}

const agentDotColor = (playbookId: number | null): string => {
  const color = playbookId ? getPlaybookGradient(playbookId) : 'blue'
  return AGENT_DOT_COLORS[color] || AGENT_DOT_COLORS.blue
}

const agentIconColor = (playbookId: number | null): string => {
  const color = playbookId ? getPlaybookGradient(playbookId) : 'blue'
  return AGENT_ICON_COLORS[color] || AGENT_ICON_COLORS.blue
}

const getStatusBadgeVariant = (status: string): BadgeProps['variant'] => {
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

const INTEREST_TAG_CONFIG: Record<Exclude<CustomerInterestTag, null>, { variant: BadgeProps['variant']; key: Exclude<CustomerInterestTag, null> }> = {
  interested: { variant: 'approved', key: 'interested' },
  meeting_request: { variant: 'success', key: 'meeting_request' },
  not_interested: { variant: 'error', key: 'not_interested' },
  wrong_person: { variant: 'warning', key: 'wrong_person' },
}

const MANUAL_INTEREST_STATUSES: ManualInterestStatus[] = ['interested', 'meeting_request', 'not_interested', 'wrong_person']

const getInterestTagConfig = (interestTag: CustomerInterestTag) => {
  return interestTag ? INTEREST_TAG_CONFIG[interestTag] : null
}

const formatDate = (dateString: string | null) => {
  if (!dateString) return '—'

  return new Date(dateString).toLocaleDateString('en-US', {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit'
  })
}

const formatDateOnly = (dateString: string | null) => {
  if (!dateString) return '—'

  return new Date(dateString).toLocaleDateString('en-US', {
    month: 'short',
    day: 'numeric',
    year: 'numeric'
  })
}

const formatEnrichmentDate = (dateString: string | null) => {
  if (!dateString) return null

  return new Date(dateString).toLocaleDateString('en-US', {
    month: 'short',
    day: 'numeric',
    year: 'numeric'
  })
}

function EnrichmentCard({
  icon: Icon,
  title,
  date,
  expanded,
  onToggle,
  children
}: {
  icon: typeof Linkedin
  title: string
  date?: string | null
  expanded: boolean
  onToggle: () => void
  children: ReactNode
}) {
  return (
    <div className="overflow-hidden rounded-[22px] border border-[var(--border)] bg-[var(--card)] shadow-[var(--shadow-sm)]">
      <button
        type="button"
        onClick={onToggle}
        className="flex w-full items-center gap-2.5 px-4 py-3 text-left transition-colors hover:bg-white/[0.03]"
      >
        <Icon className="h-4 w-4 shrink-0 text-[var(--foreground-subtle)]" />
        <span className="flex-1 text-sm font-medium text-[var(--foreground)]">{title}</span>
        {date && (
          <span className="text-[11px] text-[var(--foreground-subtle)]">
            {formatEnrichmentDate(date)}
          </span>
        )}
        <ChevronDown className={`h-3.5 w-3.5 text-[var(--foreground-subtle)] transition-transform duration-200 ${expanded ? '' : '-rotate-90'}`} />
      </button>

      {expanded && (
        <div className="space-y-3 border-t border-[var(--border)] px-4 pb-4 pt-3">
          {children}
        </div>
      )}
    </div>
  )
}

const buildTimeline = (data: LeadModalData | null): TimelineMessage[] => {
  if (!data) return []

  const generated = data.agent_leads.flatMap(agentLead =>
    agentLead.generated_messages.map((message) => ({
      key: `generated_message:${message.id}`,
      timestamp: new Date(message.sent_at || message.created_at),
      subject: message.subject || t('customer.agents.modal.messages.no_subject'),
      body: message.body,
      from: t('customer.agents.modal.messages.generated_for', { agent: agentLead.agent.name }),
      tone: 'generated' as const,
      label: t('customer.agents.modal.messages.generated_label', { status: message.status })
    }))
  )

  const thread = data.conversations.flatMap(conversation =>
    conversation.thread.map((message) => ({
      key: `${message.source}:${message.id}`,
      timestamp: new Date(message.message_at),
      subject: message.subject || t('customer.agents.modal.messages.no_subject'),
      body: message.body_plain,
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

const hasBuyingSignals = (data: LeadModalData | null) => (
  data?.buying_signals_summary_status === 'completed' && data.buying_signals_markdown.trim().length > 0
)

const getDefaultModalTab = (data: LeadModalData): ModalTab => {
  return hasBuyingSignals(data) && buildTimeline(data).length === 0 ? 'buying_signals' : 'messages'
}

export default function Index({
  auth,
  agent_leads,
  agents,
  downloadable_agents,
  status_options,
  status_counts,
  sent_today_count,
  filters,
  pagination,
  can_manage_campaigns,
  flash
}: Props) {
  const account = auth.account
  const canManageCampaigns = can_manage_campaigns ?? false
  const [searchInput, setSearchInput] = useState(filters.search || '')
  const [selectedLeadId, setSelectedLeadId] = useState<number | null>(null)
  const [selectedAgentLeadId, setSelectedAgentLeadId] = useState<number | null>(null)
  const [isModalOpen, setIsModalOpen] = useState(false)
  const [loadingLead, setLoadingLead] = useState(false)
  const [modalError, setModalError] = useState<string | null>(null)
  const [modalData, setModalData] = useState<LeadModalData | null>(null)
  const [activeModalTab, setActiveModalTab] = useState<ModalTab>('messages')
  const [agentDropdownOpen, setAgentDropdownOpen] = useState(false)
  const [expandedSections, setExpandedSections] = useState<Set<string>>(new Set())
  const [isDownloadModalOpen, setIsDownloadModalOpen] = useState(false)
  const [selectedDownloadAgentId, setSelectedDownloadAgentId] = useState('')
  const [updatingInterestStatus, setUpdatingInterestStatus] = useState(false)
  const [openingReplyConversation, setOpeningReplyConversation] = useState(false)
  const agentDropdownRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    setSearchInput(filters.search || '')
  }, [filters.search])

  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (agentDropdownRef.current && !agentDropdownRef.current.contains(event.target as Node)) {
        setAgentDropdownOpen(false)
      }
    }
    document.addEventListener('mousedown', handleClickOutside)
    return () => document.removeEventListener('mousedown', handleClickOutside)
  }, [])

  useEffect(() => {
    const fetchLead = async () => {
      if (!selectedLeadId || !isModalOpen) return

      setLoadingLead(true)
      setModalError(null)

      try {
        const response = await fetch(`/leads/${selectedLeadId}/modal`, {
          headers: {
            Accept: 'application/json',
            'X-Requested-With': 'XMLHttpRequest'
          }
        })

        if (!response.ok) {
          throw new Error(`Failed with status ${response.status}`)
        }

        const payload = await response.json() as LeadModalData
        setActiveModalTab(getDefaultModalTab(payload))
        setModalData(payload)
      } catch {
        setModalError(t('customer.agents.modal.load_error'))
      } finally {
        setLoadingLead(false)
      }
    }

    fetchLead()
  }, [selectedLeadId, isModalOpen])

  const handleFilterChange = (key: keyof Filters, value: string | null) => {
    router.get('/agents', {
      ...filters,
      [key]: value || undefined,
      page: 1
    }, { preserveState: true })
  }

  const handleSearch = (event: FormEvent) => {
    event.preventDefault()
    handleFilterChange('search', searchInput || null)
  }

  const clearSearch = () => {
    setSearchInput('')
    handleFilterChange('search', null)
  }

  const allCount = useMemo(
    () => Object.values(status_counts).reduce((sum, n) => sum + n, 0),
    [status_counts]
  )

  const activeStatusTab = filters.status || 'all'
  const selectedAgent = filters.agent_id
    ? agents.find(agent => String(agent.id) === String(filters.agent_id))
    : null
  const selectedAgentIconColor = selectedAgent ? agentIconColor(selectedAgent.playbook_id) : 'text-[var(--foreground-muted)]'

  const handleStatusTabChange = (tabId: string) => {
    handleFilterChange('status', tabId === 'all' ? null : tabId)
  }

  const goToPage = (page: number) => {
    router.get('/agents', {
      ...filters,
      page
    }, { preserveState: true })
  }

  const handleSelectedAgentCampaignToggle = () => {
    if (!selectedAgent) return
    if (selectedAgent.status !== 'active' && selectedAgent.status !== 'paused') return

    const action = selectedAgent.status === 'active' ? 'pause_campaign' : 'resume_campaign'

    router.post(`/agents/${selectedAgent.id}/${action}`, {}, {
      preserveState: true,
      preserveScroll: true
    })
  }

  const buildLeadModalUrl = (leadId: number, agentLeadId: number | null) => {
    const url = new URL(window.location.href)
    url.searchParams.set('lead_id', String(leadId))

    if (agentLeadId) {
      url.searchParams.set('agent_lead_id', String(agentLeadId))
    } else {
      url.searchParams.delete('agent_lead_id')
    }

    return `${url.pathname}${url.search}${url.hash}`
  }

  const buildAgentsListUrl = () => {
    const url = new URL(window.location.href)
    url.searchParams.delete('lead_id')
    url.searchParams.delete('agent_lead_id')

    return `${url.pathname}${url.search}${url.hash}`
  }

  const syncLeadModalFromUrl = () => {
    const url = new URL(window.location.href)
    const leadIdParam = Number(url.searchParams.get('lead_id'))
    const agentLeadIdParam = Number(url.searchParams.get('agent_lead_id'))

    if (Number.isFinite(leadIdParam) && leadIdParam > 0) {
      setSelectedLeadId(leadIdParam)
      setSelectedAgentLeadId(Number.isFinite(agentLeadIdParam) && agentLeadIdParam > 0 ? agentLeadIdParam : null)
      setModalData(null)
      setModalError(null)
      setActiveModalTab('messages')
      setExpandedSections(new Set())
      setIsModalOpen(true)
      return
    }

    setIsModalOpen(false)
    setSelectedLeadId(null)
    setSelectedAgentLeadId(null)
    setModalData(null)
    setModalError(null)
    setExpandedSections(new Set())
  }

  const closeLeadModal = () => {
    window.history.replaceState({}, '', buildAgentsListUrl())
    setIsModalOpen(false)
    setSelectedLeadId(null)
    setSelectedAgentLeadId(null)
    setModalData(null)
    setModalError(null)
    setExpandedSections(new Set())
  }

  useEffect(() => {
    syncLeadModalFromUrl()

    const handlePopState = () => {
      syncLeadModalFromUrl()
    }

    window.addEventListener('popstate', handlePopState)
    return () => window.removeEventListener('popstate', handlePopState)
  }, [])

  const openLead = (leadId: number, agentLeadId: number) => {
    window.history.pushState({}, '', buildLeadModalUrl(leadId, agentLeadId))
    setSelectedLeadId(leadId)
    setSelectedAgentLeadId(agentLeadId)
    setModalData(null)
    setModalError(null)
    setActiveModalTab('messages')
    setIsModalOpen(true)
    setExpandedSections(new Set())
  }

  const handleOpenDownloadModal = () => {
    setSelectedDownloadAgentId(filters.agent_id ? String(filters.agent_id) : '')
    setIsDownloadModalOpen(true)
  }

  const handleCloseDownloadModal = () => {
    setIsDownloadModalOpen(false)
  }

  const handleDownloadCsv = () => {
    const agentId = Number(selectedDownloadAgentId)

    if (!Number.isFinite(agentId)) {
      return
    }

    window.location.href = `/agents/download?agent_id=${agentId}`
    setIsDownloadModalOpen(false)
  }

  const toggleSection = (section: string) => {
    setExpandedSections(prev => {
      const next = new Set(prev)
      if (next.has(section)) {
        next.delete(section)
      } else {
        next.add(section)
      }

      return next
    })
  }

  const handleBuyingSignalsUpgradeInterest = async () => {
    if (!modalData) return

    try {
      const csrfToken = document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content
      const response = await fetch('/settings/billing/notify_interest', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Accept: 'application/json',
          ...(csrfToken ? { 'X-CSRF-Token': csrfToken } : {})
        },
        body: JSON.stringify({
          action_name: 'upgrade_for_buying_signals',
          lead_id: modalData.id
        })
      })

      const payload = await response.json().catch(() => ({})) as { error?: string; notice?: string }
      if (!response.ok) {
        throw new Error(payload.error || t('customer.agents.buying_signals.notify_failed'))
      }

      toast.success(payload.notice || t('customer.agents.buying_signals.notify_success'))
    } catch (error) {
      const message = error instanceof Error ? error.message : t('customer.agents.buying_signals.notify_failed')
      toast.error(message)
    }
  }

  const timeline = useMemo(() => buildTimeline(modalData), [modalData])
  const buyingSignalsAvailable = useMemo(() => hasBuyingSignals(modalData), [modalData])
  const lastMessageDate = useMemo(() => {
    const latestEntry = timeline[timeline.length - 1]
    return latestEntry ? formatEnrichmentDate(latestEntry.timestamp.toISOString()) : null
  }, [timeline])
  const lastBuyingSignalsDate = useMemo(() => formatEnrichmentDate(modalData?.buying_signals_generated_at || null), [modalData])
  const selectedTableAgentLead = useMemo(() => {
    return agent_leads.find((agentLead) => agentLead.id === selectedAgentLeadId) || null
  }, [agent_leads, selectedAgentLeadId])

  const selectedModalAgentLead = useMemo(() => {
    if (!modalData) return null

    return modalData.agent_leads.find((agentLead) => agentLead.id === selectedAgentLeadId) || modalData.agent_leads[0] || null
  }, [modalData, selectedAgentLeadId])

  const actionableConversation = useMemo(() => {
    if (!modalData) return null

    if (selectedModalAgentLead?.assigned_mailbox) {
      const mailboxConversation = modalData.conversations.find((conversation) => (
        conversation.mailbox.id === selectedModalAgentLead.assigned_mailbox?.id
      ))

      return mailboxConversation || null
    }

    if (selectedModalAgentLead) {
      return modalData.conversations.length === 1 ? modalData.conversations[0] : null
    }

    return modalData.conversations.length === 1 ? modalData.conversations[0] : null
  }, [modalData, selectedModalAgentLead])

  const fallbackInterestStatus = useMemo<ModalConversation['interest_status']>(() => {
    const tagKey = selectedTableAgentLead?.lead.interest_tag
      ? INTEREST_TAG_CONFIG[selectedTableAgentLead.lead.interest_tag]?.key
      : null

    if (tagKey === 'interested' || tagKey === 'meeting_request' || tagKey === 'not_interested' || tagKey === 'wrong_person') {
      return tagKey
    }

    return null
  }, [selectedTableAgentLead])

  const currentInterestStatus = actionableConversation?.interest_status || fallbackInterestStatus || null
  const canManuallyUpdateInterestStatus = Boolean(actionableConversation || selectedModalAgentLead)
  const hasOutgoingMessages = useMemo(() => {
    if (!modalData) return false

    const hasGeneratedOutgoing = modalData.agent_leads.some((agentLead) => (
      agentLead.generated_messages.some((message) => (
        Boolean(message.sent_at) || ['sent', 'replied', 'bounced'].includes(message.status)
      ))
    ))

    if (hasGeneratedOutgoing) return true

    return modalData.conversations.some((conversation) => (
      conversation.thread.some((message) => message.type === 'outgoing')
    ))
  }, [modalData])
  const targetMailbox = actionableConversation?.mailbox || selectedModalAgentLead?.assigned_mailbox || null
  const selectedAgentLeadHasMeeting = selectedModalAgentLead?.has_meeting ?? Boolean(selectedTableAgentLead?.meeting_booked_at)
  const canOpenReplyCenterConversation = Boolean(selectedModalAgentLead && hasOutgoingMessages)

  const handleInterestStatusChange = async (nextStatus: ManualInterestStatus) => {
    if (!selectedLeadId || !canManuallyUpdateInterestStatus || updatingInterestStatus) return
    if (nextStatus === currentInterestStatus) return

    const confirmationMessage = nextStatus === 'not_interested'
      ? (selectedAgentLeadHasMeeting
          ? t('customer.agents.modal.interest_actions.confirm_remove_meeting')
          : null)
      : nextStatus === 'meeting_request'
        ? t('customer.agents.modal.interest_actions.confirm_create_meeting')
        : null

    if (confirmationMessage && !window.confirm(confirmationMessage)) return

    setUpdatingInterestStatus(true)
    setModalError(null)

    try {
      const csrfToken = document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content
      const response = await fetch(`/leads/${selectedLeadId}/update_interest_status`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Accept: 'application/json',
          ...(csrfToken ? { 'X-CSRF-Token': csrfToken } : {})
        },
        body: JSON.stringify({
          interest_status: nextStatus,
          conversation_id: actionableConversation?.id,
          agent_lead_id: selectedModalAgentLead?.id
        })
      })

      const payload = await response.json().catch(() => ({})) as {
        error?: string
        conversation_id?: number
        interest_status?: ModalConversation['interest_status']
        mailbox?: ModalConversation['mailbox']
      }
      if (!response.ok) {
          throw new Error(payload.error || t('customer.agents.modal.interest_actions.update_failed'))
      }

      setModalData((current) => {
        if (!current) return current

        const nextConversationId = payload.conversation_id
        const nextMailbox = payload.mailbox || targetMailbox
        if (!nextConversationId || !nextMailbox) return current

        const conversationExists = current.conversations.some((conversation) => conversation.id === nextConversationId)

        return {
          ...current,
          blacklisted: true,
          conversations: conversationExists
            ? current.conversations.map((conversation) => (
              conversation.id === nextConversationId
                ? { ...conversation, interest_status: payload.interest_status || nextStatus }
                : conversation
            ))
            : [
                {
                  id: nextConversationId,
                  status: 'open',
                  interest_status: payload.interest_status || nextStatus,
                  mailbox: nextMailbox,
                  thread: []
                },
                ...current.conversations
              ]
        }
      })

      router.reload({ only: ['agent_leads', 'status_counts'] })
      toast.success(t('customer.agents.modal.interest_actions.update_success'))
    } catch (error) {
      const message = error instanceof Error ? error.message : t('customer.agents.modal.interest_actions.update_failed')
      setModalError(message)
      toast.error(message)
    } finally {
      setUpdatingInterestStatus(false)
    }
  }

  const handleOpenReplyConversation = async () => {
    if (!selectedLeadId || !selectedModalAgentLead || openingReplyConversation) return

    setOpeningReplyConversation(true)
    setModalError(null)

    try {
      const csrfToken = document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content
      const response = await fetch(`/leads/${selectedLeadId}/open_reply_conversation`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Accept: 'application/json',
          ...(csrfToken ? { 'X-CSRF-Token': csrfToken } : {})
        },
        body: JSON.stringify({
          agent_lead_id: selectedModalAgentLead.id,
          conversation_id: actionableConversation?.id,
          return_to: buildLeadModalUrl(selectedLeadId, selectedModalAgentLead.id)
        })
      })

      const payload = await response.json().catch(() => ({})) as {
        error?: string
        redirect_url?: string
      }

      if (!response.ok || !payload.redirect_url) {
        throw new Error(payload.error || t('customer.agents.modal.messages.open_reply_failed'))
      }

      router.visit(payload.redirect_url)
    } catch (error) {
      const message = error instanceof Error ? error.message : t('customer.agents.modal.messages.open_reply_failed')
      setModalError(message)
      toast.error(message)
      setOpeningReplyConversation(false)
    }
  }

  return (
    <AuthenticatedLayout
      title={t('customer.agents.title')}
      account={account}
      flash={flash}
      fullBleed={true}
      headerActions={
        <div className="flex items-center gap-3">
          <Button
            type="button"
            variant="secondary"
            size="sm"
            icon={<Building2 className="h-4 w-4" />}
            asChild
          >
            <Link href="/agents/companies">
              {t('customer.agents.companies.view_companies')}
            </Link>
          </Button>

          <Button
            type="button"
            variant="secondary"
            size="sm"
            icon={<Download className="w-4 h-4" />}
            onClick={handleOpenDownloadModal}
          >
            {t('customer.agents.show.download_button')}
          </Button>

          <Badge
            size="sm"
            className="rounded-full border-[var(--accent)]/20 bg-[var(--accent)]/10 px-2 py-0.5 text-[10px] text-[var(--accent)]"
          >
            {t('customer.agents.sent_today_badge', { count: sent_today_count })}
          </Badge>
        </div>
      }
    >
      <div className="flex h-full min-h-0 flex-col">
        <div className="sticky top-0 z-20 border-b border-[var(--border)] bg-[var(--background)]/94 px-6 py-4 backdrop-blur-sm lg:px-8">
          <div className="flex items-center gap-2">
            <div className="flex items-center gap-0.5" role="tablist">
              {[
                { id: 'all', label: t('common.all_statuses'), count: allCount },
                ...status_options.map(status => ({
                  id: status,
                  label: t(`customer.agents.delivery_statuses.${status}`),
                  count: status_counts[status] || 0
                }))
              ].map(filter => {
                const isActive = activeStatusTab === filter.id
                return (
                  <button
                    key={filter.id}
                    type="button"
                    role="tab"
                    aria-selected={isActive}
                    onClick={() => handleStatusTabChange(filter.id)}
                    className={`flex flex-col items-center rounded-full px-4 py-2 transition-colors cursor-pointer ${
                      isActive
                        ? 'border border-white/[0.08] bg-white/[0.05] text-[var(--foreground)]'
                        : 'border border-transparent text-[var(--foreground-subtle)] hover:bg-white/[0.04] hover:text-[var(--foreground)]'
                    }`}
                  >
                    <span className="text-sm leading-tight">{filter.label}</span>
                    <span className="text-[10px] font-medium leading-tight">{filter.count}</span>
                  </button>
                )
              })}
            </div>

            <div className="relative" ref={agentDropdownRef}>
              <button
                type="button"
                className="flex h-10 max-w-[180px] items-center gap-2 rounded-xl border border-[var(--input-border)] bg-[var(--input)] px-3.5 text-sm text-[var(--foreground)]"
                onClick={() => setAgentDropdownOpen(!agentDropdownOpen)}
              >
                {filters.agent_id && (() => {
                  const selected = agents.find(a => String(a.id) === String(filters.agent_id))
                  return selected ? (
                    <span className={`h-2 w-2 shrink-0 rounded-full ${agentDotColor(selected.playbook_id)}`} />
                  ) : null
                })()}
                <span className="truncate">
                  {filters.agent_id
                    ? agents.find(a => String(a.id) === String(filters.agent_id))?.name || t('customer.agents.filters.all_agents')
                    : t('customer.agents.filters.all_agents')}
                </span>
                <ChevronDown className="h-3.5 w-3.5 shrink-0 text-[var(--foreground-muted)]" />
              </button>
              {agentDropdownOpen && (
                <div className="absolute left-0 top-full z-50 mt-2 min-w-[200px] rounded-2xl border border-[var(--border)] bg-[var(--background-elevated)] py-1.5 shadow-[var(--shadow-md)]">
                  <button
                    type="button"
                    className={`flex w-full items-center gap-2 px-3 py-1.5 text-left text-sm ${
                      !filters.agent_id ? 'text-[var(--foreground)]' : 'text-[var(--foreground-muted)] hover:text-[var(--foreground)]'
                    } hover:bg-[var(--accent)]`}
                    onClick={() => { handleFilterChange('agent_id', null); setAgentDropdownOpen(false) }}
                  >
                    {t('customer.agents.filters.all_agents')}
                  </button>
                  {agents.map((agent) => (
                    <button
                      key={agent.id}
                      type="button"
                      className={`flex w-full items-center gap-2 px-3 py-1.5 text-left text-sm ${
                        String(filters.agent_id) === String(agent.id) ? 'text-[var(--foreground)]' : 'text-[var(--foreground-muted)] hover:text-[var(--foreground)]'
                      } hover:bg-[var(--accent)]`}
                      onClick={() => { handleFilterChange('agent_id', String(agent.id)); setAgentDropdownOpen(false) }}
                    >
                      <span className={`h-2 w-2 shrink-0 rounded-full ${agentDotColor(agent.playbook_id)}`} />
                      <span className="truncate">{agent.name}</span>
                    </button>
                  ))}
                </div>
              )}
            </div>

            {selectedAgent?.playbook_id && !selectedAgent.playbook_approved && (
              <Button
                type="button"
                variant="secondary"
                size="sm"
                title={t('customer.agents.campaign_controls.approve_playbook_button')}
                aria-label={t('customer.agents.campaign_controls.approve_playbook_button')}
                onClick={() => router.visit(`/playbooks/${selectedAgent.playbook_id}`)}
                className="h-9 px-3"
              >
                {t('customer.agents.campaign_controls.approve_playbook_button')}
              </Button>
            )}

            {canManageCampaigns && selectedAgent && selectedAgent.playbook_approved && (selectedAgent.status === 'active' || selectedAgent.status === 'paused') && (
              <Button
                type="button"
                variant="secondary"
                size="sm"
                title={selectedAgent.status === 'active' ? t('customer.agents.campaign_controls.pause_button') : t('customer.agents.campaign_controls.resume_button')}
                aria-label={selectedAgent.status === 'active' ? t('customer.agents.campaign_controls.pause_button') : t('customer.agents.campaign_controls.resume_button')}
                onClick={handleSelectedAgentCampaignToggle}
                className="h-9 w-9 px-0"
              >
                {selectedAgent.status === 'active' ? (
                  <Pause className={`h-4 w-4 ${selectedAgentIconColor}`} />
                ) : (
                  <Play className={`h-4 w-4 ${selectedAgentIconColor}`} />
                )}
              </Button>
            )}

            <form className="relative ml-auto" onSubmit={handleSearch}>
              <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-[var(--foreground-muted)]" />
              <input
                className="h-10 w-64 rounded-xl border border-[var(--input-border)] bg-[var(--input)] pl-9 pr-8 text-sm text-[var(--foreground)] placeholder:text-[var(--foreground-subtle)] lg:w-80"
                placeholder={t('customer.agents.filters.search_placeholder')}
                value={searchInput}
                onChange={(event) => setSearchInput(event.target.value)}
              />
              {searchInput && (
                <button
                  type="button"
                  className="absolute right-3 top-1/2 -translate-y-1/2 text-[var(--foreground-muted)] hover:text-[var(--foreground)]"
                  onClick={clearSearch}
                >
                  <X className="h-3.5 w-3.5" />
                </button>
              )}
            </form>
          </div>
        </div>

        <div className="flex-1 min-h-0 overflow-y-auto overflow-x-auto custom-scrollbar px-6 pb-6 lg:px-8 lg:pb-8">
          <div className="pt-4">
            <Table scrollable={false} containerClassName="inline-block min-w-full align-middle">
              <TableHeader>
                <TableRow>
                  <TableHead>{t('customer.agents.table.date_added')}</TableHead>
                  <TableHead>{t('customer.agents.table.last_sent')}</TableHead>
                  <TableHead>{t('customer.agents.table.lead')}</TableHead>
                  <TableHead>{t('customer.agents.table.agent')}</TableHead>
                  <TableHead><BuyingSignalsRelevanceHeader /></TableHead>
                  <TableHead>{t('common.status')}</TableHead>
                  <TableHead>{t('customer.agents.table.progress')}</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {agent_leads.length === 0 ? (
                  <TableRow>
                    <TableCell className="py-12 text-center" colSpan={7}>
                      {t('customer.agents.empty.description')}
                    </TableCell>
                  </TableRow>
                ) : (
                  agent_leads.map((row) => (
                    <TableRow key={row.id} onClick={() => openLead(row.lead.id, row.id)}>
                      <TableCell>
                        <span className="text-xs text-[var(--foreground-muted)] whitespace-nowrap">{formatDate(row.created_at)}</span>
                      </TableCell>
                      <TableCell>
                        <span className="text-xs text-[var(--foreground-muted)] whitespace-nowrap">{row.last_sent_at ? formatDate(row.last_sent_at) : '—'}</span>
                      </TableCell>
                      <TableCell variant="primary">
                        <div className="space-y-0.5">
                          <div className="text-sm font-medium text-[var(--foreground)]">{row.lead.display_name}</div>
                          <div
                            className="max-w-[220px] truncate text-xs text-[var(--foreground-subtle)]"
                            title={row.lead.job_title || '—'}
                          >
                            {row.lead.job_title || '—'}
                          </div>
                          <div
                            className="max-w-[220px] truncate text-xs text-[var(--foreground-muted)]"
                            title={row.lead.company || '—'}
                          >
                            {row.lead.company || '—'}
                          </div>
                          <div className="text-xs text-[var(--foreground-muted)]">{row.lead.email}</div>
                        </div>
                      </TableCell>
                      <TableCell className="w-[140px] max-w-[140px] !whitespace-normal">
                        <span className={`block overflow-hidden break-words rounded-md px-2 py-0.5 text-xs font-medium ${agentGradientStyle(row.agent.playbook_id)}`}>{row.agent.name}</span>
                      </TableCell>
                      <TableCell>
                        <span className="text-sm font-medium text-[var(--foreground)]">
                          {row.buying_signals_relevance_rating
                            ? t('customer.agents.buying_signals.rating_value', { rating: row.buying_signals_relevance_rating })
                            : '—'}
                        </span>
                      </TableCell>
                      <TableCell>
                        <div className="flex items-center gap-1.5">
                          {row.currently_out_of_office ? (
                            <Badge variant="warning">
                              {row.out_of_office_return_date
                                ? t('customer.agents.delivery_statuses.out_of_office_until', { date: formatDateOnly(row.out_of_office_return_date) })
                                : t('customer.agents.delivery_statuses.out_of_office')}
                            </Badge>
                          ) : (
                            <Badge variant={getStatusBadgeVariant(row.delivery_status)}>
                              {t(`customer.agents.delivery_statuses.${row.delivery_status}`)}
                            </Badge>
                          )}
                          {getInterestTagConfig(row.lead.interest_tag) && (
                            <Badge
                              variant={getInterestTagConfig(row.lead.interest_tag)?.variant}
                              size="sm"
                            >
                              {t(`customer.agents.interest_tags.${getInterestTagConfig(row.lead.interest_tag)?.key}`)}
                            </Badge>
                          )}
                        </div>
                      </TableCell>
                      <TableCell>
                        <span className="font-medium text-[var(--foreground)]">{row.total_messages_sent}</span>
                        <span className="ml-1 text-[var(--foreground-muted)]">{t('customer.agents.table.messages_sent')}</span>
                      </TableCell>
                    </TableRow>
                  ))
                )}
              </TableBody>
            </Table>
          </div>

          {pagination.total_pages > 1 && (
            <div className="mt-4 flex items-center justify-between">
              <span className="text-xs text-[var(--foreground-muted)]">
                {t('customer.agents.pagination.page_of', {
                  current: pagination.current_page,
                  total: pagination.total_pages
                })}
              </span>
              <div className="flex gap-2">
                <Button
                  variant="secondary"
                  size="sm"
                  onClick={() => goToPage(pagination.current_page - 1)}
                  disabled={pagination.current_page <= 1}
                >
                  {t('customer.agents.pagination.previous')}
                </Button>
                <Button
                  variant="secondary"
                  size="sm"
                  onClick={() => goToPage(pagination.current_page + 1)}
                  disabled={pagination.current_page >= pagination.total_pages}
                >
                  {t('customer.agents.pagination.next')}
                </Button>
              </div>
            </div>
          )}
        </div>
      </div>

      <SlideOver
        open={isModalOpen}
        onClose={closeLeadModal}
        width={1180}
        className="max-w-[72vw] bg-[var(--background-secondary)]"
      >
        {loadingLead ? (
          <div className="flex h-full items-center justify-center text-[var(--foreground-muted)]">
            {t('common.loading')}
          </div>
        ) : modalError ? (
          <div className="flex h-full flex-col items-center justify-center gap-3 p-8 text-center">
            <AlertCircle className="h-8 w-8 text-[var(--error)]" />
            <p className="text-sm text-[var(--foreground-muted)]">{modalError}</p>
          </div>
        ) : modalData ? (
          <div className="grid h-full min-h-0 grid-cols-5 bg-[var(--background-secondary)]/72">
            <aside className="col-span-2 min-h-0 overflow-y-auto border-r border-[var(--border)] bg-[var(--background-secondary)]/96 p-6 custom-scrollbar">
              <div className="space-y-5">
                <div className="rounded-[28px] border border-white/[0.08] bg-[linear-gradient(180deg,#232932_0%,#1c2128_100%)] p-5 shadow-[var(--shadow-md)]">
                  <div className="flex items-center gap-4">
                  <div className="relative shrink-0">
                    {modalData.linkedin_profile_photo_url ? (
                      <img
                        src={modalData.linkedin_profile_photo_url}
                        alt={modalData.display_name}
                        className="h-14 w-14 rounded-full border border-[var(--border)] object-cover"
                        onError={(e) => {
                          e.currentTarget.style.display = 'none'
                          e.currentTarget.nextElementSibling?.classList.remove('hidden')
                        }}
                      />
                    ) : null}
                    <div className={`flex h-14 w-14 items-center justify-center rounded-full border border-[var(--border)] bg-[linear-gradient(135deg,#35cade,#69e0ee)] text-xl font-bold text-[#081419] ${modalData.linkedin_profile_photo_url ? 'hidden' : ''}`}>
                      {(modalData.display_name || modalData.email).charAt(0)}
                    </div>
                  </div>
                  <div>
                    <h2 className="text-[22px] font-semibold tracking-[-0.02em] text-[var(--foreground)]">{modalData.display_name}</h2>
                    <p className="text-sm text-[var(--foreground-muted)]">{modalData.email}</p>
                  </div>
                </div>
                  <div className="mt-4 flex flex-wrap items-center gap-2">
                    <Badge variant={modalData.blacklisted ? 'warning' : 'success'}>
                      {modalData.blacklisted ? t('customer.agents.modal.blacklisted') : t('customer.agents.modal.active')}
                    </Badge>
                    {modalData.company && <Badge variant="default">{modalData.company}</Badge>}
                  </div>
                </div>

                <div className="space-y-2 rounded-[24px] border border-[var(--border)] bg-[var(--card)] p-4 text-sm shadow-[var(--shadow-sm)]">
                  <p className="flex items-start gap-2 text-[var(--foreground-muted)]"><Mail className="mt-0.5 h-4 w-4 shrink-0" />{modalData.email}</p>
                  {modalData.job_title && <p className="flex items-start gap-2 text-[var(--foreground-muted)]"><Briefcase className="mt-0.5 h-4 w-4 shrink-0" />{modalData.job_title}</p>}
                  {modalData.company && <p className="flex items-start gap-2 text-[var(--foreground-muted)]"><Building2 className="mt-0.5 h-4 w-4 shrink-0" />{modalData.company}</p>}
                  {modalData.location && <p className="flex items-start gap-2 text-[var(--foreground-muted)]"><MapPin className="mt-0.5 h-4 w-4 shrink-0" />{modalData.location}</p>}
                  {modalData.timezone && <p className="flex items-start gap-2 text-[var(--foreground-muted)]"><Clock className="mt-0.5 h-4 w-4 shrink-0" />{modalData.timezone}</p>}
                  {modalData.linkedin_url && (
                    <a href={modalData.linkedin_url} target="_blank" rel="noreferrer" className="flex items-start gap-2 text-[var(--accent)] hover:text-[var(--accent-hover)]">
                      <Linkedin className="mt-0.5 h-4 w-4 shrink-0" />
                      {t('customer.agents.modal.view_linkedin')}
                    </a>
                  )}
                  {modalData.company_website && (
                    <a
                      href={modalData.company_website.startsWith('http') ? modalData.company_website : `https://${modalData.company_website}`}
                      target="_blank"
                      rel="noreferrer"
                      className="flex items-start gap-2 text-[var(--accent)] hover:text-[var(--accent-hover)]"
                    >
                      <Globe className="mt-0.5 h-4 w-4 shrink-0" />
                      {modalData.company_website}
                    </a>
                  )}
                </div>

                {modalData.buying_signals_relevance_rating && (
                  <div className="rounded-[24px] border border-[var(--accent)]/20 bg-[var(--accent)]/8 p-4 shadow-[var(--shadow-sm)]">
                    <p className="text-xs uppercase tracking-wide text-[var(--foreground-subtle)]">
                      {t('customer.agents.buying_signals.buying_signal_relevance')}
                    </p>
                    <p className="mt-1 text-2xl font-semibold text-[var(--foreground)]">
                      {t('customer.agents.buying_signals.rating_value', { rating: modalData.buying_signals_relevance_rating })}
                    </p>
                  </div>
                )}

                <div className="space-y-2.5">
                  {canManuallyUpdateInterestStatus && (
                    <div className="rounded-[20px] border border-[var(--border)] bg-[var(--card)] px-4 py-3 shadow-[var(--shadow-sm)]">
                      <div className="flex items-start justify-between gap-3">
                        <div>
                          <p className="text-xs uppercase tracking-wide text-[var(--foreground-subtle)]">{t('customer.agents.modal.lead_status')}</p>
                          <p className="mt-1 text-sm font-medium text-[var(--foreground)]">
                            {currentInterestStatus === 'interested'
                              ? t('customer.agents.interest_tags.interested')
                              : currentInterestStatus === 'meeting_request'
                                ? t('customer.agents.interest_tags.meeting_request')
                              : currentInterestStatus === 'not_interested'
                                ? t('customer.agents.interest_tags.not_interested')
                                : currentInterestStatus === 'wrong_person'
                                   ? t('customer.agents.interest_tags.wrong_person')
                                   : t('customer.agents.modal.not_set')}
                          </p>
                          <p className="mt-1 text-xs text-[var(--foreground-muted)]">
                            {targetMailbox
                              ? t('customer.agents.modal.uses_mailbox', { email: targetMailbox.email })
                              : t('customer.agents.modal.creates_conversation')}
                          </p>
                        </div>
                        {updatingInterestStatus && (
                          <span className="text-xs text-[var(--foreground-muted)]">{t('customer_settings.common.saving')}</span>
                        )}
                      </div>

                      <select
                        value={currentInterestStatus || ''}
                        disabled={updatingInterestStatus}
                        onChange={(event) => handleInterestStatusChange(event.target.value as ManualInterestStatus)}
                        className="mt-3 h-10 w-full rounded-xl border border-[var(--input-border)] bg-[var(--input)] px-3.5 text-sm text-[var(--foreground)] shadow-[inset_0_1px_0_rgba(255,255,255,0.03)] transition-all focus:border-[var(--ring)] focus:outline-none focus:ring-2 focus:ring-[rgba(53,202,222,0.12)] disabled:cursor-not-allowed disabled:opacity-60"
                        aria-label={t('customer.agents.modal.lead_status')}
                      >
                        <option value="" disabled>
                          {t('customer.agents.modal.not_set')}
                        </option>
                        {MANUAL_INTEREST_STATUSES.map((status) => (
                          <option key={status} value={status}>
                            {t(`customer.agents.interest_tags.${status}`)}
                          </option>
                        ))}
                      </select>
                    </div>
                  )}

                <div className="space-y-3">
                  {(modalData.linkedin_headline || modalData.linkedin_summary) && (
                    <EnrichmentCard
                      icon={Linkedin}
                      title={t('customer.agents.modal.enrichment.linkedin_profile')}
                      date={modalData.linkedin_scraped_at}
                      expanded={expandedSections.has('linkedin_profile')}
                      onToggle={() => toggleSection('linkedin_profile')}
                    >
                      {modalData.linkedin_headline && (
                        <div>
                          <p className="mb-0.5 text-xs uppercase tracking-wide text-[var(--foreground-subtle)]">{t('customer.agents.modal.enrichment.headline')}</p>
                          <p className="text-sm text-[var(--foreground)]">{modalData.linkedin_headline}</p>
                        </div>
                      )}
                      {modalData.linkedin_summary && (
                        <div>
                          <p className="mb-0.5 text-xs uppercase tracking-wide text-[var(--foreground-subtle)]">{t('customer.agents.modal.enrichment.summary')}</p>
                          <p className="whitespace-pre-wrap text-sm text-[var(--foreground)]">{modalData.linkedin_summary}</p>
                        </div>
                      )}
                    </EnrichmentCard>
                  )}

                  {modalData.company_website_scraped_at && (
                    <EnrichmentCard
                      icon={Building2}
                      title={t('customer.agents.modal.enrichment.company_summary')}
                      date={modalData.company_website_scraped_at}
                      expanded={expandedSections.has('company_info')}
                      onToggle={() => toggleSection('company_info')}
                    >
                      {modalData.company_website_summary ? (
                        <p className="whitespace-pre-wrap text-sm text-[var(--foreground)]">{modalData.company_website_summary}</p>
                      ) : (
                        <p className="text-sm italic text-[var(--foreground-muted)]">{t('customer.agents.modal.enrichment.no_summary')}</p>
                      )}
                    </EnrichmentCard>
                  )}

                  {modalData.linkedin_posts && modalData.linkedin_posts.length > 0 && (
                    <EnrichmentCard
                      icon={MessageSquare}
                      title={t('customer.agents.modal.enrichment.linkedin_posts', { count: modalData.linkedin_posts.length })}
                      date={modalData.linkedin_posts_scraped_at}
                      expanded={expandedSections.has('linkedin_posts')}
                      onToggle={() => toggleSection('linkedin_posts')}
                    >
                      <div className="space-y-3">
                        {modalData.linkedin_posts.map((post) => (
                          <div key={`${post.url || 'post'}-${post.date || 'undated'}-${(post.text || '').slice(0, 32)}`} className="border-l-2 border-[var(--border)] pl-3 text-sm">
                            <p className="line-clamp-4 text-[var(--foreground)]">{post.text || t('customer.agents.modal.enrichment.post_unavailable')}</p>
                            <div className="mt-1 flex items-center gap-2">
                              {post.date && <span className="text-xs text-[var(--foreground-subtle)]">{post.date}</span>}
                              {post.url && (
                                <a href={post.url} target="_blank" rel="noreferrer" className="text-xs text-[var(--accent)] hover:text-[var(--accent-hover)]">
                                  {t('customer.agents.modal.enrichment.view_post')}
                                </a>
                              )}
                            </div>
                          </div>
                        ))}
                      </div>
                    </EnrichmentCard>
                  )}

                  {modalData.custom_fields && Object.keys(modalData.custom_fields).length > 0 && (
                    <EnrichmentCard
                      icon={Briefcase}
                      title={t('customer.agents.modal.enrichment.custom_fields')}
                      expanded={expandedSections.has('custom_fields')}
                      onToggle={() => toggleSection('custom_fields')}
                    >
                      <div className="space-y-2">
                        {Object.entries(modalData.custom_fields).map(([key, value]) => (
                          <div key={key}>
                            <p className="mb-0.5 text-xs uppercase tracking-wider text-[var(--foreground-subtle)]">{key.replace(/_/g, ' ')}</p>
                            <p className="break-words text-sm text-[var(--foreground)]">{typeof value === 'object' ? JSON.stringify(value) : String(value)}</p>
                          </div>
                        ))}
                      </div>
                    </EnrichmentCard>
                  )}
                </div>

                <div>
                <h3 className="mb-2 text-sm font-semibold text-[var(--foreground)]">{t('customer.agents.modal.assigned_agents')}</h3>
                <div className="space-y-2">
                  {modalData.agent_leads.map((assignment) => (
                    <div key={assignment.id} className="rounded-[20px] border border-[var(--border)] bg-[var(--card)] px-4 py-3 shadow-[var(--shadow-sm)]">
                      <div className="flex items-center justify-between gap-2">
                        <span className="text-sm text-[var(--foreground)]">{assignment.agent.name}</span>
                        <Badge variant={getStatusBadgeVariant(assignment.delivery_status)} size="sm">
                          {t(`customer.agents.delivery_statuses.${assignment.delivery_status}`)}
                        </Badge>
                      </div>
                    </div>
                  ))}
                </div>
                </div>
              </div>
              </div>
            </aside>

            <section className="col-span-3 min-h-0 overflow-y-auto bg-[var(--background)]/45 p-6 custom-scrollbar">
              <div className="sticky top-0 z-10 -mx-6 mb-6 bg-[var(--background)] px-6 pt-2 backdrop-blur-sm">
                <div role="tablist" aria-label={t('customer.agents.modal.detail_tabs_label')} className="relative z-[1] flex items-stretch">
                  <button
                    type="button"
                    role="tab"
                    aria-selected={activeModalTab === 'messages'}
                    onClick={() => setActiveModalTab('messages')}
                    className={`px-4 py-2.5 text-left transition-all duration-200 select-none border ${activeModalTab === 'messages'
                      ? 'rounded-t-lg border-white/[0.08] border-b-transparent bg-[var(--background)] text-[var(--accent)]'
                      : 'border-transparent border-b-white/[0.06] text-[var(--foreground-subtle)] hover:text-[var(--foreground)] hover:bg-white/[0.03] hover:rounded-t-lg'
                    }`}
                  >
                    <span className="block text-sm font-semibold">{t('customer.agents.modal.messages_tab')}</span>
                    <span className="mt-0.5 block text-xs opacity-60">{lastMessageDate || '—'}</span>
                  </button>

                  {buyingSignalsAvailable && (
                    <button
                      type="button"
                      role="tab"
                      aria-selected={activeModalTab === 'buying_signals'}
                      onClick={() => setActiveModalTab('buying_signals')}
                      className={`px-4 py-2.5 text-left transition-all duration-200 select-none border ${activeModalTab === 'buying_signals'
                        ? 'rounded-t-lg border-white/[0.08] border-b-transparent bg-[var(--background)] text-[var(--accent)]'
                        : 'border-transparent border-b-white/[0.06] text-[var(--foreground-subtle)] hover:text-[var(--foreground)] hover:bg-white/[0.03] hover:rounded-t-lg'
                      }`}
                    >
                      <span className="block text-sm font-semibold">{t('customer.agents.modal.buying_signals_tab')}</span>
                      <span className="mt-0.5 block text-xs opacity-60">{lastBuyingSignalsDate || '—'}</span>
                    </button>
                  )}

                  <div className="flex-1 border-b border-b-white/[0.06]" />
                </div>
              </div>

              {activeModalTab === 'messages' ? (
                timeline.length === 0 ? (
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
                          <span className="text-[var(--foreground-muted)]">{formatDate(entry.timestamp.toISOString())}</span>
                        </div>
                        <p className="text-sm font-semibold text-[var(--foreground)]">{entry.subject}</p>
                        <p className="mt-1 text-xs text-[var(--foreground-muted)]">{entry.from}</p>
                        <p className="mt-2 whitespace-pre-wrap text-sm text-[var(--foreground)]">{entry.body || t('customer.agents.modal.messages.empty_body')}</p>
                      </article>
                    ))}
                    {canOpenReplyCenterConversation && (
                      <div className="flex justify-center pt-2">
                        <Button
                          type="button"
                          variant="primary"
                          size="md"
                          icon={<MessageSquare className="h-4 w-4" />}
                          disabled={openingReplyConversation}
                          onClick={handleOpenReplyConversation}
                        >
                          {t('customer.agents.modal.messages.write_reply')}
                        </Button>
                      </div>
                    )}
                  </div>
                )
              ) : (
                buyingSignalsAvailable ? (
                  <div className="space-y-4">
                    <BuyingSignalsHighlights
                      highlights={modalData.buying_signals_highlights}
                    />
                    <div className="rounded-lg border border-[var(--border)] bg-[var(--card)] p-5 shadow-[var(--shadow-sm)]">
                      {renderBuyingSignalsMarkdown(modalData.buying_signals_markdown)}
                    </div>
                  </div>
                ) : (
                  <div className="rounded-[24px] border border-dashed border-[var(--border)] bg-[var(--card)] px-4 py-10 text-center shadow-[var(--shadow-sm)]">
                    <Button type="button" onClick={handleBuyingSignalsUpgradeInterest}>
                      {t('customer.agents.buying_signals.upgrade')}
                    </Button>
                  </div>
                )
              )}
            </section>
          </div>
        ) : null}
      </SlideOver>

      {isDownloadModalOpen && (
        <div className="fixed inset-0 z-50 overflow-y-auto">
          <div className="flex min-h-screen items-center justify-center p-4">
            <button
              type="button"
              aria-label={t('common.close')}
              className="fixed inset-0 bg-black/60 backdrop-blur-sm transition-opacity"
              onClick={handleCloseDownloadModal}
            />

            <div className="relative bg-[var(--card)] rounded-xl shadow-2xl max-w-md w-full p-6 border border-[var(--border)]">
              <div className="flex items-start justify-between mb-4 gap-4">
                <div>
                  <h3 className="text-xl font-semibold text-[var(--foreground)]">
                    {t('customer.agents.show.download_modal.title')}
                  </h3>
                  <p className="mt-1 text-sm text-[var(--foreground-muted)]">
                    {t('customer.agents.show.download_modal.description')}
                  </p>
                </div>

                <button
                  type="button"
                  onClick={handleCloseDownloadModal}
                  className="text-[var(--foreground-muted)] hover:text-[var(--foreground)] transition-colors"
                  aria-label={t('common.close')}
                >
                  <X className="w-5 h-5" />
                </button>
              </div>

              <div>
                <label htmlFor="download-agent" className="block text-sm font-medium text-[var(--foreground)] mb-2">
                  {t('customer.agents.show.download_modal.agent_label')}
                </label>
                <select
                  id="download-agent"
                  value={selectedDownloadAgentId}
                  onChange={(event) => setSelectedDownloadAgentId(event.target.value)}
                  className="w-full px-3 py-2 h-9 bg-[var(--input)] border border-[var(--input-border)] rounded-lg text-sm text-[var(--foreground)] transition-all duration-150 focus:outline-none focus:border-[var(--ring)] focus:shadow-[0_0_0_2px_var(--ring-offset),0_0_0_4px_var(--ring)]"
                >
                  <option value="">{t('customer.agents.show.download_modal.choose_agent')}</option>
                  {downloadable_agents.map((downloadableAgent) => (
                    <option key={downloadableAgent.id} value={downloadableAgent.id}>
                      {downloadableAgent.name}
                    </option>
                  ))}
                </select>
              </div>

              <div className="mt-6 flex justify-end gap-3">
                <Button type="button" variant="secondary" onClick={handleCloseDownloadModal}>
                  {t('common.cancel')}
                </Button>
                <Button type="button" onClick={handleDownloadCsv} disabled={!selectedDownloadAgentId}>
                  {t('customer.agents.show.download_modal.confirm_button')}
                </Button>
              </div>
            </div>
          </div>
        </div>
      )}

    </AuthenticatedLayout>
  )
}
