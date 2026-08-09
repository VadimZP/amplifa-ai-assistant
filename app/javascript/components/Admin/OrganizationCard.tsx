import { Link } from '@inertiajs/react'
import { Building2, Bot, BookOpen, Users, Inbox, Mail } from 'lucide-react'
import { Badge, BadgeProps } from '../ui/Badge'
import { t } from '../../lib/i18n'

interface Organization {
  id: number
  name: string
  industry: string | null
  size: string | null
  onboarded: boolean
  deactivated_at: string | null
  agents_count: number
  playbooks_count: number
  senders_count: number
  mailboxes_count: number
  card_sending_stats: {
    daily_sending_capacity: number
    messages_sent_today: number
    messages_sent_previous_sending_day: number
  }
  ai_reply_agent_enabled: boolean
}

interface OrganizationCardProps {
  organization: Organization
}

export default function OrganizationCard({ organization }: OrganizationCardProps) {
  const getStatusBadgeVariant = (): BadgeProps['variant'] => {
    if (organization.deactivated_at) return 'error'
    if (organization.onboarded) return 'success'
    return 'warning'
  }

  const getStatusLabel = (): string => {
    if (organization.deactivated_at) return t('admin.statuses.deactivated')
    if (organization.onboarded) return t('admin.statuses.onboarded')
    return t('admin.statuses.pending')
  }

  const mainStats = [
    {
      label: t('admin.organizations.card.agents'),
      value: organization.agents_count,
      icon: Bot,
      path: `/admin/organizations/${organization.id}/agents`,
    },
    {
      label: t('admin.organizations.card.playbooks'),
      value: organization.playbooks_count,
      icon: BookOpen,
      path: `/admin/organizations/${organization.id}/playbooks`,
    },
    {
      label: t('admin.organizations.card.senders'),
      value: organization.senders_count,
      icon: Users,
      path: `/admin/organizations/${organization.id}/senders`,
    },
    {
      label: t('admin.organizations.card.mailboxes'),
      value: organization.mailboxes_count,
      icon: Inbox,
      path: `/admin/organizations/${organization.id}/mailboxes`,
    },
  ]

  const sendingStats = [
    {
      label: t('admin.organizations.card.daily_capacity'),
      value: organization.card_sending_stats.daily_sending_capacity,
    },
    {
      label: t('admin.organizations.card.emails_today'),
      value: organization.card_sending_stats.messages_sent_today,
    },
    {
      label: t('admin.organizations.card.previous_sending_day', { defaultValue: 'Previous sending day' }),
      value: organization.card_sending_stats.messages_sent_previous_sending_day,
    },
  ]

  return (
    <div
      className="group relative flex h-full flex-col overflow-hidden rounded-2xl border border-[var(--border)] bg-[var(--card)] shadow-[0_2px_10px_rgba(0,0,0,0.18)] transition-all duration-300 hover:-translate-y-0.5 hover:border-[var(--accent)]/40 hover:shadow-[0_18px_40px_rgba(0,0,0,0.35)] cursor-pointer"
    >
      <div className="absolute inset-x-0 top-0 h-24 bg-gradient-to-b from-[var(--accent)]/12 to-transparent pointer-events-none" />
      <Link
        href={`/admin/organizations/${organization.id}`}
        className="absolute inset-0 z-0"
        aria-label={organization.name}
      />

      <div className="relative z-10 p-5 pb-4 pointer-events-none">
        <div className="flex items-start justify-between gap-4">
          <div className="flex min-w-0 items-start gap-3">
            <div className="flex h-11 w-11 items-center justify-center rounded-xl bg-[var(--accent)]/10 text-[var(--accent)] ring-1 ring-[var(--accent)]/20">
              <Building2 className="h-5 w-5" />
            </div>
            <div className="min-w-0">
              <span
                title={organization.name}
                className="block truncate text-lg font-semibold text-[var(--foreground)] tracking-tight"
              >
                {organization.name}
              </span>
              <div className="mt-1 flex flex-wrap items-center gap-2 text-xs text-[var(--foreground-muted)]">
                <span className="inline-flex items-center gap-1">
                  {organization.industry || t('admin.common.no_industry')}
                </span>
                {organization.size && (
                  <span className="inline-flex items-center rounded-full border border-[var(--border)]/70 bg-[var(--background)]/40 px-2 py-0.5 text-[11px] font-medium text-[var(--foreground-muted)]">
                    {organization.size}
                    {t('admin.organizations.new.size_suffix')}
                  </span>
                )}
              </div>
            </div>
          </div>
          <Badge variant={getStatusBadgeVariant()} className="shrink-0">
            {getStatusLabel()}
          </Badge>
        </div>

        {organization.ai_reply_agent_enabled && (
          <span className="inline-flex items-center gap-1.5 rounded-full border border-amber-400/30 bg-amber-400/10 px-2.5 py-0.5 text-xs font-semibold text-amber-400">
            🤡 {t('admin.organizations.card.ai_reply_agent_on', { defaultValue: 'AI Reply Agent On' })}
          </span>
        )}

        <div className="mt-4 border-t border-[var(--border)]/60 pt-3">
          <div className="mb-3 flex items-center gap-2 text-xs font-semibold uppercase tracking-wide text-[var(--foreground-muted)]">
            <div className="flex h-7 w-7 items-center justify-center rounded-lg bg-blue-500/10 text-blue-400">
              <Mail className="h-4 w-4" />
            </div>
            <span>{t('admin.organizations.card.emails_sent')}</span>
          </div>

          <div className="grid grid-cols-3 gap-2 text-xs">
            {sendingStats.map((stat) => (
              <div key={stat.label} className="rounded-lg border border-[var(--border)]/70 bg-[var(--background)]/40 px-3 py-2">
                <div className="text-[10px] font-semibold uppercase tracking-wide text-[var(--foreground-muted)]">
                  {stat.label}
                </div>
                <div className="mt-1 text-sm font-semibold text-[var(--foreground)] tabular-nums">
                  {stat.value.toLocaleString()}
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>

      <div className="relative z-10 px-5 pb-5 pt-4 grid grid-cols-2 gap-3 flex-grow pointer-events-none">
        {mainStats.map((stat) => (
          <Link
            key={stat.label}
            href={stat.path}
            onClick={(event) => event.stopPropagation()}
            className="pointer-events-auto flex items-center justify-between rounded-xl border border-[var(--border)]/70 bg-[var(--background)]/40 px-3 py-2 text-left transition-all duration-200 hover:border-[var(--accent)]/30 hover:bg-[var(--accent)]/10 hover:shadow-[0_6px_14px_rgba(0,0,0,0.2)] hover:[&_.stat-icon]:bg-[var(--accent)]/10 hover:[&_.stat-icon]:text-[var(--accent)]"
          >
            <div className="flex items-center gap-2">
              <span className="stat-icon flex h-8 w-8 items-center justify-center rounded-lg bg-[var(--card)] text-[var(--foreground-muted)] transition-colors">
                <stat.icon className="h-4 w-4" />
              </span>
              <span className="text-xs font-semibold text-[var(--foreground-muted)]">
                {stat.label}
              </span>
            </div>
            <span className="text-lg font-semibold text-[var(--foreground)] tabular-nums">
              {stat.value}
            </span>
          </Link>
        ))}
      </div>

      <div className="relative z-10 px-5 py-3 border-t border-[var(--border)]/60 bg-[var(--background)]/40 flex items-center justify-end rounded-b-2xl pointer-events-none">
        <Link
          href={`/admin/organizations/${organization.id}/edit`}
          onClick={(e) => e.stopPropagation()}
          className="pointer-events-auto text-xs font-semibold text-[var(--foreground-muted)] hover:text-[var(--foreground)] transition-colors px-3 py-1.5 rounded-md hover:bg-[var(--card)]"
        >
          {t('admin.common.edit')}
        </Link>
      </div>
    </div>
  )
}
