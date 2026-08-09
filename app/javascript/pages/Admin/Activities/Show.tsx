/**
 * Admin Activities Show Page
 * Activity detail view with cards for different sections
 *
 * Design: Dark theme with Card components
 * Migration: Task 5.3.6 (Phase 5)
 */
import { Link } from '@inertiajs/react'
import AuthenticatedLayout from '../../../layouts/AuthenticatedLayout'
import { t } from '../../../lib/i18n'
import { Card, CardContent, CardHeader } from '../../../components/ui/Card'
import { Badge, BadgeProps } from '../../../components/ui/Badge'
import { ArrowLeft, User, Building2, FileText, Globe, Clock, Hash, Monitor } from 'lucide-react'

interface Account {
  id: number
  email: string
  first_name: string
  last_name: string
  full_name: string
  name: string
  role: string
}

interface Organization {
  id: number
  name: string
  website: string | null
}

interface Activity {
  id: number
  action: string
  details: Record<string, unknown>
  ip_address: string | null
  user_agent: string | null
  created_at: string
  account: Account
  organization: Organization | null
}

interface AdminActivitiesShowProps {
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
  activity: Activity
  flash?: {
    notice?: string
    alert?: string
  }
}

export default function Show({
  auth,
  activity,
  flash
}: AdminActivitiesShowProps) {
  const account = auth.account

  const formatDate = (dateString: string) => {
    return new Date(dateString).toLocaleDateString('en-US', {
      year: 'numeric',
      month: 'long',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
      timeZoneName: 'short'
    })
  }

  const formatActionName = (action: string) => {
    // WHY: Convert action names from snake_case to human-readable format
    return action
      .split('_')
      .map(word => word.charAt(0).toUpperCase() + word.slice(1))
      .join(' ')
  }

  /**
   * Get badge variant for action type
   * - impersonate/login_as: warning (yellow)
   * - create: success (green)
   * - update: info (blue)
   * - delete/deactivate: error (red)
   * - default: default
   */
  const getActionBadgeVariant = (action: string): BadgeProps['variant'] => {
    if (action.includes('impersonate') || action.includes('login_as')) {
      return 'warning'
    } else if (action.includes('create')) {
      return 'success'
    } else if (action.includes('update')) {
      return 'info'
    } else if (action.includes('delete') || action.includes('deactivate')) {
      return 'error'
    }
    return 'default'
  }

  /**
   * Get badge variant for role
   * - amplifa_admin: purple
   * - customer_admin: info (blue)
   * - customer_user: default
   */
  const getRoleBadgeVariant = (role: string): BadgeProps['variant'] => {
    switch (role) {
      case 'amplifa_admin':
        return 'purple'
      case 'customer_admin':
        return 'info'
      case 'customer_user':
      default:
        return 'default'
    }
  }

  const formatRoleName = (role: string) => {
    return t(`admin.roles.${role}`, { defaultValue: role })
  }

  return (
    <AuthenticatedLayout
      title={t('admin.activities.show.title')}
      subtitle={t('admin.activities.show.subtitle')}
      account={account}
      flash={flash}
      headerActions={
        <Link
          href="/admin/activities"
          className="inline-flex items-center justify-center h-9 px-4 gap-2 text-sm font-medium rounded-lg border border-[var(--border-strong)] bg-transparent text-[var(--foreground)] hover:bg-[rgba(255,255,255,0.05)] transition-colors"
        >
          <ArrowLeft className="h-4 w-4" />
          {t('admin.common.back_to_activity_log')}
        </Link>
      }
    >
      {/* Breadcrumb */}
      <nav className="mb-6" aria-label="Breadcrumb">
        <ol className="inline-flex items-center space-x-2 text-sm">
          <li>
            <Link
              href="/admin/dashboard"
              className="text-[var(--foreground-muted)] hover:text-[var(--foreground)] transition-colors"
            >
              {t('admin.activities.show.breadcrumb_dashboard')}
            </Link>
          </li>
          <li className="text-[var(--foreground-subtle)]">/</li>
          <li>
            <Link
              href="/admin/activities"
              className="text-[var(--foreground-muted)] hover:text-[var(--foreground)] transition-colors"
            >
              {t('admin.activities.show.breadcrumb_log')}
            </Link>
          </li>
          <li className="text-[var(--foreground-subtle)]">/</li>
          <li className="text-[var(--foreground)]" aria-current="page">
            {t('admin.activities.show.breadcrumb_activity', { id: activity.id })}
          </li>
        </ol>
      </nav>

      {/* Content Grid */}
      <div className="space-y-6">
        {/* Overview Card */}
        <Card>
          <CardHeader>
            <div className="flex items-center gap-2">
              <FileText className="h-5 w-5 text-[var(--foreground-muted)]" />
              <span>{t('admin.activities.show.overview')}</span>
            </div>
          </CardHeader>
          <CardContent>
            <div className="grid grid-cols-1 gap-6 sm:grid-cols-2">
              <div>
                <dt className="flex items-center gap-2 text-sm font-medium text-[var(--foreground-muted)] mb-1">
                  <Hash className="h-4 w-4" />
                  {t('admin.activities.show.activity_id')}
                </dt>
                <dd className="text-sm text-[var(--foreground)] font-mono">#{activity.id}</dd>
              </div>
              <div>
                <dt className="flex items-center gap-2 text-sm font-medium text-[var(--foreground-muted)] mb-1">
                  <Clock className="h-4 w-4" />
                  {t('admin.activities.show.timestamp')}
                </dt>
                <dd className="text-sm text-[var(--foreground)]">{formatDate(activity.created_at)}</dd>
              </div>
              <div>
                <dt className="text-sm font-medium text-[var(--foreground-muted)] mb-1">
                  {t('admin.activities.show.action_type')}
                </dt>
                <dd>
                  <Badge variant={getActionBadgeVariant(activity.action)}>
                    {formatActionName(activity.action)}
                  </Badge>
                </dd>
              </div>
              <div>
                <dt className="flex items-center gap-2 text-sm font-medium text-[var(--foreground-muted)] mb-1">
                  <Globe className="h-4 w-4" />
                  {t('admin.activities.show.ip_address')}
                </dt>
                <dd className="text-sm text-[var(--foreground)] font-mono">
                  {activity.ip_address || <span className="text-[var(--foreground-subtle)]">{t('admin.common.not_recorded')}</span>}
                </dd>
              </div>
            </div>
          </CardContent>
        </Card>

        {/* Admin Card */}
        <Card>
          <CardHeader>
            <div className="flex items-center gap-2">
              <User className="h-5 w-5 text-[var(--foreground-muted)]" />
              <span>{t('admin.activities.show.performed_by')}</span>
            </div>
          </CardHeader>
          <CardContent>
            <div className="flex items-center gap-4">
              {/* Avatar */}
              <div className="flex-shrink-0 h-12 w-12 rounded-full bg-[var(--accent)]/20 flex items-center justify-center">
                <span className="text-lg font-semibold text-[var(--accent)]">
                  {activity.account.first_name?.charAt(0) || activity.account.name?.charAt(0) || 'A'}
                </span>
              </div>
              {/* User Info */}
              <div className="flex-1 min-w-0">
                <div className="text-base font-semibold text-[var(--foreground)]">
                  {activity.account.full_name || activity.account.name}
                </div>
                <div className="text-sm text-[var(--foreground-muted)]">{activity.account.email}</div>
                <div className="mt-1">
                  <Badge variant={getRoleBadgeVariant(activity.account.role)}>
                    {formatRoleName(activity.account.role)}
                  </Badge>
                </div>
              </div>
            </div>
          </CardContent>
        </Card>

        {/* Organization Card */}
        {activity.organization && (
          <Card>
            <CardHeader>
              <div className="flex items-center gap-2">
                <Building2 className="h-5 w-5 text-[var(--foreground-muted)]" />
                <span>{t('admin.activities.show.related_organization')}</span>
              </div>
            </CardHeader>
            <CardContent>
              <div className="grid grid-cols-1 gap-6 sm:grid-cols-2">
                <div>
                  <dt className="text-sm font-medium text-[var(--foreground-muted)] mb-1">
                    {t('admin.activities.show.organization_name')}
                  </dt>
                  <dd>
                    <Link
                      href={`/admin/organizations/${activity.organization.id}/edit`}
                      className="text-sm font-semibold text-[var(--accent)] hover:text-[var(--accent-hover)] transition-colors"
                    >
                      {activity.organization.name}
                    </Link>
                  </dd>
                </div>
                {activity.organization.website && (
                  <div>
                    <dt className="text-sm font-medium text-[var(--foreground-muted)] mb-1">
                      {t('admin.activities.show.website')}
                    </dt>
                    <dd>
                      <a
                        href={activity.organization.website}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="text-sm text-[var(--accent)] hover:text-[var(--accent-hover)] transition-colors inline-flex items-center gap-1"
                      >
                        {activity.organization.website}
                        <span className="text-xs">↗</span>
                      </a>
                    </dd>
                  </div>
                )}
              </div>
            </CardContent>
          </Card>
        )}

        {/* Details Card */}
        <Card>
          <CardHeader>
            <div className="flex items-center gap-2">
              <FileText className="h-5 w-5 text-[var(--foreground-muted)]" />
              <span>{t('admin.activities.show.action_details')}</span>
            </div>
          </CardHeader>
          <CardContent>
            {activity.details && Object.keys(activity.details).length > 0 ? (
              <div className="bg-[var(--secondary)] rounded-lg p-4 border border-[var(--border)]">
                <pre className="text-sm text-[var(--foreground-muted)] whitespace-pre-wrap overflow-x-auto font-mono">
                  {JSON.stringify(activity.details, null, 2)}
                </pre>
              </div>
            ) : (
              <p className="text-sm text-[var(--foreground-subtle)] italic">
                {t('admin.activities.show.no_details')}
              </p>
            )}
          </CardContent>
        </Card>

        {/* User Agent Card */}
        {activity.user_agent && (
          <Card>
            <CardHeader>
              <div className="flex items-center gap-2">
                <Monitor className="h-5 w-5 text-[var(--foreground-muted)]" />
                <span>{t('admin.activities.show.technical_info')}</span>
              </div>
            </CardHeader>
            <CardContent>
              <div>
                <dt className="text-sm font-medium text-[var(--foreground-muted)] mb-2">
                  {t('admin.activities.show.user_agent')}
                </dt>
                <dd className="text-sm text-[var(--foreground)] font-mono bg-[var(--secondary)] p-3 rounded-lg border border-[var(--border)] break-all">
                  {activity.user_agent}
                </dd>
              </div>
            </CardContent>
          </Card>
        )}
      </div>
    </AuthenticatedLayout>
  )
}
