/**
 * Admin Invitations Index Page
 * Invitations table with filters and pagination
 *
 * Design: Dark theme with Table component, Badge for status
 * Migration: Task 5.3.7 (Phase 5)
 */
import { Link, router } from '@inertiajs/react'
import { useState } from 'react'
import AuthenticatedLayout from '../../../layouts/AuthenticatedLayout'
import { t } from '../../../lib/i18n'
import { Table, TableHeader, TableBody, TableRow, TableHead, TableCell } from '../../../components/ui/Table'
import { Badge, BadgeProps } from '../../../components/ui/Badge'
import { Card, CardContent } from '../../../components/ui/Card'
import { Button } from '../../../components/ui/Button'
import { ChevronLeft, ChevronRight, Filter, Plus, RefreshCw, XCircle, Trash2 } from 'lucide-react'

// WHY: Define TypeScript interfaces for type safety and IDE autocomplete
interface Organization {
  id: number
  name: string
}

interface InvitedBy {
  id: number
  first_name: string
  last_name: string
  email: string
  full_name: string
}

interface Invitation {
  id: number
  email: string
  first_name: string
  last_name: string
  role: string
  status: string
  sent_at: string | null
  accepted_at: string | null
  expires_at: string
  created_at: string
  organization: Organization
  invited_by: InvitedBy
}

interface AdminInvitationsIndexProps {
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
  invitations: Invitation[]
  organizations: [number, string][]
  filters: {
    status?: string
    organization_id?: string
  }
  pagination: {
    current_page: number
    total_pages: number
    total_count: number
  }
  flash?: {
    notice?: string
    alert?: string
  }
}

