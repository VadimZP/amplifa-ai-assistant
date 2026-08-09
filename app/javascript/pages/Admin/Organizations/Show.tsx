/**
 * Admin Organization Show Page - Overview Tab
 * Displays organization stats, recent activity, and info sidebar
 *
 * Design: Two-column layout with stats grid and activity feed
 */
import { Link, router } from '@inertiajs/react'
import OrganizationTabLayout from '../../../components/Admin/OrganizationTabLayout'
import { Badge } from '../../../components/ui/Badge'
import { Button } from '../../../components/ui/Button'
import { t } from '../../../lib/i18n'
import {
  Pencil,
  Crown
} from 'lucide-react'

interface Account {
  id: number
  email: string
  first_name: string
  last_name: string
  full_name: string
  role: string
  'amplifa_admin?'?: boolean
}

interface Organization {
  id: number
  name: string
  industry: string | null
  size: string | null
  website: string | null
  calendly_url: string | null
  locale: string
  currency: string
  onboarded: boolean
  deactivated_at: string | null
  archived_at: string | null
  created_at: string
  plan_tier: string | null
  monthly_subscription: number | null
  monthly_meeting_limit: number | null
  billing_cycle_started_on: string | null
  current_plan: {
    identifier: string
    name: string
    monthly_meeting_limit: number
    monthly_price: number
  } | null
}

interface Activity {
  id: number
  action: string
  details: Record<string, unknown>
  created_at: string
  account_email: string | null
}

interface Props {
  auth: { account: Account }
  organization: Organization
  recent_activities: Activity[]
  current_tab: string
  flash?: { notice?: string; alert?: string }
}

