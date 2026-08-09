import { Link, router } from '@inertiajs/react'
import { useState } from 'react'
import {
  ChevronDown,
  ChevronRight,
  Globe,
  Mail,
  UserPlus,
  Bot,
  CheckCircle,
  XCircle,
  RefreshCw,
  Search,
  Settings,
  Trash2,
  X,
} from 'lucide-react'
import { Card, CardContent } from '../ui/Card'
import { Badge, BadgeProps } from '../ui/Badge'
import { Button } from '../ui/Button'
import { Table, TableHeader, TableBody, TableRow, TableHead, TableCell } from '../ui/Table'
import { SimpleProgressBar } from '../ui/ProgressBar'
import { t } from '../../lib/i18n'

interface Sender {
  id: number
  full_name: string
  email: string
  job_title: string | null
  status: string
  has_profile_photo: boolean
  profile_photo_url: string | null
}

interface Agent {
  id: number
  name: string
  status: string
}

interface Mailbox {
  id: number
  email: string
  display_name: string | null
  status: string
  daily_send_limit: number
  daily_sends_today: number
  daily_capacity_remaining: number
  warmup_started_at: string | null
  warmup_complete: boolean
  warmup_progress_percentage: number
  can_send: boolean
  sender: Sender | null
  agents: Agent[]
}

interface Domain {
  id: number
  domain: string
  provider_type: string
  status: string
  google_admin_email: string | null
  last_verified_at: string | null
  verification_error: string | null
  created_at: string
  mailbox_count: number
  active_mailbox_count: number
  total_capacity: number
  mailboxes: Mailbox[]
}

interface DomainCardProps {
  domain: Domain
  organizationId: number
  expanded: boolean
  onToggle: () => void
  selectedMailboxIds: Set<number>
  onMailboxSelect: (mailboxId: number) => void
  onAssignSender: (mailboxId: number) => void
  onUnassignSender: (mailboxId: number) => void
  onDeleteMailbox: (mailbox: Mailbox) => void
}

const getStatusBadgeVariant = (status: string): BadgeProps['variant'] => {
  switch (status) {
    case 'active':
      return 'success'
    case 'inactive':
    case 'paused':
      return 'warning'
    case 'error':
    case 'suspended':
      return 'error'
    default:
      return 'default'
  }
}

const getProviderLabel = (providerType: string): string => {
  switch (providerType) {
    case 'google':
      return 'Google Workspace'
    case 'microsoft':
      return 'Microsoft 365'
    default:
      return providerType
  }
}

