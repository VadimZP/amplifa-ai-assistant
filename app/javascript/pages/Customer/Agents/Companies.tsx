import { FormEvent, ReactNode, useEffect, useMemo, useRef, useState } from 'react'
import { Link, router } from '@inertiajs/react'
import { AlertCircle, Briefcase, Building2, ChevronDown, Globe, Linkedin, Search, Users, X } from 'lucide-react'
import AuthenticatedLayout from '../../../layouts/AuthenticatedLayout'
import { getPlaybookGradient } from '../../../layouts/PlaybookLayout'
import { t } from '../../../lib/i18n'
import { renderBuyingSignalsMarkdown } from '../../../lib/renderBuyingSignalsMarkdown'
import { BuyingSignalsHighlights } from '../../../components/BuyingSignalsHighlights'
import { BuyingSignalsRelevanceHeader } from '../../../components/BuyingSignalsRelevanceHeader'
import { Badge, BadgeProps } from '../../../components/ui/Badge'
import { Button } from '../../../components/ui/Button'
import { SlideOver } from '../../../components/ui/SlideOver'
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '../../../components/ui/Table'

interface Agent {
  id: number
  name: string
  playbook_id: number | null
  status: string
  playbook_approved: boolean
}

interface CompanyRowAgent {
  id: number
  name: string
  playbook_id: number | null
  status: string
}