export default function Show({ auth, organization, recent_activities, current_tab, flash }: Props) {
  const formatDate = (dateString: string) => {
    return new Date(dateString).toLocaleDateString('en-US', {
      year: 'numeric',
      month: 'short',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit'
    })
  }

  const formatAction = (action: string) => {
    return action
      .split('_')
      .map(word => word.charAt(0).toUpperCase() + word.slice(1))
      .join(' ')
  }

  const formatCurrency = (value: number | null) => {
    if (value === null) {
      return '—'
    }

    try {
      return new Intl.NumberFormat('en-US', { style: 'currency', currency: organization.currency }).format(value)
    } catch {
      return `${value.toLocaleString()} ${organization.currency}`
    }
  }

  const formatPlanTier = (tier: string | null) => {
    if (!tier) {
      return 'Not set'
    }

    return tier
      .split('_')
      .map(word => word.charAt(0).toUpperCase() + word.slice(1))
      .join(' ')
  }

  const getStatusBadge = () => {
    if (organization.archived_at) {
      return <Badge variant="default">{t('admin.statuses.archived')}</Badge>
    }

    if (organization.deactivated_at) {
      return <Badge variant="error">{t('admin.statuses.deactivated')}</Badge>
    }
    if (organization.onboarded) {
      return <Badge variant="success">{t('admin.statuses.onboarded')}</Badge>
    }
    return <Badge variant="warning">{t('admin.statuses.pending')}</Badge>
  }

  const handleArchive = () => {
    if (!confirm(t('admin.organizations.overview.archive_confirm'))) {
      return
    }

    router.post(`/admin/organizations/${organization.id}/archive`)
  }

  return (
    <OrganizationTabLayout
      organization={organization}
      currentTab={current_tab}
      account={auth.account}
      flash={flash}
      headerActions={
        <Link href={`/admin/organizations/${organization.id}/edit`}>
          <Button variant="secondary" icon={<Pencil className="h-4 w-4" />}>
            {t('admin.common.edit')}
          </Button>
        </Link>
      }
    >
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Main Content - Stats & Activity */}
        <div className="lg:col-span-2 space-y-6">
          {/* Recent Activity */}
          <div>
            <h3 className="text-lg font-semibold text-[var(--foreground)] mb-4">
              {t('admin.organizations.overview.activity_title')}
            </h3>
            <div className="bg-[var(--card)] border border-[var(--border)] rounded-lg divide-y divide-[var(--border)]">
              {recent_activities.length === 0 ? (
                <div className="p-4 text-center text-[var(--foreground-muted)]">
                  {t('admin.organizations.overview.no_activity')}
                </div>
              ) : (
                recent_activities.map((activity) => (
                  <div key={activity.id} className="p-4 flex items-start justify-between">
                    <div>
                      <p className="text-sm font-medium text-[var(--foreground)]">
                        {formatAction(activity.action)}
                      </p>
                      {activity.account_email && (
                        <p className="text-xs text-[var(--foreground-muted)] mt-0.5">
                          {t('admin.organizations.overview.by')} {activity.account_email}
                        </p>
                      )}
                    </div>
                    <span className="text-xs text-[var(--foreground-muted)] whitespace-nowrap">
                      {formatDate(activity.created_at)}
                    </span>
                  </div>
                ))
              )}
            </div>
          </div>
        </div>

        {/* Sidebar - Organization Info */}
        <div>
          <h3 className="text-lg font-semibold text-[var(--foreground)] mb-4">
            {t('admin.organizations.overview.info_title')}
          </h3>
          <div className="bg-[var(--card)] border border-[var(--border)] rounded-lg p-4 space-y-4">
            <div className="flex items-center justify-between">
              <span className="text-sm text-[var(--foreground-muted)]">
                {t('admin.organizations.fields.status')}
              </span>
              {getStatusBadge()}
            </div>

            <div>
              <span className="text-sm text-[var(--foreground-muted)]">
                {t('admin.organizations.fields.created')}
              </span>
              <p className="text-sm text-[var(--foreground)] mt-1">
                {formatDate(organization.created_at)}
              </p>
            </div>

            {organization.website && (
              <div>
                <span className="text-sm text-[var(--foreground-muted)]">
                  {t('admin.organizations.fields.website')}
                </span>
                <a
                  href={organization.website}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-sm text-[var(--accent)] hover:underline mt-1 block truncate"
                >
                  {organization.website}
                </a>
              </div>
            )}

            {organization.industry && (
              <div>
                <span className="text-sm text-[var(--foreground-muted)]">
                  {t('admin.organizations.fields.industry')}
                </span>
                <p className="text-sm text-[var(--foreground)] mt-1">
                  {organization.industry}
                </p>
              </div>
            )}

            {organization.size && (
              <div>
                <span className="text-sm text-[var(--foreground-muted)]">
                  {t('admin.organizations.fields.size')}
                </span>
                <p className="text-sm text-[var(--foreground)] mt-1">
                  {organization.size} {t('admin.organizations.new.size_suffix')}
                </p>
              </div>
            )}

            <div>
              <span className="text-sm text-[var(--foreground-muted)]">
                {t('admin.organizations.fields.locale')}
              </span>
              <p className="text-sm text-[var(--foreground)] mt-1">
                {organization.locale.toUpperCase()} / {organization.currency}
              </p>
            </div>

            {organization.deactivated_at && !organization.archived_at && (
              <div className="pt-4 border-t border-[var(--border)]">
                <div className="bg-[var(--error)]/10 border border-[var(--error)]/20 rounded-lg p-4">
                  <h4 className="text-sm font-semibold text-[var(--error)]">
                    {t('admin.organizations.overview.archive_title')}
                  </h4>
                  <p className="mt-1 text-sm text-[var(--error)]/80">
                    {t('admin.organizations.overview.archive_description')}
                  </p>
                  <Button
                    type="button"
                    variant="destructive"
                    size="sm"
                    className="mt-3"
                    onClick={handleArchive}
                  >
                    {t('admin.organizations.overview.archive_button')}
                  </Button>
                </div>
              </div>
            )}
          </div>

          <div className="bg-[var(--card)] border border-[var(--border)] rounded-lg p-4 space-y-4 mt-4">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <Crown className="size-4 text-[var(--accent)]" />
                <span className="text-sm font-medium text-[var(--foreground)]">Current Plan</span>
              </div>
              <Badge variant="info">Active</Badge>
            </div>

            <div>
              <span className="text-sm text-[var(--foreground-muted)]">Plan</span>
              <p className="text-sm text-[var(--foreground)] mt-1">
                {organization.current_plan?.name || formatPlanTier(organization.plan_tier)}
              </p>
            </div>

            <div>
              <span className="text-sm text-[var(--foreground-muted)]">Monthly Subscription</span>
              <p className="text-sm text-[var(--foreground)] mt-1">
                {formatCurrency(organization.monthly_subscription ?? organization.current_plan?.monthly_price ?? null)}
              </p>
            </div>

            <div>
              <span className="text-sm text-[var(--foreground-muted)]">Meeting Limit / Month</span>
              <p className="text-sm text-[var(--foreground)] mt-1">
                {(organization.monthly_meeting_limit ?? organization.current_plan?.monthly_meeting_limit ?? 0).toLocaleString()}
              </p>
            </div>

            <div>
              <span className="text-sm text-[var(--foreground-muted)]">Billing Starts</span>
              <p className="text-sm text-[var(--foreground)] mt-1">
                {organization.billing_cycle_started_on ? formatDate(organization.billing_cycle_started_on) : 'Not set'}
              </p>
            </div>
          </div>
        </div>
      </div>
    </OrganizationTabLayout>
  )
}
