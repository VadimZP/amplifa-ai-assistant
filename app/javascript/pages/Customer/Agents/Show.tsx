/**
 * Customer Agent Detail Page
 * Shows agent details, statistics, leads table, and mailboxes
 *
 * Design: Dark theme with Card components, Badge for status
 * Migration: Task 5.4.2 (Phase 5)
 */
import { Link, router } from '@inertiajs/react'
import { ArrowLeft, CheckCircle, XCircle, Mail, Users, MessageSquare, Calendar, Percent, TrendingUp } from 'lucide-react'
import AuthenticatedLayout from '../../../layouts/AuthenticatedLayout'
import { t } from '../../../lib/i18n'
import { Card, CardContent, CardHeader } from '../../../components/ui/Card'
import { Badge, BadgeProps } from '../../../components/ui/Badge'
import { Button } from '../../../components/ui/Button'
import { Table, TableHeader, TableBody, TableRow, TableHead, TableCell } from '../../../components/ui/Table'

interface Organization {
  id: number
  name: string
}

interface Playbook {
  id: number
  product_name: string
}

interface CreatedBy {
  id: number
  first_name: string
  last_name: string
  full_name: string
}

interface Agent {
  id: number
  name: string
  description: string | null
  status: string
  default_timezone: string | null
  total_leads_count: number
  contacted_count: number
  replied_count: number
  meetings_booked_count: number
  reply_rate: number
  meeting_rate: number
  'can_launch?': boolean
  created_at: string
  updated_at: string
  organization: Organization
  playbook: Playbook | null
  created_by: CreatedBy | null
}

interface Lead {
  id: number
  email: string
  first_name: string | null
  last_name: string | null
  full_name: string | null
  display_name: string
  job_title: string | null
  company: string | null
  blacklisted: boolean
  created_at: string
}

interface Mailbox {
  id: number
  email: string
  display_name: string | null
  status: string
  daily_send_limit: number
  warmup_days_remaining: number | null
  'warmup_complete?': boolean
  warmup_progress_percentage: number
}

interface Pagination {
  current_page: number
  total_pages: number
  total_count: number
  per_page: number
}

interface CustomerAgentsShowProps {
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
  agent: Agent
  leads: Lead[]
  leads_pagination: Pagination
  mailboxes: Mailbox[]
  flash?: {
    notice?: string
    alert?: string
  }
}

/**
 * Get badge variant for agent status
 */
const getStatusBadgeVariant = (status: string): BadgeProps['variant'] => {
  switch (status) {
    case 'draft':
      return 'draft'
    case 'ready':
      return 'info'
    case 'active':
      return 'success'
    case 'paused':
      return 'warning'
    case 'completed':
      return 'approved'
    default:
      return 'default'
  }
}

/**
 * Get badge variant for mailbox status
 */
const getMailboxStatusBadgeVariant = (status: string): BadgeProps['variant'] => {
  switch (status) {
    case 'active':
      return 'success'
    case 'paused':
      return 'draft'
    case 'suspended':
      return 'error'
    default:
      return 'default'
  }
}

