/**
 * Admin Activities Index Page
 * Activity log table with filters and pagination
 *
 * Design: Dark theme with Table component, Badge for action types
 * Migration: Task 5.3.6 (Phase 5)
 */
import { Link, router } from '@inertiajs/react'
import AuthenticatedLayout from '../../../layouts/AuthenticatedLayout'
import { useState } from 'react'
import { t } from '../../../lib/i18n'
import { Table, TableHeader, TableBody, TableRow, TableHead, TableCell } from '../../../components/ui/Table'
import { Badge, BadgeProps } from '../../../components/ui/Badge'
import { Card, CardContent } from '../../../components/ui/Card'
import { Button } from '../../../components/ui/Button'
import { ChevronLeft, ChevronRight, Eye, EyeOff, Filter } from 'lucide-react'

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
}

interface Activity {
  id: number
  action: string
  details: Record<string, unknown>
  ip_address: string | null
  user_agent: string | null
  created_at: string
  organization_id: number | null
  account: Account
  organization: Organization | null
}

interface Pagination {
  page: number
  per_page: number
  total: number
  total_pages: number
}

interface Filters {
  organization_id?: string
  action?: string
  start_date?: string
  end_date?: string
}

interface AdminActivitiesIndexProps {
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
  activities: Activity[]
  organizations: Organization[]
  action_types: string[]
  pagination: Pagination
  filters: Filters
  flash?: {
    notice?: string
    alert?: string
  }
}

