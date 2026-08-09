import { Link } from '@inertiajs/react'
import OrganizationTabLayout from '../../../../components/Admin/OrganizationTabLayout'
import { Table, TableHeader, TableBody, TableRow, TableHead, TableCell } from '../../../../components/ui/Table'
import { Badge, BadgeProps } from '../../../../components/ui/Badge'
import { Button } from '../../../../components/ui/Button'
import { t } from '../../../../lib/i18n'
import { Plus, Users } from 'lucide-react'

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
}

interface User {
  id: number
  email: string
  first_name: string | null
  last_name: string | null
  role: string
  status: string
  created_at: string
  deactivated_at?: string | null
}

interface Props {
  auth: { account: Account }
  organization: Organization
  users: User[]
  current_tab: string
  flash?: { notice?: string; alert?: string }
}

const getRoleBadgeVariant = (role: string): BadgeProps['variant'] => {
  switch (role) {
    case 'customer_admin': return 'approved'
    case 'customer_user': return 'info'
    default: return 'default'
  }
}

const getStatusBadgeVariant = (status: string): BadgeProps['variant'] => {
  switch (status) {
    case 'verified': return 'success'
    case 'unverified': return 'warning'
    default: return 'default'
  }
}

export default function Index({ auth, organization, users, current_tab, flash }: Props) {
  const formatDate = (dateString: string) => {
    return new Date(dateString).toLocaleDateString('en-US', {
      year: 'numeric',
      month: 'short',
      day: 'numeric'
    })
  }

  const getFullName = (user: User) => {
    const parts = [user.first_name, user.last_name].filter(Boolean)
    return parts.length > 0 ? parts.join(' ') : null
  }

  return (
    <OrganizationTabLayout
      organization={organization}
      currentTab={current_tab}
      account={auth.account}
      flash={flash}
      headerActions={
        <Link href={`/admin/users/new?organization_id=${organization.id}&return_to=/admin/organizations/${organization.id}/users`}>
          <Button icon={<Plus className="h-4 w-4" />}>
            {t('admin.users.create_button')}
          </Button>
        </Link>
      }
    >
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>{t('admin.common.name')}</TableHead>
            <TableHead>{t('admin.common.email')}</TableHead>
            <TableHead>{t('admin.common.role')}</TableHead>
            <TableHead>{t('admin.common.status')}</TableHead>
            <TableHead>{t('admin.common.created')}</TableHead>
            <TableHead sticky>{t('admin.common.actions')}</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {users.length === 0 ? (
            <TableRow>
              <TableCell colSpan={6} className="text-center py-12">
                <div className="flex flex-col items-center gap-4">
                  <Users className="h-12 w-12 text-[var(--foreground-subtle)]" />
                  <span className="text-[var(--foreground-muted)]">
                    {t('admin.users.empty')}
                  </span>
                  <Link href={`/admin/users/new?organization_id=${organization.id}&return_to=/admin/organizations/${organization.id}/users`}>
                    <Button icon={<Plus className="h-4 w-4" />}>
                      {t('admin.users.create_button')}
                    </Button>
                  </Link>
                </div>
              </TableCell>
            </TableRow>
          ) : (
            users.map((user) => (
              <TableRow key={user.id} className="hover:bg-[var(--card-hover)]">
                <TableCell variant="primary">
                  <Link
                    href={`/admin/organizations/${organization.id}/users/${user.id}`}
                    className="text-[var(--accent)] hover:text-[var(--accent-hover)] font-medium transition-colors"
                  >
                    {getFullName(user) || (
                      <span className="text-[var(--foreground-subtle)]">—</span>
                    )}
                  </Link>
                </TableCell>
                <TableCell>{user.email}</TableCell>
                <TableCell>
                  <Badge variant={getRoleBadgeVariant(user.role)}>
                    {t(`admin.users.roles.${user.role}`)}
                  </Badge>
                </TableCell>
                <TableCell>
                  <Badge variant={getStatusBadgeVariant(user.status)}>
                    {t(`admin.users.statuses.${user.status}`)}
                  </Badge>
                </TableCell>
                <TableCell>{formatDate(user.created_at)}</TableCell>
                <TableCell sticky className="text-right space-x-3">
                  <Link
                    href={`/admin/organizations/${organization.id}/users/${user.id}/edit`}
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
    </OrganizationTabLayout>
  )
}