export default function Index({ auth, invitations, organizations, filters, pagination, flash }: AdminInvitationsIndexProps) {
  const account = auth.account

  // WHY: Local state for managing filter form values
  const [statusFilter, setStatusFilter] = useState(filters.status || 'all')
  const [organizationFilter, setOrganizationFilter] = useState(filters.organization_id || 'all')

  // WHY: Format dates consistently for better UX
  const formatDate = (dateString: string | null) => {
    if (!dateString) return 'N/A'
    return new Date(dateString).toLocaleDateString('en-US', {
      year: 'numeric',
      month: 'short',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit'
    })
  }

  // WHY: Format role names for display consistency
  const formatRoleName = (role: string) => {
    return t(`admin.roles.${role}`, { defaultValue: role })
  }

  /**
   * Get badge variant for status
   * - pending: warning (yellow)
   * - accepted: success (green)
   * - expired: error (red)
   * - cancelled: default (gray)
   */
  const getStatusBadgeVariant = (status: string): BadgeProps['variant'] => {
    switch (status) {
      case 'pending':
        return 'warning'
      case 'accepted':
        return 'success'
      case 'expired':
        return 'error'
      case 'cancelled':
        return 'default'
      default:
        return 'default'
    }
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
        return 'default'
      default:
        return 'default'
    }
  }

  // WHY: Format status for display
  const formatStatus = (status: string) => {
    return t(`admin.statuses.${status}`, { defaultValue: status.charAt(0).toUpperCase() + status.slice(1).replace('_', ' ') })
  }

  // WHY: Apply filters and refresh page with new query parameters
  const applyFilters = () => {
    const params = new URLSearchParams()
    if (statusFilter !== 'all') params.append('status', statusFilter)
    if (organizationFilter !== 'all') params.append('organization_id', organizationFilter)

    router.visit(`/admin/invitations?${params.toString()}`)
  }

  // WHY: Reset filters to show all invitations
  const resetFilters = () => {
    setStatusFilter('all')
    setOrganizationFilter('all')
    router.visit('/admin/invitations')
  }

  // WHY: Handle action buttons with confirmation dialogs for destructive actions
  const handleResend = (invitationId: number, email: string) => {
    if (confirm(t('admin.invitations.confirm.resend', { email }))) {
      router.post(`/admin/invitations/${invitationId}/resend`)
    }
  }

  const handleCancel = (invitationId: number, email: string) => {
    if (confirm(t('admin.invitations.confirm.cancel', { email }))) {
      router.post(`/admin/invitations/${invitationId}/cancel`)
    }
  }

  const handleDelete = (invitationId: number, email: string) => {
    if (confirm(t('admin.invitations.confirm.delete', { email }))) {
      router.delete(`/admin/invitations/${invitationId}`)
    }
  }

  // WHY: Navigate to different page while preserving filters
  const goToPage = (page: number) => {
    const params = new URLSearchParams()
    params.append('page', page.toString())
    if (filters.status) params.append('status', filters.status)
    if (filters.organization_id) params.append('organization_id', filters.organization_id)
    router.visit(`/admin/invitations?${params.toString()}`)
  }

  return (
    <AuthenticatedLayout
      title={t('admin.invitations.title')}
      subtitle={t('admin.invitations.subtitle')}
      account={account}
      flash={flash}
      headerActions={
        <Link
          href="/admin/invitations/new"
          className="inline-flex items-center gap-2 h-10 px-4 rounded-lg bg-[var(--primary)] text-[var(--primary-foreground)] font-medium text-sm hover:bg-[var(--primary-hover)] transition-colors"
        >
          <Plus className="h-4 w-4" />
          {t('admin.invitations.create_button')}
        </Link>
      }
    >
      {/* Filters Card */}
      <Card className="mb-6">
        <CardContent className="pt-6">
          <div className="flex items-center gap-2 mb-4">
            <Filter className="h-5 w-5 text-[var(--foreground-muted)]" />
            <h3 className="text-base font-semibold text-[var(--foreground)]">
              {t('admin.invitations.filters.title')}
            </h3>
          </div>
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
            {/* Status Filter */}
            <div>
              <label htmlFor="status-filter" className="block text-sm font-medium text-[var(--foreground)] mb-2">
                {t('admin.common.status')}
              </label>
              <select
                id="status-filter"
                value={statusFilter}
                onChange={e => setStatusFilter(e.target.value)}
                className="block w-full px-3 py-2.5 bg-[var(--input)] border border-[var(--input-border)] rounded-lg text-[var(--foreground)] text-sm focus:outline-none focus:ring-2 focus:ring-[var(--ring)] focus:border-transparent transition-all"
              >
                <option value="all">{t('admin.invitations.filters.status_all')}</option>
                <option value="pending">{t('admin.statuses.pending')}</option>
                <option value="accepted">{t('admin.statuses.accepted')}</option>
                <option value="expired">{t('admin.statuses.expired')}</option>
                <option value="cancelled">{t('admin.statuses.cancelled')}</option>
              </select>
            </div>

            {/* Organization Filter */}
            <div>
              <label htmlFor="organization-filter" className="block text-sm font-medium text-[var(--foreground)] mb-2">
                {t('admin.common.organization')}
              </label>
              <select
                id="organization-filter"
                value={organizationFilter}
                onChange={e => setOrganizationFilter(e.target.value)}
                className="block w-full px-3 py-2.5 bg-[var(--input)] border border-[var(--input-border)] rounded-lg text-[var(--foreground)] text-sm focus:outline-none focus:ring-2 focus:ring-[var(--ring)] focus:border-transparent transition-all"
              >
                <option value="all">{t('admin.invitations.filters.organization_all')}</option>
                {organizations.map(([id, name]) => (
                  <option key={id} value={id}>
                    {name}
                  </option>
                ))}
              </select>
            </div>

            {/* Filter Actions */}
            <div className="flex items-end gap-2">
              <Button onClick={applyFilters} className="flex-1">
                {t('admin.common.apply_filters')}
              </Button>
              <Button variant="secondary" onClick={resetFilters}>
                {t('admin.common.reset')}
              </Button>
            </div>
          </div>
        </CardContent>
      </Card>

      {/* Invitations Table */}
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>{t('admin.common.name')}</TableHead>
            <TableHead>{t('admin.common.email')}</TableHead>
            <TableHead>{t('admin.common.organization')}</TableHead>
            <TableHead>{t('admin.common.role')}</TableHead>
            <TableHead>{t('admin.common.status')}</TableHead>
            <TableHead>{t('admin.invitations.table.expires')}</TableHead>
            <TableHead>{t('admin.invitations.table.invited_by')}</TableHead>
            <TableHead sticky>{t('admin.common.actions')}</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {invitations.length === 0 ? (
            <TableRow>
              <TableCell colSpan={8} className="text-center py-12">
                <span className="text-[var(--foreground-muted)]">
                  {filters.status || filters.organization_id
                    ? t('admin.invitations.empty_with_filter')
                    : t('admin.invitations.empty')
                  }
                </span>
              </TableCell>
            </TableRow>
          ) : (
            invitations.map((invitation) => (
              <TableRow key={invitation.id} className="hover:bg-[var(--card-hover)]">
                <TableCell variant="primary">
                  {invitation.first_name} {invitation.last_name}
                </TableCell>
                <TableCell>
                  {invitation.email}
                </TableCell>
                <TableCell>
                  <Link
                    href={`/admin/organizations/${invitation.organization.id}/edit`}
                    className="text-[var(--accent)] hover:text-[var(--accent-hover)] font-medium transition-colors"
                  >
                    {invitation.organization.name}
                  </Link>
                </TableCell>
                <TableCell>
                  <Badge variant={getRoleBadgeVariant(invitation.role)}>
                    {formatRoleName(invitation.role)}
                  </Badge>
                </TableCell>
                <TableCell>
                  <Badge variant={getStatusBadgeVariant(invitation.status)}>
                    {formatStatus(invitation.status)}
                  </Badge>
                </TableCell>
                <TableCell>
                  {formatDate(invitation.expires_at)}
                </TableCell>
                <TableCell>
                  {invitation.invited_by.full_name}
                </TableCell>
                <TableCell sticky className="text-right">
                  <div className="flex items-center justify-end gap-2">
                    {/* WHY: Only show Resend for pending invitations */}
                    {invitation.status === 'pending' && (
                      <button
                        onClick={() => handleResend(invitation.id, invitation.email)}
                        className="inline-flex items-center gap-1.5 text-[var(--accent)] hover:text-[var(--accent-hover)] font-medium text-sm transition-colors"
                        title={t('admin.invitations.actions.resend')}
                      >
                        <RefreshCw className="h-4 w-4" />
                        <span className="hidden sm:inline">{t('admin.invitations.actions.resend')}</span>
                      </button>
                    )}

                    {/* WHY: Only show Cancel for pending invitations */}
                    {invitation.status === 'pending' && (
                      <button
                        onClick={() => handleCancel(invitation.id, invitation.email)}
                        className="inline-flex items-center gap-1.5 text-[var(--warning)] hover:text-amber-400 font-medium text-sm transition-colors"
                        title={t('admin.invitations.actions.cancel')}
                      >
                        <XCircle className="h-4 w-4" />
                        <span className="hidden sm:inline">{t('admin.invitations.actions.cancel')}</span>
                      </button>
                    )}

                    {/* WHY: Allow deletion of expired and cancelled invitations to clean up */}
                    {(invitation.status === 'expired' || invitation.status === 'cancelled') && (
                      <button
                        onClick={() => handleDelete(invitation.id, invitation.email)}
                        className="inline-flex items-center gap-1.5 text-[var(--error)] hover:text-red-400 font-medium text-sm transition-colors"
                        title={t('admin.common.delete')}
                      >
                        <Trash2 className="h-4 w-4" />
                        <span className="hidden sm:inline">{t('admin.common.delete')}</span>
                      </button>
                    )}
                  </div>
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
              onClick={() => goToPage(pagination.current_page - 1)}
              disabled={pagination.current_page === 1}
            >
              {t('admin.common.previous')}
            </Button>
            <Button
              variant="secondary"
              size="sm"
              onClick={() => goToPage(pagination.current_page + 1)}
              disabled={pagination.current_page === pagination.total_pages}
            >
              {t('admin.common.next')}
            </Button>
          </div>

          {/* Desktop pagination */}
          <div className="hidden sm:flex sm:flex-1 sm:items-center sm:justify-between">
            <div>
              <p className="text-sm text-[var(--foreground-muted)]">
                {t('admin.invitations.pagination.showing', {
                  current: pagination.current_page,
                  total: pagination.total_pages,
                  count: pagination.total_count
                })}
              </p>
            </div>
            <div>
              <nav className="inline-flex items-center gap-1" aria-label="Pagination">
                <button
                  onClick={() => goToPage(pagination.current_page - 1)}
                  disabled={pagination.current_page === 1}
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
                    Math.abs(pageNum - pagination.current_page) <= 1

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
                        pageNum === pagination.current_page
                          ? 'bg-[var(--primary)] text-[var(--primary-foreground)]'
                          : 'border border-[var(--border)] bg-transparent text-[var(--foreground-muted)] hover:bg-[var(--card-hover)] hover:text-[var(--foreground)]'
                      }`}
                    >
                      {pageNum}
                    </button>
                  )
                })}
                <button
                  onClick={() => goToPage(pagination.current_page + 1)}
                  disabled={pagination.current_page === pagination.total_pages}
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