export default function Show({ auth, agent, leads, leads_pagination, mailboxes, flash }: CustomerAgentsShowProps) {
  const account = auth.account

  const formatDate = (dateString: string) => {
    return new Date(dateString).toLocaleDateString('en-US', {
      year: 'numeric',
      month: 'long',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit'
    })
  }

  const formatShortDate = (dateString: string) => {
    return new Date(dateString).toLocaleDateString('en-US', {
      year: 'numeric',
      month: 'short',
      day: 'numeric'
    })
  }

  const handleLeadsPageChange = (page: number) => {
    router.get(`/agents/${agent.id}`, { leads_page: page }, { preserveState: true })
  }

  return (
    <AuthenticatedLayout
      title={agent.name}
      account={account}
      flash={flash}
      headerActions={
        <Link
          href="/agents"
          className="inline-flex items-center text-sm text-[var(--foreground-muted)] hover:text-[var(--foreground)] transition-colors"
        >
          <ArrowLeft className="w-4 h-4 mr-1" />
          {t('customer.agents.show.back_to_list')}
        </Link>
      }
    >
      {/* Status Badges */}
      <div className="flex items-center gap-3 mb-8">
        <Badge variant={getStatusBadgeVariant(agent.status)}>
          {t(`customer.agents.statuses.${agent.status}`)}
        </Badge>
        {agent['can_launch?'] ? (
          <Badge variant="success">
            <CheckCircle className="w-3 h-3 mr-1" />
            {t('customer.agents.show.can_launch')}
          </Badge>
        ) : (
          <Badge variant="error">
            <XCircle className="w-3 h-3 mr-1" />
            {t('customer.agents.show.cannot_launch')}
          </Badge>
        )}
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
        {/* Main Content - Left Column */}
        <div className="lg:col-span-2 space-y-8">
          {/* Agent Details */}
          <Card>
            <CardHeader>
              <h3 className="text-lg font-semibold text-[var(--foreground)]">
                {t('customer.agents.show.description_title')}
              </h3>
            </CardHeader>
            <CardContent>
              <p className="text-[var(--foreground-muted)] leading-relaxed">
                {agent.description || t('customer.agents.show.no_description')}
              </p>
              <dl className="mt-6 grid grid-cols-1 gap-4 sm:grid-cols-2">
                <div>
                  <dt className="text-sm font-medium text-[var(--foreground-subtle)]">
                    {t('customer.agents.show.playbook')}
                  </dt>
                  <dd className="mt-1 text-sm text-[var(--foreground)]">
                    {agent.playbook ? (
                      <Link
                        href={`/playbooks/${agent.playbook.id}`}
                        className="text-[var(--accent)] hover:text-[var(--accent-hover)] transition-colors"
                      >
                        {agent.playbook.product_name}
                      </Link>
                    ) : (
                      <span className="text-[var(--foreground-subtle)]">
                        {t('customer.agents.show.no_playbook')}
                      </span>
                    )}
                  </dd>
                </div>
                <div>
                  <dt className="text-sm font-medium text-[var(--foreground-subtle)]">
                    {t('customer.agents.show.default_timezone')}
                  </dt>
                  <dd className="mt-1 text-sm text-[var(--foreground)]">
                    {agent.default_timezone || <span className="text-[var(--foreground-subtle)]">—</span>}
                  </dd>
                </div>
                <div>
                  <dt className="text-sm font-medium text-[var(--foreground-subtle)]">
                    {t('customer.agents.show.created_at')}
                  </dt>
                  <dd className="mt-1 text-sm text-[var(--foreground)]">
                    {formatDate(agent.created_at)}
                  </dd>
                </div>
              </dl>
            </CardContent>
          </Card>

          {/* Campaign Statistics */}
          <Card>
            <CardHeader>
              <h3 className="text-lg font-semibold text-[var(--foreground)]">
                {t('customer.agents.show.stats.title')}
              </h3>
            </CardHeader>
            <CardContent>
              <div className="grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-6">
                <div className="bg-[var(--secondary)] rounded-lg p-4 text-center">
                  <div className="flex items-center justify-center mb-2">
                    <Users className="w-5 h-5 text-[var(--foreground-muted)]" />
                  </div>
                  <dt className="text-xs font-medium text-[var(--foreground-muted)] uppercase tracking-wider">
                    {t('customer.agents.show.stats.total_leads')}
                  </dt>
                  <dd className="mt-2 text-2xl font-bold text-[var(--foreground)]">
                    {agent.total_leads_count}
                  </dd>
                </div>
                <div className="bg-[var(--secondary)] rounded-lg p-4 text-center">
                  <div className="flex items-center justify-center mb-2">
                    <Mail className="w-5 h-5 text-[var(--foreground-muted)]" />
                  </div>
                  <dt className="text-xs font-medium text-[var(--foreground-muted)] uppercase tracking-wider">
                    {t('customer.agents.show.stats.contacted')}
                  </dt>
                  <dd className="mt-2 text-2xl font-bold text-[var(--foreground)]">
                    {agent.contacted_count}
                  </dd>
                </div>
                <div className="bg-[var(--secondary)] rounded-lg p-4 text-center">
                  <div className="flex items-center justify-center mb-2">
                    <MessageSquare className="w-5 h-5 text-[var(--foreground-muted)]" />
                  </div>
                  <dt className="text-xs font-medium text-[var(--foreground-muted)] uppercase tracking-wider">
                    {t('customer.agents.show.stats.replied')}
                  </dt>
                  <dd className="mt-2 text-2xl font-bold text-[var(--foreground)]">
                    {agent.replied_count}
                  </dd>
                </div>
                <div className="bg-[var(--secondary)] rounded-lg p-4 text-center">
                  <div className="flex items-center justify-center mb-2">
                    <Calendar className="w-5 h-5 text-[var(--foreground-muted)]" />
                  </div>
                  <dt className="text-xs font-medium text-[var(--foreground-muted)] uppercase tracking-wider">
                    {t('customer.agents.show.stats.meetings')}
                  </dt>
                  <dd className="mt-2 text-2xl font-bold text-[var(--foreground)]">
                    {agent.meetings_booked_count}
                  </dd>
                </div>
                <div className="bg-[var(--accent)]/10 rounded-lg p-4 text-center">
                  <div className="flex items-center justify-center mb-2">
                    <Percent className="w-5 h-5 text-[var(--accent)]" />
                  </div>
                  <dt className="text-xs font-medium text-[var(--accent)] uppercase tracking-wider">
                    {t('customer.agents.show.stats.reply_rate')}
                  </dt>
                  <dd className="mt-2 text-2xl font-bold text-[var(--accent)]">
                    {agent.reply_rate}%
                  </dd>
                </div>
                <div className="bg-[var(--success)]/10 rounded-lg p-4 text-center">
                  <div className="flex items-center justify-center mb-2">
                    <TrendingUp className="w-5 h-5 text-[var(--success)]" />
                  </div>
                  <dt className="text-xs font-medium text-[var(--success)] uppercase tracking-wider">
                    {t('customer.agents.show.stats.meeting_rate')}
                  </dt>
                  <dd className="mt-2 text-2xl font-bold text-[var(--success)]">
                    {agent.meeting_rate}%
                  </dd>
                </div>
              </div>
            </CardContent>
          </Card>

          {/* Assigned Leads */}
          <Card>
            <CardHeader>
              <h3 className="text-lg font-semibold text-[var(--foreground)]">
                {t('customer.agents.show.leads.title')} ({leads_pagination.total_count})
              </h3>
            </CardHeader>
            <CardContent className="p-0">
              {leads.length === 0 ? (
                <p className="px-6 pb-6 text-sm text-[var(--foreground-muted)]">
                  {t('customer.agents.show.leads.empty')}
                </p>
              ) : (
                <>
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead>{t('customer.agents.show.leads.email')}</TableHead>
                        <TableHead>{t('customer.agents.show.leads.name')}</TableHead>
                        <TableHead>{t('customer.agents.show.leads.company')}</TableHead>
                        <TableHead>{t('customer.agents.show.leads.status')}</TableHead>
                        <TableHead>{t('customer.agents.show.leads.created')}</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {leads.map((lead) => (
                        <TableRow key={lead.id}>
                          <TableCell variant="primary">{lead.email}</TableCell>
                          <TableCell>{lead.display_name}</TableCell>
                          <TableCell>{lead.company || '—'}</TableCell>
                          <TableCell>
                            {lead.blacklisted ? (
                              <Badge variant="error">
                                {t('customer.agents.show.leads.blacklisted')}
                              </Badge>
                            ) : (
                              <Badge variant="success">
                                {t('customer.agents.show.leads.active')}
                              </Badge>
                            )}
                          </TableCell>
                          <TableCell>{formatShortDate(lead.created_at)}</TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                  {/* Pagination */}
                  {leads_pagination.total_pages > 1 && (
                    <div className="px-6 py-4 flex items-center justify-between border-t border-[var(--border)]">
                      <div className="text-sm text-[var(--foreground-muted)]">
                        {t('customer.agents.pagination.page_of', {
                          current: leads_pagination.current_page,
                          total: leads_pagination.total_pages
                        })}
                      </div>
                      <div className="flex gap-2">
                        <Button
                          variant="secondary"
                          size="sm"
                          onClick={() => handleLeadsPageChange(leads_pagination.current_page - 1)}
                          disabled={leads_pagination.current_page <= 1}
                        >
                          {t('customer.agents.pagination.previous')}
                        </Button>
                        <Button
                          variant="secondary"
                          size="sm"
                          onClick={() => handleLeadsPageChange(leads_pagination.current_page + 1)}
                          disabled={leads_pagination.current_page >= leads_pagination.total_pages}
                        >
                          {t('customer.agents.pagination.next')}
                        </Button>
                      </div>
                    </div>
                  )}
                </>
              )}
            </CardContent>
          </Card>
        </div>

        {/* Sidebar - Right Column */}
        <div className="space-y-8">
          {/* Mailboxes */}
          <Card>
            <CardHeader>
              <div className="flex items-center gap-2">
                <Mail className="w-5 h-5 text-[var(--foreground-muted)]" />
                <h3 className="text-lg font-semibold text-[var(--foreground)]">
                  {t('customer.agents.show.mailboxes.title')} ({mailboxes.length})
                </h3>
              </div>
            </CardHeader>
            <CardContent>
              {mailboxes.length === 0 ? (
                <p className="text-sm text-[var(--foreground-muted)]">
                  {t('customer.agents.show.mailboxes.empty')}
                </p>
              ) : (
                <ul className="space-y-3">
                  {mailboxes.map((mailbox) => (
                    <li
                      key={mailbox.id}
                      className="border border-[var(--border)] rounded-lg p-3"
                    >
                      <div className="flex items-start justify-between">
                        <div className="flex-1 min-w-0">
                          <p className="text-sm font-medium text-[var(--foreground)] truncate">
                            {mailbox.email}
                          </p>
                          {mailbox.display_name && (
                            <p className="text-xs text-[var(--foreground-muted)] truncate">
                              {mailbox.display_name}
                            </p>
                          )}
                        </div>
                        <Badge variant={getMailboxStatusBadgeVariant(mailbox.status)}>
                          {t(`customer.agents.show.mailboxes.statuses.${mailbox.status}`)}
                        </Badge>
                      </div>
                      <div className="mt-2 flex items-center gap-2 text-xs text-[var(--foreground-muted)]">
                        <span>
                          {mailbox['warmup_complete?'] ? (
                            <span className="text-[var(--success)] font-medium">
                              {t('customer.agents.show.mailboxes.warmup_complete')}
                            </span>
                          ) : mailbox.warmup_days_remaining !== null ? (
                            t('customer.agents.show.mailboxes.days_remaining', { days: mailbox.warmup_days_remaining })
                          ) : null}
                        </span>
                      </div>
                      {!mailbox['warmup_complete?'] && mailbox.warmup_progress_percentage > 0 && (
                        <div className="mt-2">
                          <div className="w-full bg-[var(--secondary)] rounded-full h-1.5">
                            <div
                              className="bg-[var(--accent)] h-1.5 rounded-full transition-all"
                              style={{ width: `${mailbox.warmup_progress_percentage}%` }}
                            />
                          </div>
                        </div>
                      )}
                    </li>
                  ))}
                </ul>
              )}
            </CardContent>
          </Card>
        </div>
      </div>

    </AuthenticatedLayout>
  )
}
