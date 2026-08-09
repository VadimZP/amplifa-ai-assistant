/**
 * Admin Users Index Page
 * Lists all user accounts with role and status badges
 *
 * Design: Dark theme with Table component, Badge for roles/statuses
 * Migration: Task 5.3.3 (Phase 5)
 */
import { Link, router } from '@inertiajs/react'
import { useEffect, useRef, useState } from 'react'
import AuthenticatedLayout from '../../../layouts/AuthenticatedLayout'
import { t } from '../../../lib/i18n'
import { Table, TableHeader, TableBody, TableRow, TableHead, TableCell } from '../../../components/ui/Table'
import { Badge, BadgeProps } from '../../../components/ui/Badge'
import SearchInput from '../../../components/ui/SearchInput'
import { toast } from '../../../components/ui/Toaster'
import { ArrowDown, ArrowUp, ArrowUpDown, Filter, Plus, X } from 'lucide-react'

interface Organization {
  id: number
  name: string
}

interface Account {
  id: number
  email: string
  first_name: string
  last_name: string
  full_name: string
  role: string
  status: string
  created_at: string
  active?: boolean
  deactivated_at: string | null
  organization: Organization | null
  organization_memberships: OrganizationMembership[]
}

interface OrganizationMembership {
  id: number
  role: string
  status: string
  organization_id: number
  organization: Organization | null
}

interface Filters {
  search: string
  role: string
  status: string
  organization_id: string
}

interface AdminUsersIndexProps {
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
  accounts: Account[]
  organizations: Organization[]
  roles: string[]
  filters: Filters
  sort: SortKey
  direction: SortDirection
  flash?: {
    notice?: string
    alert?: string
  }
}

type SortKey = 'name' | 'email' | 'organization' | 'role'
type SortDirection = 'asc' | 'desc'

