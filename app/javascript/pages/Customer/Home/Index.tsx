import { useState } from 'react'
import { usePage, router } from '@inertiajs/react'
import AuthenticatedLayout from '../../../layouts/AuthenticatedLayout'
import { t } from '../../../lib/i18n'
import { Card, CardHeader, CardContent } from '../../../components/ui/Card'
import { Button } from '../../../components/ui/Button'
import { Input } from '../../../components/ui/Input'
import { Badge } from '../../../components/ui/Badge'
import {
  Building2,
  ChevronDown,
  Globe,
  Users,
  Mail,
  Ban,
  Plus,
  X,
  CheckCircle,
  Clock,
  ExternalLink,
  Search,
  ChevronLeft,
  ChevronRight,
} from 'lucide-react'

const INITIAL_DOMAINS_VISIBLE = 10
const INITIAL_MAILBOXES_VISIBLE = 10
const INITIAL_SENDER_MAILBOXES_VISIBLE = 20

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface Domain {
  id: number
  domain: string
  provider_type: string
  status: string
  customer_requested: boolean
  last_verified_at: string | null
  mailbox_count: number
}

interface SenderMailbox {
  id: number
  email: string
  status: string
}

interface Sender {
  id: number
  first_name: string
  last_name: string
  full_name: string
  email: string
  job_title: string | null
  status: string
  mailbox_count: number
  active_mailbox_count: number
  mailboxes: SenderMailbox[]
}

interface MailboxItem {
  id: number
  email: string
  status: string
  daily_send_limit: number
  domain: string | null
  sender_name: string | null
  warmup_complete: boolean
  warmup_progress: number
}

interface BlacklistEntry {
  id: number
  value: string
  value_type: string
  source: string
  reason: string | null
  is_global: boolean
  can_delete: boolean
  created_at: string
  created_by: string | null
}

interface BlacklistPagination {
  current_page: number
  total_pages: number
  total_count: number
  per_page: number
}

interface BlacklistFilters {
  search: string
}

interface HomeProps {
  organization: {
    id: number
    name: string
    website: string | null
    industry: string | null
    average_contract_value: number | null
    status: string
    onboarded: boolean
  }
  domains: Domain[]
  domains_count: number
  max_domains: number
  senders: Sender[]
  mailboxes: MailboxItem[]
  blacklists: BlacklistEntry[]
  blacklist_count: number
  blacklist_total_entries: number
  blacklist_filters: BlacklistFilters
  blacklist_pagination: BlacklistPagination
  can_edit: boolean
  user_count: number
}

interface SharedProps {
  [key: string]: unknown
  auth: {
    account: {
      id: number
      email: string
      first_name: string
      last_name: string
      full_name: string
      role: string
    }
    organization?: { id: number; name: string }
  }
  flash?: { notice?: string; alert?: string }
}

// ---------------------------------------------------------------------------
// Status badge helper
// ---------------------------------------------------------------------------

function StatusBadge({ status }: { status: string }) {
  const variantMap: Record<string, 'success' | 'warning' | 'error' | 'info' | 'default'> = {
    active: 'success',
    inactive: 'warning',
    error: 'error',
    paused: 'warning',
    suspended: 'error',
  }
  return <Badge variant={variantMap[status] || 'default'}>{status}</Badge>
}

// ---------------------------------------------------------------------------
// Section 1 – Company
// ---------------------------------------------------------------------------