export function DomainCard({
  domain,
  organizationId,
  expanded,
  onToggle,
  selectedMailboxIds,
  onMailboxSelect,
  onAssignSender,
  onUnassignSender,
  onDeleteMailbox,
}: DomainCardProps) {
  const [testingConnection, setTestingConnection] = useState(false)
  const [discoveringMailboxes, setDiscoveringMailboxes] = useState(false)

  const handleTestConnection = (e: React.MouseEvent) => {
    e.stopPropagation()
    setTestingConnection(true)
    router.post(
      `/admin/organizations/${organizationId}/domains/${domain.id}/verify_connection`,
      {},
      {
        preserveScroll: true,
        onFinish: () => setTestingConnection(false),
      }
    )
  }

  const handleDiscoverMailboxes = (e: React.MouseEvent) => {
    e.stopPropagation()
    if (confirm(t('admin.email_domains.discovery_confirm'))) {
      setDiscoveringMailboxes(true)
      router.post(
        `/admin/organizations/${organizationId}/domains/${domain.id}/discover_mailboxes`,
        {},
        {
          preserveScroll: true,
          onFinish: () => setDiscoveringMailboxes(false),
        }
      )
    }
  }

  const allMailboxesSelected = domain.mailboxes.length > 0 && 
    domain.mailboxes.every(m => selectedMailboxIds.has(m.id))
  
  const someMailboxesSelected = domain.mailboxes.some(m => selectedMailboxIds.has(m.id))

  const handleSelectAll = () => {
    if (allMailboxesSelected) {
      domain.mailboxes.forEach(m => {
        if (selectedMailboxIds.has(m.id)) {
          onMailboxSelect(m.id)
        }
      })
    } else {
      domain.mailboxes.forEach(m => {
        if (!selectedMailboxIds.has(m.id)) {
          onMailboxSelect(m.id)
        }
      })
    }
  }

  return (
    <Card className="overflow-hidden">
      <div
        className="flex items-center justify-between px-6 py-4 cursor-pointer hover:bg-[var(--card-hover)] transition-colors"
        onClick={onToggle}
      >
        <div className="flex items-center gap-4">
          <div className="flex items-center gap-2 text-[var(--foreground-muted)]">
            {expanded ? (
              <ChevronDown className="h-5 w-5" />
            ) : (
              <ChevronRight className="h-5 w-5" />
            )}
            <Globe className="h-5 w-5" />
          </div>
          
          <div className="flex flex-col gap-1">
            <div className="flex items-center gap-3">
              <span className="text-lg font-semibold text-[var(--foreground)]">
                {domain.domain}
              </span>
              <Badge variant="default" size="sm">
                {getProviderLabel(domain.provider_type)}
              </Badge>
              <Badge variant={getStatusBadgeVariant(domain.status)} size="sm">
                {t(`admin.email_domains.statuses.${domain.status}`)}
              </Badge>
            </div>
            <div className="flex items-center gap-2 text-sm text-[var(--foreground-muted)]">
              <span>{domain.mailbox_count} {t('admin.email_domains.mailboxes_label')}</span>
              <span>•</span>
              <span>{domain.total_capacity} {t('admin.email_domains.capacity_label')}</span>
              {domain.verification_error && (
                <>
                  <span>•</span>
                  <span className="text-[var(--error)] flex items-center gap-1">
                    <XCircle className="h-3.5 w-3.5" />
                    {domain.verification_error}
                  </span>
                </>
              )}
            </div>
          </div>
        </div>

        <div className="flex items-center gap-2" onClick={e => e.stopPropagation()}>
          <Button
            variant="ghost"
            size="sm"
            onClick={handleTestConnection}
            disabled={testingConnection}
            icon={<RefreshCw className={`h-4 w-4 ${testingConnection ? 'animate-spin' : ''}`} />}
          >
            {testingConnection ? t('admin.email_domains.testing_connection') : t('admin.email_domains.test_connection')}
          </Button>
          <Button
            variant="ghost"
            size="sm"
            onClick={handleDiscoverMailboxes}
            disabled={discoveringMailboxes}
            icon={<Search className={`h-4 w-4 ${discoveringMailboxes ? 'animate-pulse' : ''}`} />}
          >
            {t('admin.email_domains.discover_mailboxes')}
          </Button>
          <Link href={`/admin/organizations/${organizationId}/domains/${domain.id}/edit`}>
            <Button variant="ghost" size="sm" icon={<Settings className="h-4 w-4" />}>
              {t('admin.email_domains.settings')}
            </Button>
          </Link>
        </div>
      </div>

      {expanded && (
        <CardContent className="px-0 pb-0">
          {domain.mailboxes.length === 0 ? (
            <div className="flex flex-col items-center justify-center py-8 text-[var(--foreground-muted)]">
              <Mail className="h-8 w-8 mb-2" />
              <span>{t('admin.email_domains.no_mailboxes')}</span>
            </div>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead className="w-12">
                    <input
                      type="checkbox"
                      checked={allMailboxesSelected}
                      ref={input => {
                        if (input) {
                          input.indeterminate = someMailboxesSelected && !allMailboxesSelected
                        }
                      }}
                      onChange={handleSelectAll}
                      className="h-4 w-4 rounded border-[var(--border)] bg-transparent text-[var(--accent)] focus:ring-[var(--accent)] focus:ring-offset-0"
                    />
                  </TableHead>
                  <TableHead>{t('admin.email_domains.mailbox_table.email')}</TableHead>
                  <TableHead>{t('admin.email_domains.mailbox_table.sender')}</TableHead>
                  <TableHead>{t('admin.email_domains.mailbox_table.agents')}</TableHead>
                  <TableHead>{t('admin.email_domains.mailbox_table.status')}</TableHead>
                  <TableHead>{t('admin.email_domains.mailbox_table.warmup')}</TableHead>
                  <TableHead>{t('admin.email_domains.mailbox_table.capacity')}</TableHead>
                  <TableHead sticky>{t('admin.email_domains.mailbox_table.actions')}</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {domain.mailboxes.map(mailbox => (
                  <MailboxRow
                    key={mailbox.id}
                    mailbox={mailbox}
                    organizationId={organizationId}
                    isSelected={selectedMailboxIds.has(mailbox.id)}
                    onSelect={() => onMailboxSelect(mailbox.id)}
                    onAssignSender={() => onAssignSender(mailbox.id)}
                    onUnassignSender={() => onUnassignSender(mailbox.id)}
                    onDelete={() => onDeleteMailbox(mailbox)}
                  />
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      )}
    </Card>
  )
}

interface MailboxRowProps {
  mailbox: Mailbox
  organizationId: number
  isSelected: boolean
  onSelect: () => void
  onAssignSender: () => void
  onUnassignSender: () => void
  onDelete: () => void
}

function MailboxRow({
  mailbox,
  organizationId,
  isSelected,
  onSelect,
  onAssignSender,
  onUnassignSender,
  onDelete,
}: MailboxRowProps) {
  return (
    <TableRow>
      <TableCell className="w-12">
        <input
          type="checkbox"
          checked={isSelected}
          onChange={onSelect}
          className="h-4 w-4 rounded border-[var(--border)] bg-transparent text-[var(--accent)] focus:ring-[var(--accent)] focus:ring-offset-0"
        />
      </TableCell>
      <TableCell variant="primary">
        <div className="flex items-center gap-2">
          <Mail className="h-4 w-4 text-[var(--foreground-muted)]" />
          <span>{mailbox.email}</span>
        </div>
      </TableCell>
      <TableCell>
        {mailbox.sender ? (
          <Link
            href={`/admin/organizations/${organizationId}/senders/${mailbox.sender.id}`}
            className="flex items-center gap-2 hover:text-[var(--accent)] transition-colors"
          >
            <div className="relative shrink-0">
              {mailbox.sender.profile_photo_url ? (
                <img
                  src={mailbox.sender.profile_photo_url}
                  alt={mailbox.sender.full_name}
                  className="w-7 h-7 rounded-full object-cover"
                />
              ) : (
                <div className="w-7 h-7 rounded-full bg-gradient-to-br from-[var(--accent)] to-purple-600 flex items-center justify-center text-white text-xs font-bold">
                  {mailbox.sender.full_name.charAt(0)}
                </div>
              )}
            </div>
            <div className="flex flex-col">
              <span className="text-sm font-medium text-[var(--foreground)]">
                {mailbox.sender.full_name}
              </span>
              {mailbox.sender.job_title && (
                <span className="text-xs text-[var(--foreground-muted)]">
                  {mailbox.sender.job_title}
                </span>
              )}
            </div>
            <button
              onClick={(e) => {
                e.preventDefault()
                e.stopPropagation()
                onUnassignSender()
              }}
              className="ml-1 p-1 rounded hover:bg-[var(--card-hover)] text-[var(--foreground-muted)] hover:text-[var(--error)] transition-colors"
              title={t('admin.email_domains.unassign_sender')}
            >
              <X className="h-3.5 w-3.5" />
            </button>
          </Link>
        ) : (
          <button
            onClick={onAssignSender}
            className="flex items-center gap-1.5 text-sm text-[var(--accent)] hover:text-[var(--accent-hover)] transition-colors"
          >
            <UserPlus className="h-4 w-4" />
            <span>{t('admin.email_domains.assign_sender')}</span>
          </button>
        )}
      </TableCell>
      <TableCell>
        {mailbox.agents.length > 0 ? (
          <div className="flex items-center gap-1.5">
            <Bot className="h-4 w-4 text-[var(--foreground-muted)]" />
            <span className="truncate max-w-[150px]">
              {mailbox.agents.map(a => a.name).join(', ')}
            </span>
          </div>
        ) : (
          <span className="text-[var(--foreground-subtle)]">
            {t('admin.email_domains.no_agents')}
          </span>
        )}
      </TableCell>
      <TableCell>
        <Badge variant={getStatusBadgeVariant(mailbox.status)} size="sm">
          {t(`admin.mailboxes.statuses.${mailbox.status}`)}
        </Badge>
      </TableCell>
      <TableCell>
        <div className="flex items-center gap-2 min-w-[100px]">
          <SimpleProgressBar
            value={mailbox.warmup_progress_percentage}
            max={100}
            className="flex-1"
          />
          <span className="text-xs text-[var(--foreground-muted)] w-10 text-right">
            {mailbox.warmup_progress_percentage}%
          </span>
        </div>
      </TableCell>
      <TableCell>
        <div className="flex items-center gap-2">
          <span className="font-medium text-[var(--foreground)]">
            {mailbox.daily_sends_today}
          </span>
          <span className="text-[var(--foreground-muted)]">/</span>
          <span className="text-[var(--foreground-muted)]">
            {mailbox.daily_send_limit}
          </span>
          {mailbox.can_send ? (
            <CheckCircle className="h-4 w-4 text-[var(--success)]" />
          ) : (
            <XCircle className="h-4 w-4 text-[var(--foreground-subtle)]" />
          )}
        </div>
      </TableCell>
      <TableCell sticky>
        <div className="flex items-center justify-end gap-2">
          <Link
            href={`/admin/organizations/${organizationId}/mailboxes/${mailbox.id}/edit`}
            className="text-[var(--accent)] hover:text-[var(--accent-hover)] font-medium transition-colors"
          >
            {t('admin.common.edit')}
          </Link>
          <button
            type="button"
            onClick={onDelete}
            className="p-1.5 rounded-lg text-[var(--error)] hover:bg-[var(--error-muted)] transition-colors"
            title={t('admin.common.delete')}
          >
            <Trash2 className="h-4 w-4" />
          </button>
        </div>
      </TableCell>
    </TableRow>
  )
}

export default DomainCard