export default function Index({ auth, accounts, organizations, roles, filters, sort, direction, flash }: AdminUsersIndexProps) {
  const account = auth.account
  const [searchInput, setSearchInput] = useState(filters.search || '')
  const searchTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null)

  useEffect(() => {
    setSearchInput(filters.search || '')
  }, [filters.search])

  useEffect(() => {
    const platformAccessNotices = [
      t('admin.users.platform_access.amplifa_admin_enabled'),
      t('admin.users.platform_access.amplifa_admin_disabled'),
      t('admin.users.platform_access.two_factor_enabled'),
      t('admin.users.platform_access.two_factor_disabled')
    ]

    if (flash?.notice && platformAccessNotices.includes(flash.notice)) {
      toast.success(flash.notice)
    }
  }, [flash?.notice])

  useEffect(() => {
    return () => {
      if (searchTimeoutRef.current) clearTimeout(searchTimeoutRef.current)
    }
  }, [])

  const requestUsers = (overrides: Partial<Filters> = {}, nextSort = sort, nextDirection = direction) => {
    const nextFilters = { ...filters, ...overrides }
    const params: Record<string, string> = {
      sort: nextSort,
      direction: nextDirection
    }

    if (nextFilters.search.trim()) params.search = nextFilters.search.trim()
    if (nextFilters.role !== 'all') params.role = nextFilters.role
    if (nextFilters.status !== 'all') params.status_filter = nextFilters.status
    if (nextFilters.organization_id !== 'all') params.organization_id = nextFilters.organization_id

    router.get('/admin/users', params, {
      preserveState: true,
      preserveScroll: true,
      replace: true
    })
  }

  const updateSearch = (value: string) => {
    setSearchInput(value)
    if (searchTimeoutRef.current) clearTimeout(searchTimeoutRef.current)

    searchTimeoutRef.current = setTimeout(() => {
      requestUsers({ search: value })
    }, 300)
  }

  const clearFilters = () => {
    setSearchInput('')
    requestUsers({ search: '', role: 'all', status: 'all', organization_id: 'all' })
  }

  const hasActiveFilters = Boolean(filters.search.trim()) || filters.role !== 'all' || filters.status !== 'all' || filters.organization_id !== 'all'

  const nextDirectionFor = (column: SortKey): SortDirection => {
    if (sort !== column) {
      return 'asc'
    }

    return direction === 'asc' ? 'desc' : 'asc'
  }

  const applySort = (column: SortKey) => {
    requestUsers({}, column, nextDirectionFor(column))
  }

  const SortIndicator = ({ column }: { column: SortKey }) => {
    if (sort !== column) {
      return <ArrowUpDown className="h-3.5 w-3.5 text-[var(--foreground-subtle)]" />
    }

    return direction === 'asc'
      ? <ArrowUp className="h-3.5 w-3.5 text-[var(--accent)]" />
      : <ArrowDown className="h-3.5 w-3.5 text-[var(--accent)]" />
  }

  const SortableHeader = ({ column, label }: { column: SortKey; label: string }) => (
    <button
      type="button"
      onClick={() => applySort(column)}
      className="inline-flex items-center gap-1.5 hover:text-[var(--accent)] transition-colors"
    >
      <span>{label}</span>
      <SortIndicator column={column} />
    </button>
  )

  const formatDate = (dateString: string) => {
    return new Date(dateString).toLocaleDateString('en-US', {
      year: 'numeric',
      month: 'short',
      day: 'numeric'
    })
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
    switch (role) {
      case 'amplifa_admin':
        return t('admin.roles.amplifa_admin')
      case 'customer_admin':
        return t('admin.roles.customer_admin')
      case 'customer_user':
        return t('admin.roles.customer_user')
      default:
        return role
    }
  }

  const selectClasses = 'h-10 rounded-xl border border-[var(--input-border)] bg-[var(--input)] px-3 text-sm text-[var(--foreground)] focus:border-[var(--ring)] focus:outline-none focus:ring-4 focus:ring-[rgba(53,202,222,0.12)]'

  const activeMembershipsFor = (user: Account) => {
    if (user.organization_memberships.length > 0) return user.organization_memberships

    return user.organization
      ? [{ id: user.organization.id, role: user.role, status: 'active', organization_id: user.organization.id, organization: user.organization }]
      : []
  }

  const stickyNavigation = (
    <div className="flex flex-col gap-3 px-6 py-3 lg:px-8">
      <div className="flex flex-col gap-3 lg:flex-row lg:items-center lg:justify-between">
        <div className="flex min-w-0 flex-1 items-center gap-3">
          <SearchInput
            value={searchInput}
            onChange={event => updateSearch(event.target.value)}
            placeholder={t('admin.users.filters.search_placeholder')}
            aria-label={t('admin.users.filters.search_label')}
            className="w-full lg:w-[360px]"
          />
          <div className="hidden items-center gap-1.5 text-xs text-[var(--foreground-muted)] lg:flex" aria-live="polite">
            <Filter className="h-3.5 w-3.5" />
            {t('admin.users.filters.result_count', { count: accounts.length })}
          </div>
        </div>

        <div className="flex flex-wrap items-center gap-2">
          <select
            value={filters.organization_id}
            onChange={event => requestUsers({ organization_id: event.target.value })}
            className={selectClasses}
            aria-label={t('admin.users.filters.organization_label')}
          >
            <option value="all">{t('admin.users.filters.organization_all')}</option>
            {organizations.map(organization => (
              <option key={organization.id} value={organization.id}>{organization.name}</option>
            ))}
          </select>

          <select
            value={filters.role}
            onChange={event => requestUsers({ role: event.target.value })}
            className={selectClasses}
            aria-label={t('admin.users.filters.role_label')}
          >
            <option value="all">{t('admin.users.filters.role_all')}</option>
            {roles.map(role => (
              <option key={role} value={role}>{formatRoleName(role)}</option>
            ))}
          </select>

          <select
            value={filters.status}
            onChange={event => requestUsers({ status: event.target.value })}
            className={selectClasses}
            aria-label={t('admin.users.filters.status_label')}
          >
            <option value="all">{t('admin.users.filters.status_all')}</option>
            <option value="active">{t('admin.statuses.active')}</option>
            <option value="deactivated">{t('admin.statuses.deactivated')}</option>
          </select>

          {hasActiveFilters && (
            <button
              type="button"
              onClick={clearFilters}
              className="inline-flex h-10 items-center gap-2 rounded-xl border border-[var(--border)] px-3 text-sm text-[var(--foreground-muted)] transition-colors hover:border-[var(--accent)] hover:text-[var(--foreground)]"
            >
              <X className="h-4 w-4" />
              {t('admin.users.filters.clear')}
            </button>
          )}
        </div>
      </div>
    </div>
  )

  return (
    <AuthenticatedLayout
      title={t('admin.users.title')}
      subtitle={t('admin.users.subtitle')}
      account={account}
      flash={flash}
      stickyNavigation={stickyNavigation}
      headerActions={
        <Link
          href="/admin/users/new"
          className="inline-flex items-center justify-center h-9 px-4 gap-2 text-sm font-medium rounded-lg bg-[var(--primary)] text-[var(--primary-foreground)] hover:bg-[var(--primary-hover)] transition-colors"
        >
          <Plus className="h-4 w-4" />
          {t('admin.users.create_button')}
        </Link>
      }
    >
      {/* Users Table */}
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead><SortableHeader column="name" label={t('admin.common.name')} /></TableHead>
            <TableHead><SortableHeader column="email" label={t('admin.common.email')} /></TableHead>
            <TableHead><SortableHeader column="organization" label={t('admin.common.organization')} /></TableHead>
            <TableHead><SortableHeader column="role" label={t('admin.common.role')} /></TableHead>
            <TableHead>{t('admin.common.status')}</TableHead>
            <TableHead>{t('admin.common.created')}</TableHead>
            <TableHead sticky>{t('admin.common.actions')}</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {accounts.length === 0 ? (
            <TableRow>
              <TableCell colSpan={7} className="text-center py-12">
                <span className="text-[var(--foreground-muted)]">
                  {t('admin.users.empty')}
                </span>
              </TableCell>
            </TableRow>
          ) : (
            accounts.map((user) => (
              <TableRow key={user.id} className="hover:bg-[var(--card-hover)]">
                <TableCell variant="primary">
                  <Link
                    href={`/admin/users/${user.id}`}
                    className="text-[var(--foreground)] hover:text-[var(--accent)] transition-colors"
                  >
                    {user.full_name}
                  </Link>
                </TableCell>
                <TableCell>
                  {user.email}
                </TableCell>
                <TableCell>
                  {activeMembershipsFor(user).length > 0 ? (
                    <div className="flex max-w-[260px] flex-wrap gap-1.5">
                      {activeMembershipsFor(user).map(membership => (
                        membership.organization ? (
                          <Link
                            key={`${user.id}-${membership.organization_id}`}
                            href={`/admin/organizations/${membership.organization.id}/edit`}
                            className="inline-flex max-w-full items-center rounded-full border border-[var(--accent)]/25 bg-[var(--accent)]/10 px-2.5 py-1 text-xs font-medium text-[var(--accent)] transition-colors hover:border-[var(--accent)]/50 hover:bg-[var(--accent)]/15"
                          >
                            <span className="truncate">{membership.organization.name}</span>
                          </Link>
                        ) : null
                      ))}
                    </div>
                  ) : (
                    <span className="text-[var(--foreground-subtle)]">{t('admin.common.na')}</span>
                  )}
                </TableCell>
                <TableCell>
                  <Badge variant={getRoleBadgeVariant(user.role)}>
                    {formatRoleName(user.role)}
                  </Badge>
                </TableCell>
                <TableCell>
                  {user.deactivated_at ? (
                    <Badge variant="error">
                      {t('admin.statuses.deactivated')}
                    </Badge>
                  ) : (
                    <Badge variant="success">
                      {t('admin.statuses.active')}
                    </Badge>
                  )}
                </TableCell>
                <TableCell>
                  {formatDate(user.created_at)}
                </TableCell>
                <TableCell sticky className="text-right space-x-3">
                  <Link
                    href={`/admin/users/${user.id}/edit`}
                    className="text-[var(--accent)] hover:text-[var(--accent-hover)] font-medium transition-colors"
                  >
                    {t('admin.common.edit')}
                  </Link>
                  {(user.role === 'customer_admin' || user.role === 'customer_user') && !user.deactivated_at && (
                    <Link
                      href={`/admin/users/${user.id}/impersonate`}
                      method="post"
                      as="button"
                      className="text-[var(--success)] hover:text-green-300 font-medium transition-colors"
                    >
                      {t('admin.users.table.login_as')}
                    </Link>
                  )}
                </TableCell>
              </TableRow>
            ))
          )}
        </TableBody>
      </Table>
    </AuthenticatedLayout>
  )
}