export default function Index({
  auth,
  activities,
  organizations,
  action_types,
  pagination,
  filters,
  flash
}: AdminActivitiesIndexProps) {
  const account = auth.account
  const [expandedDetails, setExpandedDetails] = useState<Set<number>>(new Set())

  // WHY: Local state for filters to allow user to modify before submitting
  const [localFilters, setLocalFilters] = useState<Filters>(filters)

  const formatDate = (dateString: string) => {
    return new Date(dateString).toLocaleDateString('en-US', {
      year: 'numeric',
      month: 'short',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit'
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

  const toggleDetails = (activityId: number) => {
    // WHY: Toggle expanded/collapsed state for activity details JSON
    setExpandedDetails(prev => {
      const newSet = new Set(prev)
      if (newSet.has(activityId)) {
        newSet.delete(activityId)
      } else {
        newSet.add(activityId)
      }
      return newSet
    })
  }

  const handleFilterChange = (key: keyof Filters, value: string) => {
    setLocalFilters(prev => ({
      ...prev,
      [key]: value || undefined
    }))
  }

  // WHY: Inertia's payload type needs a plain record; dropping undefined values also keeps
  // cleared filters out of the URL.
  const filterParams = (extra: Record<string, string | number> = {}) => ({
    ...Object.fromEntries(Object.entries(localFilters).filter(([, value]) => value !== undefined)),
    ...extra
  })

  const applyFilters = () => {
    // WHY: Submit filters as GET parameters to maintain URL state
    router.get('/admin/activities', filterParams(), {
      preserveState: true,
      preserveScroll: true
    })
  }

  const clearFilters = () => {
    // WHY: Reset all filters and reload page
    setLocalFilters({})
    router.get('/admin/activities', {}, {
      preserveState: false
    })
  }

  const goToPage = (page: number) => {
    // WHY: Navigate to different page while preserving filters
    router.get('/admin/activities', filterParams({ page }), {
      preserveState: true,
      preserveScroll: false
    })
  }

  return (
    <AuthenticatedLayout
      title={t('admin.activities.title')}
      subtitle={t('admin.activities.subtitle')}
      account={account}
      flash={flash}
    >
      {/* Filters Card */}
      <Card className="mb-6">
        <CardContent className="pt-6">
          <div className="flex items-center gap-2 mb-4">
            <Filter className="h-5 w-5 text-[var(--foreground-muted)]" />
            <h3 className="text-base font-semibold text-[var(--foreground)]">
              {t('admin.activities.filters.title')}
            </h3>
          </div>
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
            {/* Organization Filter */}
            <div>
              <label htmlFor="organization_filter" className="block text-sm font-medium text-[var(--foreground)] mb-2">
                {t('admin.common.organization')}
              </label>
              <select
                id="organization_filter"
                value={localFilters.organization_id || ''}
                onChange={(e) => handleFilterChange('organization_id', e.target.value)}
                className="block w-full px-3 py-2.5 bg-[var(--input)] border border-[var(--input-border)] rounded-lg text-[var(--foreground)] text-sm focus:outline-none focus:ring-2 focus:ring-[var(--ring)] focus:border-transparent transition-all"
              >
                <option value="">{t('admin.activities.filters.organization_all')}</option>
                {organizations.map(org => (
                  <option key={org.id} value={org.id.toString()}>
                    {org.name}
                  </option>
                ))}
              </select>
            </div>

            {/* Action Type Filter */}
            <div>
              <label htmlFor="action_filter" className="block text-sm font-medium text-[var(--foreground)] mb-2">
                {t('admin.activities.filters.action_label')}
              </label>
              <select
                id="action_filter"
                value={localFilters.action || ''}
                onChange={(e) => handleFilterChange('action', e.target.value)}
                className="block w-full px-3 py-2.5 bg-[var(--input)] border border-[var(--input-border)] rounded-lg text-[var(--foreground)] text-sm focus:outline-none focus:ring-2 focus:ring-[var(--ring)] focus:border-transparent transition-all"
              >
                <option value="">{t('admin.activities.filters.action_all')}</option>
                {action_types.map(action => (
                  <option key={action} value={action}>
                    {formatActionName(action)}
                  </option>
                ))}
              </select>
            </div>

            {/* Date Range Filters */}
            <div>
              <label htmlFor="start_date" className="block text-sm font-medium text-[var(--foreground)] mb-2">
                {t('admin.activities.filters.start_date_label')}
              </label>
              <input
                type="date"
                id="start_date"
                value={localFilters.start_date || ''}
                onChange={(e) => handleFilterChange('start_date', e.target.value)}
                className="block w-full px-3 py-2.5 bg-[var(--input)] border border-[var(--input-border)] rounded-lg text-[var(--foreground)] text-sm focus:outline-none focus:ring-2 focus:ring-[var(--ring)] focus:border-transparent transition-all [color-scheme:dark]"
              />
            </div>

            <div>
              <label htmlFor="end_date" className="block text-sm font-medium text-[var(--foreground)] mb-2">
                {t('admin.activities.filters.end_date_label')}
              </label>
              <input
                type="date"
                id="end_date"
                value={localFilters.end_date || ''}
                onChange={(e) => handleFilterChange('end_date', e.target.value)}
                className="block w-full px-3 py-2.5 bg-[var(--input)] border border-[var(--input-border)] rounded-lg text-[var(--foreground)] text-sm focus:outline-none focus:ring-2 focus:ring-[var(--ring)] focus:border-transparent transition-all [color-scheme:dark]"
              />
            </div>
          </div>

          {/* Filter Actions */}
          <div className="mt-4 flex gap-3">
            <Button onClick={applyFilters}>
              {t('admin.common.apply_filters')}
            </Button>
            <Button variant="secondary" onClick={clearFilters}>
              {t('admin.common.clear_all')}
            </Button>
          </div>
        </CardContent>
      </Card>

      {/* Activities Table */}
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>{t('admin.activities.table.timestamp')}</TableHead>
            <TableHead>{t('admin.activities.table.admin')}</TableHead>
            <TableHead>{t('admin.common.organization')}</TableHead>
            <TableHead>{t('admin.activities.table.action')}</TableHead>
            <TableHead>{t('admin.activities.table.details')}</TableHead>
            <TableHead>{t('admin.activities.table.ip_address')}</TableHead>
            <TableHead sticky>{t('admin.common.actions')}</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {activities.length === 0 ? (
            <TableRow>
              <TableCell colSpan={7} className="text-center py-12">
                <span className="text-[var(--foreground-muted)]">
                  {t('admin.activities.empty')}
                </span>
              </TableCell>
            </TableRow>
          ) : (
            activities.map((activity) => (
              <TableRow key={activity.id} className="hover:bg-[var(--card-hover)]">
                <TableCell>
                  {formatDate(activity.created_at)}
                </TableCell>
                <TableCell variant="primary">
                  <div className="font-medium text-[var(--foreground)]">
                    {activity.account ? (activity.account.full_name || activity.account.name) : t('admin.activities.unknown_admin')}
                  </div>
                  <div className="text-xs text-[var(--foreground-muted)]">
                    {activity.account ? activity.account.email : t('admin.common.na')}
                  </div>
                </TableCell>
                <TableCell>
                  {activity.organization ? (
                    <Link
                      href={`/admin/organizations/${activity.organization.id}/edit`}
                      className="text-[var(--accent)] hover:text-[var(--accent-hover)] font-medium transition-colors"
                    >
                      {activity.organization.name}
                    </Link>
                  ) : (
                    <span className="text-[var(--foreground-subtle)]">{t('admin.common.na')}</span>
                  )}
                </TableCell>
                <TableCell>
                  <Badge variant={getActionBadgeVariant(activity.action)}>
                    {formatActionName(activity.action)}
                  </Badge>
                </TableCell>
                <TableCell className="max-w-xs">
                  {activity.details && Object.keys(activity.details).length > 0 ? (
                    <div>
                      <button
                        onClick={() => toggleDetails(activity.id)}
                        className="inline-flex items-center gap-1.5 text-[var(--accent)] hover:text-[var(--accent-hover)] font-medium text-xs transition-colors"
                      >
                        {expandedDetails.has(activity.id) ? (
                          <>
                            <EyeOff className="h-3.5 w-3.5" />
                            {t('admin.activities.hide_details')}
                          </>
                        ) : (
                          <>
                            <Eye className="h-3.5 w-3.5" />
                            {t('admin.activities.show_details')}
                          </>
                        )}
                      </button>
                      {expandedDetails.has(activity.id) && (
                        <pre className="mt-2 text-xs bg-[var(--secondary)] p-3 rounded-lg border border-[var(--border)] overflow-x-auto text-[var(--foreground-muted)] font-mono max-w-md whitespace-pre-wrap">
                          {JSON.stringify(activity.details, null, 2)}
                        </pre>
                      )}
                    </div>
                  ) : (
                    <span className="text-[var(--foreground-subtle)] text-xs">{t('admin.activities.no_details')}</span>
                  )}
                </TableCell>
                <TableCell>
                  <span className="font-mono text-xs">
                    {activity.ip_address || <span className="text-[var(--foreground-subtle)]">{t('admin.common.na')}</span>}
                  </span>
                </TableCell>
                <TableCell sticky className="text-right">
                  <Link
                    href={`/admin/activities/${activity.id}`}
                    className="text-[var(--accent)] hover:text-[var(--accent-hover)] font-medium transition-colors"
                  >
                    {t('admin.common.view')}
                  </Link>
                </TableCell>
              </TableRow>
            ))
          )}
        </TableBody>
      </Table>

      {/* Pagination */}
      {pagination.total_pages > 1 && (
        <div className="mt-6 flex items-center justify-between px-2">
          {/* Mobile pagination */}
          <div className="flex flex-1 justify-between sm:hidden">
            <Button
              variant="secondary"
              size="sm"
              onClick={() => goToPage(pagination.page - 1)}
              disabled={pagination.page === 1}
            >
              {t('admin.common.previous')}
            </Button>
            <Button
              variant="secondary"
              size="sm"
              onClick={() => goToPage(pagination.page + 1)}
              disabled={pagination.page === pagination.total_pages}
            >
              {t('admin.common.next')}
            </Button>
          </div>

          {/* Desktop pagination */}
          <div className="hidden sm:flex sm:flex-1 sm:items-center sm:justify-between">
            <div>
              <p className="text-sm text-[var(--foreground-muted)]">
                {t('admin.activities.pagination.showing', {
                  start: (pagination.page - 1) * pagination.per_page + 1,
                  end: Math.min(pagination.page * pagination.per_page, pagination.total),
                  total: pagination.total
                })}
              </p>
            </div>
            <div>
              <nav className="inline-flex items-center gap-1" aria-label="Pagination">
                <button
                  onClick={() => goToPage(pagination.page - 1)}
                  disabled={pagination.page === 1}
                  className="inline-flex items-center justify-center h-9 w-9 rounded-lg border border-[var(--border)] bg-transparent text-[var(--foreground-muted)] hover:bg-[var(--card-hover)] hover:text-[var(--foreground)] transition-colors disabled:opacity-50 disabled:cursor-not-allowed disabled:hover:bg-transparent"
                  aria-label={t('admin.common.previous')}
                >
                  <ChevronLeft className="h-4 w-4" />
                </button>
                {[...Array(pagination.total_pages)].map((_, idx) => {
                  const pageNum = idx + 1
                  // WHY: Show first, last, current, and adjacent pages only
                  const showPage =
                    pageNum === 1 ||
                    pageNum === pagination.total_pages ||
                    Math.abs(pageNum - pagination.page) <= 1

                  if (!showPage && (pageNum === 2 || pageNum === pagination.total_pages - 1)) {
                    return (
                      <span key={pageNum} className="px-2 text-[var(--foreground-subtle)]">
                        ...
                      </span>
                    )
                  }

                  if (!showPage) return null

                  return (
                    <button
                      key={pageNum}
                      onClick={() => goToPage(pageNum)}
                      className={`inline-flex items-center justify-center h-9 min-w-[36px] px-3 rounded-lg text-sm font-medium transition-colors ${
                        pageNum === pagination.page
                          ? 'bg-[var(--primary)] text-[var(--primary-foreground)]'
                          : 'border border-[var(--border)] bg-transparent text-[var(--foreground-muted)] hover:bg-[var(--card-hover)] hover:text-[var(--foreground)]'
                      }`}
                    >
                      {pageNum}
                    </button>
                  )
                })}
                <button
                  onClick={() => goToPage(pagination.page + 1)}
                  disabled={pagination.page === pagination.total_pages}
                  className="inline-flex items-center justify-center h-9 w-9 rounded-lg border border-[var(--border)] bg-transparent text-[var(--foreground-muted)] hover:bg-[var(--card-hover)] hover:text-[var(--foreground)] transition-colors disabled:opacity-50 disabled:cursor-not-allowed disabled:hover:bg-transparent"
                  aria-label={t('admin.common.next')}
                >
                  <ChevronRight className="h-4 w-4" />
                </button>
              </nav>
            </div>
          </div>
        </div>
      )}
    </AuthenticatedLayout>
  )
}