interface CompanyRow {
  id: number
  name: string
  domain: string | null
  website_url: string | null
  summary_available: boolean
  leads_count: number
  agents: CompanyRowAgent[]
  buying_signals_relevance_rating: number | null
  delivery_statuses: string[]
  latest_activity_at: string | null
  created_at: string | null
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

interface ModalLeadAgent {
  id: number
  name: string
  playbook_id: number | null
  delivery_status: string
  last_sent_at: string | null
}

interface ModalLead {
  id: number
  email: string
  display_name: string
  job_title: string | null
  company: string | null
  linkedin_url: string | null
  location: string | null
  blacklisted: boolean
  interest_tag: 'interested' | 'meeting_request' | 'not_interested' | 'wrong_person' | null
  agents: ModalLeadAgent[]
}

interface BuyingSignalsSummary {
  agent: CompanyRowAgent
  status: string | null
  markdown: string
  highlights: string[]
  relevance_rating: number | null
  generated_at: string | null
}

interface CompanyModalData {
  id: number
  name: string
  domain: string | null
  website_url: string | null
  summary: string | null
  summary_generated_at: string | null
  leads: ModalLead[]
  buying_signals_summaries: BuyingSignalsSummary[]
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
  companies: CompanyRow[]
  agents: Agent[]
  status_options: string[]
  status_counts: Record<string, number>
  filters: Filters
  pagination: Pagination
  flash?: { notice?: string; alert?: string }
}

type ModalTab = 'leads' | 'buying_signals'

const AGENT_GRADIENT_STYLES: Record<string, string> = {
  orange: 'bg-gradient-to-r from-orange-500/25 to-amber-500/25 text-orange-300 ring-1 ring-orange-500/20',
  green: 'bg-gradient-to-r from-emerald-500/25 to-teal-500/25 text-emerald-300 ring-1 ring-emerald-500/20',
  blue: 'bg-gradient-to-r from-blue-500/25 to-indigo-500/25 text-blue-300 ring-1 ring-blue-500/20',
  purple: 'bg-gradient-to-r from-purple-500/25 to-violet-500/25 text-purple-300 ring-1 ring-purple-500/20',
}

const AGENT_DOT_COLORS: Record<string, string> = {
  orange: 'bg-orange-400',
  green: 'bg-emerald-400',
  blue: 'bg-blue-400',
  purple: 'bg-purple-400',
}

const agentGradientStyle = (playbookId: number | null): string => {
  const color = playbookId ? getPlaybookGradient(playbookId) : 'blue'
  return AGENT_GRADIENT_STYLES[color] || AGENT_GRADIENT_STYLES.blue
}

const agentDotColor = (playbookId: number | null): string => {
  const color = playbookId ? getPlaybookGradient(playbookId) : 'blue'
  return AGENT_DOT_COLORS[color] || AGENT_DOT_COLORS.blue
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

const INTEREST_TAG_CONFIG: Record<Exclude<ModalLead['interest_tag'], null>, { variant: BadgeProps['variant']; key: Exclude<ModalLead['interest_tag'], null> }> = {
  interested: { variant: 'approved', key: 'interested' },
  meeting_request: { variant: 'success', key: 'meeting_request' },
  not_interested: { variant: 'error', key: 'not_interested' },
  wrong_person: { variant: 'warning', key: 'wrong_person' },
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

const formatEnrichmentDate = (dateString: string | null) => {
  if (!dateString) return null

  return new Date(dateString).toLocaleDateString('en-US', {
    month: 'short',
    day: 'numeric',
    year: 'numeric'
  })
}

function TabButton({
  active,
  title,
  subtitle,
  onClick
}: {
  active: boolean
  title: string
  subtitle: string
  onClick: () => void
}) {
  return (
    <button
      type="button"
      role="tab"
      aria-selected={active}
      onClick={onClick}
      className={`px-4 py-2.5 text-left transition-all duration-200 select-none border ${active
        ? 'rounded-t-lg border-white/[0.08] border-b-transparent bg-[var(--background)] text-[var(--accent)]'
        : 'border-transparent border-b-white/[0.06] text-[var(--foreground-subtle)] hover:text-[var(--foreground)] hover:bg-white/[0.03] hover:rounded-t-lg'
      }`}
    >
      <span className="block text-sm font-semibold">{title}</span>
      <span className="mt-0.5 block text-xs opacity-60">{subtitle}</span>
    </button>
  )
}

function DetailLine({ icon, children }: { icon: ReactNode; children: ReactNode }) {
  return (
    <p className="flex items-start gap-2 text-[var(--foreground-muted)]">
      <span className="mt-0.5 shrink-0">{icon}</span>
      {children}
    </p>
  )
}

export default function Companies({
  auth,
  companies,
  agents,
  status_options,
  status_counts,
  filters,
  pagination,
  flash
}: Props) {
  const account = auth.account
  const [searchInput, setSearchInput] = useState(filters.search || '')
  const [selectedCompanyId, setSelectedCompanyId] = useState<number | null>(null)
  const [isModalOpen, setIsModalOpen] = useState(false)
  const [loadingCompany, setLoadingCompany] = useState(false)
  const [modalError, setModalError] = useState<string | null>(null)
  const [modalData, setModalData] = useState<CompanyModalData | null>(null)
  const [activeModalTab, setActiveModalTab] = useState<ModalTab>('leads')
  const [agentDropdownOpen, setAgentDropdownOpen] = useState(false)
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
    const fetchCompany = async () => {
      if (!selectedCompanyId || !isModalOpen) return

      setLoadingCompany(true)
      setModalError(null)

      try {
        const response = await fetch(`/agents/companies/${selectedCompanyId}/modal`, {
          headers: {
            Accept: 'application/json',
            'X-Requested-With': 'XMLHttpRequest'
          }
        })

        if (!response.ok) {
          throw new Error(`Failed with status ${response.status}`)
        }

        const payload = await response.json() as CompanyModalData
        setActiveModalTab('leads')
        setModalData(payload)
      } catch {
        setModalError(t('customer.agents.companies.modal.load_error'))
      } finally {
        setLoadingCompany(false)
      }
    }

    fetchCompany()
  }, [selectedCompanyId, isModalOpen])

  const handleFilterChange = (key: keyof Filters, value: string | null) => {
    router.get('/agents/companies', {
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

  const activeStatusTab = filters.status || 'all'
  const selectedAgent = filters.agent_id
    ? agents.find(agent => String(agent.id) === String(filters.agent_id))
    : null

  const statusTabs = useMemo(() => ([
    { id: 'all', label: t('common.all_statuses'), count: pagination.total_count },
    ...status_options.map(status => ({
      id: status,
      label: t(`customer.agents.delivery_statuses.${status}`),
      count: status_counts[status] || 0
    }))
  ]), [pagination.total_count, status_counts, status_options])

  const handleStatusTabChange = (tabId: string) => {
    handleFilterChange('status', tabId === 'all' ? null : tabId)
  }

  const goToPage = (page: number) => {
    router.get('/agents/companies', {
      ...filters,
      page
    }, { preserveState: true })
  }

  const buildCompanyModalUrl = (companyId: number) => {
    const url = new URL(window.location.href)
    url.searchParams.set('company_id', String(companyId))

    return `${url.pathname}${url.search}${url.hash}`
  }

  const buildCompaniesListUrl = () => {
    const url = new URL(window.location.href)
    url.searchParams.delete('company_id')

    return `${url.pathname}${url.search}${url.hash}`
  }

  const syncCompanyModalFromUrl = () => {
    const url = new URL(window.location.href)
    const companyIdParam = Number(url.searchParams.get('company_id'))

    if (Number.isFinite(companyIdParam) && companyIdParam > 0) {
      setSelectedCompanyId(companyIdParam)
      setModalData(null)
      setModalError(null)
      setActiveModalTab('leads')
      setIsModalOpen(true)
      return
    }

    setIsModalOpen(false)
    setSelectedCompanyId(null)
    setModalData(null)
    setModalError(null)
  }

  const closeCompanyModal = () => {
    window.history.replaceState({}, '', buildCompaniesListUrl())
    setIsModalOpen(false)
    setSelectedCompanyId(null)
    setModalData(null)
    setModalError(null)
  }

  useEffect(() => {
    syncCompanyModalFromUrl()

    const handlePopState = () => {
      syncCompanyModalFromUrl()
    }

    window.addEventListener('popstate', handlePopState)
    return () => window.removeEventListener('popstate', handlePopState)
  }, [])

  const openCompany = (companyId: number) => {
    window.history.pushState({}, '', buildCompanyModalUrl(companyId))
    setSelectedCompanyId(companyId)
    setModalData(null)
    setModalError(null)
    setActiveModalTab('leads')
    setIsModalOpen(true)
  }

  const latestBuyingSignalsDate = useMemo(() => {
    if (!modalData) return null

    const generatedDates = modalData.buying_signals_summaries
      .map(summary => summary.generated_at)
      .filter((date): date is string => Boolean(date))
      .sort()

    return formatEnrichmentDate(generatedDates[generatedDates.length - 1] || null)
  }, [modalData])

  const companyBuyingSignalsRelevanceRating = useMemo(() => {
    if (!modalData) return null

    const ratings = modalData.buying_signals_summaries
      .map(summary => summary.relevance_rating)
      .filter((rating): rating is number => Boolean(rating))

    return ratings.length > 0 ? Math.max(...ratings) : null
  }, [modalData])

  return (
    <AuthenticatedLayout
      title={t('customer.agents.companies.title')}
      account={account}
      flash={flash}
      fullBleed={true}
      headerActions={
        <Button
          type="button"
          variant="secondary"
          size="sm"
          icon={<Users className="h-4 w-4" />}
          asChild
        >
          <Link href="/agents">
            {t('customer.agents.companies.back_to_leads')}
          </Link>
        </Button>
      }
    >
      <div className="flex h-full min-h-0 flex-col">
        <div className="sticky top-0 z-20 border-b border-[var(--border)] bg-[var(--background)]/94 px-6 py-4 backdrop-blur-sm lg:px-8">
          <div className="flex items-center gap-2">
            <div className="flex items-center gap-0.5" role="tablist">
              {statusTabs.map(filter => {
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
                {selectedAgent && <span className={`h-2 w-2 shrink-0 rounded-full ${agentDotColor(selectedAgent.playbook_id)}`} />}
                <span className="truncate">
                  {selectedAgent?.name || t('customer.agents.filters.all_agents')}
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

            <form className="relative ml-auto" onSubmit={handleSearch}>
              <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-[var(--foreground-muted)]" />
              <input
                className="h-10 w-64 rounded-xl border border-[var(--input-border)] bg-[var(--input)] pl-9 pr-8 text-sm text-[var(--foreground)] placeholder:text-[var(--foreground-subtle)] lg:w-80"
                placeholder={t('customer.agents.companies.filters.search_placeholder')}
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
                  <TableHead>{t('customer.agents.companies.table.last_activity')}</TableHead>
                  <TableHead>{t('customer.agents.companies.table.company')}</TableHead>
                  <TableHead>{t('customer.agents.table.agent')}</TableHead>
                  <TableHead><BuyingSignalsRelevanceHeader /></TableHead>
                  <TableHead>{t('customer.agents.companies.table.leads')}</TableHead>
                  <TableHead>{t('common.status')}</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {companies.length === 0 ? (
                  <TableRow>
                      <TableCell className="py-12 text-center" colSpan={7}>
                      {t('customer.agents.companies.empty.description')}
                    </TableCell>
                  </TableRow>
                ) : (
                  companies.map((company) => (
                    <TableRow key={company.id} onClick={() => openCompany(company.id)}>
                      <TableCell>
                        <span className="text-xs text-[var(--foreground-muted)] whitespace-nowrap">{formatDate(company.created_at)}</span>
                      </TableCell>
                      <TableCell>
                        <span className="text-xs text-[var(--foreground-muted)] whitespace-nowrap">{formatDate(company.latest_activity_at)}</span>
                      </TableCell>
                      <TableCell variant="primary" className="w-[240px] max-w-[240px]">
                        <div className="truncate text-sm font-medium text-[var(--foreground)]" title={company.name}>{company.name}</div>
                      </TableCell>
                      <TableCell className="w-[220px] max-w-[220px] !whitespace-normal">
                        <div className="flex flex-wrap gap-1.5">
                          {company.agents.map(agent => (
                            <span key={agent.id} className={`block overflow-hidden break-words rounded-md px-2 py-0.5 text-xs font-medium ${agentGradientStyle(agent.playbook_id)}`}>{agent.name}</span>
                          ))}
                        </div>
                      </TableCell>
                      <TableCell>
                        <span className="text-sm font-medium text-[var(--foreground)]">
                          {company.buying_signals_relevance_rating
                            ? t('customer.agents.buying_signals.rating_value', { rating: company.buying_signals_relevance_rating })
                            : '—'}
                        </span>
                      </TableCell>
                      <TableCell>
                        <span className="font-medium text-[var(--foreground)]">{company.leads_count}</span>
                        <span className="ml-1 text-[var(--foreground-muted)]">{t('customer.agents.companies.table.leads_suffix')}</span>
                      </TableCell>
                      <TableCell className="align-middle">
                        <div className="flex flex-col items-start justify-center gap-1.5">
                          {company.delivery_statuses.map(status => (
                            <Badge key={status} variant={getStatusBadgeVariant(status)}>
                              {t(`customer.agents.delivery_statuses.${status}`)}
                            </Badge>
                          ))}
                        </div>
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
        onClose={closeCompanyModal}
        width={1180}
        className="max-w-[72vw] bg-[var(--background-secondary)]"
      >
        {loadingCompany ? (
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
                    <div className="flex h-14 w-14 items-center justify-center rounded-full border border-[var(--border)] bg-[linear-gradient(135deg,#35cade,#69e0ee)] text-xl font-bold text-[#081419]">
                      {modalData.name.charAt(0)}
                    </div>
                    <div>
                      <h2 className="text-[22px] font-semibold tracking-[-0.02em] text-[var(--foreground)]">{modalData.name}</h2>
                      <p className="text-sm text-[var(--foreground-muted)]">{modalData.domain || modalData.website_url || '—'}</p>
                    </div>
                  </div>
                  <div className="mt-4 flex flex-wrap items-center gap-2">
                    <Badge variant="default">{t('customer.agents.companies.modal.company')}</Badge>
                    <Badge variant={modalData.summary ? 'success' : 'default'}>
                      {modalData.summary ? t('customer.agents.companies.table.summary_available') : t('customer.agents.companies.table.no_summary')}
                    </Badge>
                  </div>
                </div>

                <div className="space-y-2 rounded-[24px] border border-[var(--border)] bg-[var(--card)] p-4 text-sm shadow-[var(--shadow-sm)]">
                  <DetailLine icon={<Building2 className="h-4 w-4" />}>{modalData.name}</DetailLine>
                  {modalData.domain && <DetailLine icon={<Briefcase className="h-4 w-4" />}>{modalData.domain}</DetailLine>}
                  {modalData.website_url && (
                    <a
                      href={modalData.website_url.startsWith('http') ? modalData.website_url : `https://${modalData.website_url}`}
                      target="_blank"
                      rel="noreferrer"
                      className="flex items-start gap-2 text-[var(--accent)] hover:text-[var(--accent-hover)]"
                    >
                      <Globe className="mt-0.5 h-4 w-4 shrink-0" />
                      {modalData.website_url}
                    </a>
                  )}
                </div>

                {companyBuyingSignalsRelevanceRating && (
                  <div className="rounded-[24px] border border-[var(--accent)]/20 bg-[var(--accent)]/8 p-4 shadow-[var(--shadow-sm)]">
                    <p className="text-xs uppercase tracking-wide text-[var(--foreground-subtle)]">
                      {t('customer.agents.buying_signals.buying_signal_relevance')}
                    </p>
                    <p className="mt-1 text-2xl font-semibold text-[var(--foreground)]">
                      {t('customer.agents.buying_signals.rating_value', { rating: companyBuyingSignalsRelevanceRating })}
                    </p>
                  </div>
                )}

                <div className="rounded-[24px] border border-[var(--border)] bg-[var(--card)] p-4 shadow-[var(--shadow-sm)]">
                  <div className="mb-2 flex items-center justify-between gap-3">
                    <h3 className="text-sm font-semibold text-[var(--foreground)]">{t('customer.agents.companies.modal.company_summary')}</h3>
                    {modalData.summary_generated_at && (
                      <span className="text-[11px] text-[var(--foreground-subtle)]">{formatEnrichmentDate(modalData.summary_generated_at)}</span>
                    )}
                  </div>
                  {modalData.summary ? (
                    <p className="whitespace-pre-wrap text-sm text-[var(--foreground)]">{modalData.summary}</p>
                  ) : (
                    <p className="text-sm italic text-[var(--foreground-muted)]">{t('customer.agents.companies.modal.no_company_summary')}</p>
                  )}
                </div>
              </div>
            </aside>

            <section className="col-span-3 min-h-0 overflow-y-auto bg-[var(--background)]/45 p-6 custom-scrollbar">
              <div className="sticky top-0 z-10 -mx-6 mb-6 bg-[var(--background)] px-6 pt-2 backdrop-blur-sm">
                <div role="tablist" aria-label={t('customer.agents.companies.modal.detail_tabs_label')} className="relative z-[1] flex items-stretch">
                  <TabButton
                    active={activeModalTab === 'leads'}
                    title={t('customer.agents.companies.modal.leads_tab')}
                    subtitle={String(modalData.leads.length)}
                    onClick={() => setActiveModalTab('leads')}
                  />
                  <TabButton
                    active={activeModalTab === 'buying_signals'}
                    title={t('customer.agents.companies.modal.buying_signals_tab')}
                    subtitle={latestBuyingSignalsDate || '—'}
                    onClick={() => setActiveModalTab('buying_signals')}
                  />
                  <div className="flex-1 border-b border-b-white/[0.06]" />
                </div>
              </div>

              {activeModalTab === 'leads' ? (
                modalData.leads.length === 0 ? (
                  <div className="rounded-[24px] border border-dashed border-[var(--border)] bg-[var(--card)] px-4 py-10 text-center text-sm text-[var(--foreground-muted)]">
                    {t('customer.agents.companies.modal.no_leads')}
                  </div>
                ) : (
                  <div className="space-y-4">
                    {modalData.leads.map((lead) => {
                      const interestConfig = lead.interest_tag ? INTEREST_TAG_CONFIG[lead.interest_tag] : null

                      return (
                        <article key={lead.id} className="rounded-[24px] border border-[var(--border)] bg-[var(--card)] p-4 shadow-[var(--shadow-sm)]">
                          <div className="flex items-start justify-between gap-4">
                            <div>
                              <p className="text-sm font-semibold text-[var(--foreground)]">{lead.display_name}</p>
                              <p className="mt-1 text-xs text-[var(--foreground-muted)]">{lead.email}</p>
                              {lead.job_title && <p className="mt-1 text-xs text-[var(--foreground-subtle)]">{lead.job_title}</p>}
                              {lead.location && <p className="mt-1 text-xs text-[var(--foreground-muted)]">{lead.location}</p>}
                              {lead.linkedin_url && (
                                <a href={lead.linkedin_url} target="_blank" rel="noreferrer" className="mt-2 inline-flex items-center gap-1.5 text-xs text-[var(--accent)] hover:text-[var(--accent-hover)]">
                                  <Linkedin className="h-3.5 w-3.5" />
                                  {t('customer.agents.companies.modal.view_linkedin')}
                                </a>
                              )}
                            </div>
                            <div className="flex flex-wrap justify-end gap-1.5">
                              {lead.blacklisted && <Badge variant="warning">{t('customer.agents.modal.blacklisted')}</Badge>}
                              {interestConfig && (
                                <Badge variant={interestConfig.variant} size="sm">
                                  {t(`customer.agents.interest_tags.${interestConfig.key}`)}
                                </Badge>
                              )}
                            </div>
                          </div>

                          <div className="mt-3 flex flex-wrap gap-1.5">
                            {lead.agents.map(agent => (
                              <div key={agent.id} className="flex items-center gap-1.5 rounded-md border border-[var(--border)] px-2 py-1">
                                <span className={`text-xs font-medium ${agentGradientStyle(agent.playbook_id)}`}>{agent.name}</span>
                                <Badge variant={getStatusBadgeVariant(agent.delivery_status)} size="sm">
                                  {t(`customer.agents.delivery_statuses.${agent.delivery_status}`)}
                                </Badge>
                              </div>
                            ))}
                          </div>
                        </article>
                      )
                    })}
                  </div>
                )
              ) : (
                <div className="space-y-4">
                  {modalData.buying_signals_summaries.map((summary) => {
                    const hasSummary = summary.status === 'completed' && summary.markdown.trim().length > 0

                    return (
                      <div key={summary.agent.id} className="space-y-4">
                        {hasSummary && (
                          <BuyingSignalsHighlights
                            highlights={summary.highlights}
                          />
                        )}
                        <article className="rounded-lg border border-[var(--border)] bg-[var(--card)] p-5 shadow-[var(--shadow-sm)]">
                          <div className="mb-4 flex items-center justify-between gap-3">
                            <span className={`block overflow-hidden break-words rounded-md px-2 py-0.5 text-xs font-medium ${agentGradientStyle(summary.agent.playbook_id)}`}>{summary.agent.name}</span>
                            <span className="text-[11px] text-[var(--foreground-subtle)]">{formatEnrichmentDate(summary.generated_at) || '—'}</span>
                          </div>
                          {hasSummary ? (
                            renderBuyingSignalsMarkdown(summary.markdown)
                          ) : (
                            <p className="text-sm italic text-[var(--foreground-muted)]">{t('customer.agents.companies.modal.no_buying_signals')}</p>
                          )}
                        </article>
                      </div>
                    )
                  })}
                </div>
              )}
            </section>
          </div>
        ) : null}
      </SlideOver>
    </AuthenticatedLayout>
  )
}