function CompanySection({
  organization,
}: {
  organization: HomeProps['organization']
}) {
  return (
    <Card>
      <CardHeader
        description={t('customer_home.company.description')}
      >
        <div className="flex items-center gap-2">
          <Building2 className="size-4 text-[var(--foreground-muted)]" strokeWidth={1.5} />
          <span>{t('customer_home.company.title')}</span>
        </div>
      </CardHeader>
      <CardContent>
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-6">
          <div>
            <p className="text-xs text-[var(--foreground-muted)] mb-1">{t('customer_home.company.website')}</p>
            {organization.website ? (
              <a
                href={organization.website}
                target="_blank"
                rel="noopener noreferrer"
                className="text-sm text-[var(--accent)] hover:underline inline-flex items-center gap-1"
              >
                {organization.website.replace(/^https?:\/\//, '')}
                <ExternalLink className="size-3" />
              </a>
            ) : (
              <p className="text-sm text-[var(--foreground-muted)]">{t('customer_home.common.not_set')}</p>
            )}
          </div>
          <div>
            <p className="text-xs text-[var(--foreground-muted)] mb-1">{t('customer_home.company.industry')}</p>
            <p className="text-sm text-[var(--foreground)]">
              {organization.industry || t('customer_home.common.not_set')}
            </p>
          </div>
          <div>
            <p className="text-xs text-[var(--foreground-muted)] mb-1">
              {t('customer_home.company.average_contract_value')}
            </p>
            <p className="text-sm text-[var(--foreground)]">
              {organization.average_contract_value
                ? `€${Number(organization.average_contract_value).toLocaleString()}`
                : t('customer_home.common.not_set')}
            </p>
          </div>
        </div>
      </CardContent>
    </Card>
  )
}

// ---------------------------------------------------------------------------
// Section 2 – Domains
// ---------------------------------------------------------------------------

function DomainsSection({
  domains,
  domainsCount,
  maxDomains,
}: {
  domains: Domain[]
  domainsCount: number
  maxDomains: number
}) {
  const [showAllDomains, setShowAllDomains] = useState(false)

  const visibleDomains = showAllDomains ? domains : domains.slice(0, INITIAL_DOMAINS_VISIBLE)
  const hasMoreDomains = domains.length > INITIAL_DOMAINS_VISIBLE

  return (
    <Card>
      <CardHeader
        description={domainsCount > maxDomains ? t('customer_home.domains.configured', { count: domainsCount }) : t('customer_home.domains.configured_of', { count: domainsCount, max: maxDomains })}
      >
        <div className="flex items-center gap-2">
          <Globe className="size-4 text-[var(--foreground-muted)]" strokeWidth={1.5} />
          <span>{t('customer_home.domains.title')}</span>
        </div>
      </CardHeader>
      <CardContent>
        {domains.length === 0 ? (
          <p className="text-sm text-[var(--foreground-muted)]">
            {t('customer_home.domains.empty')}
          </p>
        ) : (
          <div className="space-y-2">
            {visibleDomains.map((domain) => (
              <div
                key={domain.id}
                className="flex items-center justify-between py-2.5 px-3 rounded-lg bg-white/[0.02] border border-[var(--border)]"
              >
                <div className="flex items-center gap-3">
                  <span className="text-sm font-medium text-[var(--foreground)]">
                    {domain.domain}
                  </span>
                  {domain.customer_requested && (
                    <Badge variant="info" size="sm">
                      <Clock className="size-3 mr-0.5" />
                      {t('customer_home.domains.pending_setup')}
                    </Badge>
                  )}
                </div>
                <div className="flex items-center gap-3">
                  <span className="text-xs text-[var(--foreground-muted)]">
                    {t('customer_home.domains.mailboxes_count', { count: domain.mailbox_count })}
                  </span>
                  <StatusBadge status={domain.status} />
                </div>
              </div>
            ))}
            {hasMoreDomains && !showAllDomains && (
              <Button
                type="button"
                variant="ghost"
                size="sm"
                fullWidth
                onClick={() => setShowAllDomains(true)}
                icon={<ChevronDown className="size-3.5" />}
              >
                {t('customer_home.common.see_all')}
              </Button>
            )}
          </div>
        )}
      </CardContent>
    </Card>
  )
}

// ---------------------------------------------------------------------------
// Section 3 – Senders
// ---------------------------------------------------------------------------

function SenderItem({ sender }: { sender: Sender }) {
  const [showAllMailboxes, setShowAllMailboxes] = useState(false)

  const visibleMailboxes = showAllMailboxes ? sender.mailboxes : sender.mailboxes.slice(0, INITIAL_SENDER_MAILBOXES_VISIBLE)
  const hasMoreMailboxes = sender.mailboxes.length > INITIAL_SENDER_MAILBOXES_VISIBLE

  return (
    <div className="rounded-lg border border-[var(--border)] bg-white/[0.02] overflow-hidden">
      {/* Sender row */}
      <div className="flex items-center justify-between py-3 px-4">
        <div className="flex items-center gap-3 min-w-0">
          <div className="size-8 rounded-full bg-[var(--accent)]/10 flex items-center justify-center shrink-0">
            <span className="text-xs font-medium text-[var(--accent)]">
              {sender.first_name[0]}
              {sender.last_name[0]}
            </span>
          </div>
          <div className="min-w-0">
            <p className="text-sm font-medium text-[var(--foreground)] truncate">
              {sender.full_name}
            </p>
            <p className="text-xs text-[var(--foreground-muted)] truncate">
              {sender.email}
              {sender.job_title && ` · ${sender.job_title}`}
            </p>
          </div>
        </div>
        <div className="flex items-center gap-3 shrink-0">
          <span className="text-xs text-[var(--foreground-muted)]">
            {t('customer_home.senders.active_mailboxes_count', { count: sender.active_mailbox_count })}
          </span>
          <StatusBadge status={sender.status} />
        </div>
      </div>

      {/* Sender's mailboxes */}
      {sender.mailboxes.length > 0 && (
        <div className="border-t border-[var(--border)] bg-white/[0.01] px-4 py-2">
          <div className="flex flex-wrap gap-2">
            {visibleMailboxes.map((mb) => (
              <span
                key={mb.id}
                className="inline-flex items-center gap-1.5 text-xs text-[var(--foreground-muted)] bg-white/[0.03] px-2 py-1 rounded"
              >
                <Mail className="size-3" strokeWidth={1.5} />
                {mb.email}
                <span
                  className={`size-1.5 rounded-full ${
                    mb.status === 'active'
                      ? 'bg-emerald-400'
                      : mb.status === 'paused'
                        ? 'bg-amber-400'
                        : 'bg-red-400'
                  }`}
                />
              </span>
            ))}
            {hasMoreMailboxes && !showAllMailboxes && (
              <Button
                type="button"
                variant="ghost"
                size="sm"
                onClick={() => setShowAllMailboxes(true)}
                icon={<ChevronDown className="size-3.5" />}
              >
                {t('customer_home.common.see_all')}
              </Button>
            )}
          </div>
        </div>
      )}
    </div>
  )
}

function SendersSection({ senders }: { senders: Sender[] }) {
  return (
    <Card>
      <CardHeader description={t('customer_home.senders.description')}>
        <div className="flex items-center gap-2">
          <Users className="size-4 text-[var(--foreground-muted)]" strokeWidth={1.5} />
          <span>{t('customer_home.senders.title')}</span>
        </div>
      </CardHeader>
      <CardContent>
        {senders.length === 0 ? (
          <p className="text-sm text-[var(--foreground-muted)]">
            {t('customer_home.senders.empty')}
          </p>
        ) : (
          <div className="space-y-3">
            {senders.map((sender) => (
              <SenderItem key={sender.id} sender={sender} />
            ))}
          </div>
        )}
      </CardContent>
    </Card>
  )
}

// ---------------------------------------------------------------------------
// Section 4 – Email Accounts
// ---------------------------------------------------------------------------

function EmailAccountsSection({ mailboxes }: { mailboxes: MailboxItem[] }) {
  const [showAllMailboxes, setShowAllMailboxes] = useState(false)

  const visibleMailboxes = showAllMailboxes ? mailboxes : mailboxes.slice(0, INITIAL_MAILBOXES_VISIBLE)
  const hasMoreMailboxes = mailboxes.length > INITIAL_MAILBOXES_VISIBLE
  const mailboxCountText = t('customer_home.email_accounts.mailboxes_count', { count: mailboxes.length })

  return (
    <Card>
      <CardHeader description={mailboxCountText}>
        <div className="flex items-center gap-2">
          <Mail className="size-4 text-[var(--foreground-muted)]" strokeWidth={1.5} />
          <span>{t('customer_home.email_accounts.title')}</span>
        </div>
      </CardHeader>
      <CardContent>
        {mailboxes.length === 0 ? (
          <p className="text-sm text-[var(--foreground-muted)]">
            {t('customer_home.email_accounts.empty')}
          </p>
        ) : (
          <div className="space-y-2">
            {visibleMailboxes.map((mb) => (
              <div
                key={mb.id}
                className="flex items-center justify-between py-2.5 px-3 rounded-lg bg-white/[0.02] border border-[var(--border)]"
              >
                <div className="flex items-center gap-3 min-w-0">
                  <span className="text-sm font-medium text-[var(--foreground)] truncate">
                    {mb.email}
                  </span>
                  {mb.domain && (
                    <span className="text-xs text-[var(--foreground-muted)]">
                      {mb.domain}
                    </span>
                  )}
                </div>
                <div className="flex items-center gap-3 shrink-0">
                  {mb.sender_name && (
                    <span className="text-xs text-[var(--foreground-muted)]">
                      {mb.sender_name}
                    </span>
                  )}
                  {/* Warmup indicator */}
                  {mb.warmup_complete ? (
                    <span className="inline-flex items-center gap-1 text-xs text-emerald-400">
                      <CheckCircle className="size-3" />
                      {t('customer_home.email_accounts.ready')}
                    </span>
                  ) : (
                    <span className="inline-flex items-center gap-1.5 text-xs text-[var(--foreground-muted)]">
                      <div className="w-16 h-1.5 rounded-full bg-white/10 overflow-hidden">
                        <div
                          className="h-full rounded-full bg-amber-400 transition-all"
                          style={{ width: `${mb.warmup_progress}%` }}
                        />
                      </div>
                      {mb.warmup_progress}%
                    </span>
                  )}
                  <span className="text-xs text-[var(--foreground-muted)]">
                    {mb.daily_send_limit}/day
                  </span>
                  <StatusBadge status={mb.status} />
                </div>
              </div>
            ))}
            {hasMoreMailboxes && !showAllMailboxes && (
              <Button
                type="button"
                variant="ghost"
                size="sm"
                fullWidth
                onClick={() => setShowAllMailboxes(true)}
                icon={<ChevronDown className="size-3.5" />}
              >
                {t('customer_home.common.see_all')}
              </Button>
            )}
          </div>
        )}
      </CardContent>
    </Card>
  )
}

// ---------------------------------------------------------------------------
// Section 5 – Blacklist
// ---------------------------------------------------------------------------

function BlacklistSection({
  blacklists,
  blacklistCount,
  blacklistTotalEntries,
  blacklistFilters,
  blacklistPagination,
  canEdit,
}: {
  blacklists: BlacklistEntry[]
  blacklistCount: number
  blacklistTotalEntries: number
  blacklistFilters: BlacklistFilters
  blacklistPagination: BlacklistPagination
  canEdit: boolean
}) {
  const [newValue, setNewValue] = useState('')
  const [newType, setNewType] = useState<'email' | 'domain'>('email')
  const [submitting, setSubmitting] = useState(false)
  const [deletingId, setDeletingId] = useState<number | null>(null)
  const [searchValue, setSearchValue] = useState(blacklistFilters.search || '')

  const navigate = (params: Record<string, string>) => {
    router.get('/dashboard', params, {
      preserveState: true,
      preserveScroll: true,
    })
  }

  const applySearch = () => {
    const params: Record<string, string> = {}
    if (searchValue.trim()) params.blacklist_search = searchValue.trim()
    navigate(params)
  }

  const goToPage = (page: number) => {
    const params: Record<string, string> = {}
    if (blacklistFilters.search) params.blacklist_search = blacklistFilters.search
    if (page > 1) params.blacklist_page = page.toString()
    navigate(params)
  }

  const handleAdd = () => {
    if (!newValue.trim()) return
    setSubmitting(true)
    router.post(
      '/settings/blacklists',
      { blacklist: { value: newValue.trim(), value_type: newType } },
      {
        preserveScroll: true,
        onFinish: () => {
          setSubmitting(false)
          setNewValue('')
        },
      }
    )
  }

  const handleDelete = (id: number) => {
    setDeletingId(id)
    router.delete(`/settings/blacklists/${id}`, {
      preserveScroll: true,
      onFinish: () => setDeletingId(null),
    })
  }

  const hasSearch = blacklistFilters.search.trim().length > 0
  const description = hasSearch
    ? t('customer_home.blacklist.entries_match', { count: blacklistCount, total: blacklistTotalEntries })
    : blacklistTotalEntries > 0
      ? t('customer_home.blacklist.entries_count', { count: blacklistTotalEntries })
      : undefined

  return (
    <Card>
      <CardHeader description={description}>
        <div className="flex items-center gap-2">
          <Ban className="size-4 text-[var(--foreground-muted)]" strokeWidth={1.5} />
          <span>{t('customer_home.blacklist.title')}</span>
        </div>
      </CardHeader>
      <CardContent>
        <div className="mb-4 relative">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 size-4 text-[var(--foreground-muted)]" />
          <input
            type="text"
            placeholder={t('customer_home.blacklist.search_placeholder')}
            value={searchValue}
            onChange={(e) => setSearchValue(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter') applySearch()
            }}
            onBlur={applySearch}
            className="w-full pl-9 pr-4 py-2 bg-[var(--input)] border border-[var(--input-border)] rounded-lg text-sm text-[var(--foreground)] focus:outline-none focus:ring-2 focus:ring-[var(--accent)]"
          />
        </div>

        {blacklists.length === 0 ? (
          <p className="text-sm text-[var(--foreground-muted)]">
            {t('customer_home.blacklist.empty')}
          </p>
        ) : (
          <div className="space-y-2">
            {blacklists.map((entry) => (
              <div
                key={entry.id}
                className="flex items-center justify-between py-2 px-3 rounded-lg bg-white/[0.02] border border-[var(--border)]"
              >
                <div className="flex items-center gap-3 min-w-0">
                  <span className="text-sm text-[var(--foreground)] truncate">
                    {entry.value}
                  </span>
                  <Badge variant="default" size="sm">
                    {entry.value_type}
                  </Badge>
                  {entry.is_global && (
                    <Badge variant="purple" size="sm">
                      {t('customer_home.blacklist.global')}
                    </Badge>
                  )}
                </div>
                <div className="flex items-center gap-3 shrink-0">
                  <span className="text-xs text-[var(--foreground-muted)]">
                    {entry.source}
                  </span>
                  <span className="text-xs text-[var(--foreground-muted)]">
                    {new Date(entry.created_at).toLocaleDateString()}
                  </span>
                  {entry.can_delete && (
                    <button
                      type="button"
                      onClick={() => handleDelete(entry.id)}
                      disabled={deletingId === entry.id}
                      className="p-1 rounded hover:bg-white/10 text-[var(--foreground-muted)] hover:text-[var(--error)] transition-colors disabled:opacity-50"
                      title={t('customer_home.blacklist.remove_entry')}
                    >
                      <X className="size-3.5" />
                    </button>
                  )}
                </div>
              </div>
            ))}
          </div>
        )}

        {blacklistPagination.total_pages > 1 && (
          <div className="mt-4 flex items-center justify-between">
            <p className="text-xs text-[var(--foreground-muted)]">
              {t('customer_home.blacklist.showing', { start: (blacklistPagination.current_page - 1) * blacklistPagination.per_page + 1, end: Math.min(blacklistPagination.current_page * blacklistPagination.per_page, blacklistPagination.total_count), total: blacklistPagination.total_count })}
            </p>
            <div className="inline-flex items-center gap-2">
              <Button
                variant="ghost"
                size="sm"
                onClick={() => goToPage(blacklistPagination.current_page - 1)}
                disabled={blacklistPagination.current_page === 1}
                icon={<ChevronLeft className="size-4" />}
              >
                {t('customer_home.common.previous')}
              </Button>
              <Button
                variant="ghost"
                size="sm"
                onClick={() => goToPage(blacklistPagination.current_page + 1)}
                disabled={blacklistPagination.current_page === blacklistPagination.total_pages}
                icon={<ChevronRight className="size-4" />}
              >
                {t('customer_home.common.next')}
              </Button>
            </div>
          </div>
        )}

        {canEdit && (
          <div className="mt-4 flex items-end gap-3">
            <div className="flex-1">
              <Input
                placeholder={
                  newType === 'email' ? 'user@example.com' : 'example.com'
                }
                value={newValue}
                onChange={(e) => setNewValue(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === 'Enter') handleAdd()
                }}
              />
            </div>
            <select
              value={newType}
              onChange={(e) => setNewType(e.target.value as 'email' | 'domain')}
              className="h-9 px-3 text-sm rounded-lg border border-[var(--input-border)] bg-[var(--input)] text-[var(--foreground)]"
            >
              <option value="email">{t('customer_home.blacklist.types.email')}</option>
              <option value="domain">{t('customer_home.blacklist.types.domain')}</option>
            </select>
            <Button
              size="sm"
              onClick={handleAdd}
              loading={submitting}
              disabled={!newValue.trim()}
              icon={<Plus className="size-3.5" />}
            >
              {t('common.add')}
            </Button>
          </div>
        )}
      </CardContent>
    </Card>
  )
}

// ---------------------------------------------------------------------------
// Main Page
// ---------------------------------------------------------------------------

export default function Index({
  organization,
  domains,
  domains_count,
  max_domains,
  senders,
  mailboxes,
  blacklists,
  blacklist_count,
  blacklist_total_entries,
  blacklist_filters,
  blacklist_pagination,
  can_edit,
}: HomeProps) {
  const { auth, flash } = usePage<SharedProps>().props

  return (
    <AuthenticatedLayout
      title={t('customer_home.title')}
      account={auth.account}
      organization={auth.organization}
      flash={flash}
    >
      <div className="mx-auto max-w-6xl space-y-5">
        <div>
          <h2 className="text-[32px] font-semibold tracking-[-0.03em] text-[var(--foreground)]">
            {t('customer_home.welcome_back', { name: auth.account.first_name })}
          </h2>
          <p className="mt-2 max-w-2xl text-sm leading-6 text-[var(--foreground-muted)]">
            {t('customer_home.subtitle')}
          </p>
        </div>

        <CompanySection organization={organization} />

        <DomainsSection
          domains={domains}
          domainsCount={domains_count}
          maxDomains={max_domains}
        />

        <SendersSection senders={senders} />

        <EmailAccountsSection mailboxes={mailboxes} />

        <BlacklistSection
          blacklists={blacklists}
          blacklistCount={blacklist_count}
          blacklistTotalEntries={blacklist_total_entries}
          blacklistFilters={blacklist_filters}
          blacklistPagination={blacklist_pagination}
          canEdit={can_edit}
        />
      </div>
    </AuthenticatedLayout>
  )
}
