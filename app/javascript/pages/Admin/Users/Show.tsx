import { Link, router } from '@inertiajs/react'
import { useState } from 'react'
import {
  Activity,
  Building2,
  Calendar,
  Mail,
  Pencil,
  Shield,
  Trash2,
  User,
  type LucideIcon,
} from 'lucide-react'
import AuthenticatedLayout from '../../../layouts/AuthenticatedLayout'
import { Card, CardContent, CardHeader, CardTitle } from '../../../components/ui/Card'
import { Button } from '../../../components/ui/Button'
import { Badge, type BadgeProps } from '../../../components/ui/Badge'

interface Organization {
  id: number
  name: string
  website?: string | null
}

interface ActivityActor {
  id: number
  email: string
  first_name?: string
  last_name?: string
  full_name?: string
  name?: string
}

interface ActivityOrganization {
  id: number
  name: string
}

interface AdminActivity {
  id: number
  action: string
  details: Record<string, unknown> | null
  ip_address: string | null
  user_agent: string | null
  created_at: string
  organization_id: number | null
  account?: ActivityActor | null
  organization?: ActivityOrganization | null
}

interface Account {
  id: number
  email: string
  first_name: string
  last_name: string
  full_name: string
  role: string
  status: string
  deactivated_at: string | null
  created_at: string
  organization?: Organization | null
}

interface AdminUsersShowProps {
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
  account: Account
  activities_by_user: AdminActivity[]
  activities_on_user: AdminActivity[]
  can_destroy: boolean
  flash?: {
    notice?: string
    alert?: string
  }
}

function formatLabel(value: string) {
  return value
    .split('_')
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(' ')
}

function formatDate(dateString: string | null | undefined) {
  if (!dateString) return '—'

  return new Date(dateString).toLocaleDateString('en-US', {
    year: 'numeric',
    month: 'long',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  })
}

function getRoleBadgeVariant(role: string): BadgeProps['variant'] {
  switch (role) {
    case 'amplifa_admin':
      return 'approved'
    case 'customer_admin':
      return 'info'
    case 'customer_user':
      return 'default'
    default:
      return 'default'
  }
}

function getStatusBadgeVariant(status: string): BadgeProps['variant'] {
  switch (status) {
    case 'verified':
      return 'success'
    case 'unverified':
      return 'warning'
    case 'closed':
      return 'error'
    default:
      return 'default'
  }
}

function DetailItem({
  icon: Icon,
  label,
  value,
  badge,
}: {
  icon: LucideIcon
  label: string
  value?: string
  badge?: React.ReactNode
}) {
  return (
    <div className="flex items-start gap-3 rounded-lg border border-[var(--border)]/50 bg-[var(--card-hover)]/50 p-4">
      <div className="rounded-md border border-[var(--border)] bg-[var(--card)] p-2 text-[var(--foreground-muted)]">
        <Icon className="h-4 w-4" />
      </div>
      <div className="flex-1">
        <dt className="mb-1 text-sm font-medium text-[var(--foreground-muted)]">{label}</dt>
        <dd className="text-sm font-medium text-[var(--foreground)]">
          {badge || value || <span className="text-[var(--foreground-subtle)]">—</span>}
        </dd>
      </div>
    </div>
  )
}

function ActivityList({ title, description, activities }: { title: string; description: string; activities: AdminActivity[] }) {
  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2 text-xl">
          <Activity className="h-5 w-5" />
          {title}
        </CardTitle>
        <p className="text-sm text-[var(--foreground-muted)]">{description}</p>
      </CardHeader>
      <CardContent>
        {activities.length === 0 ? (
          <p className="text-sm text-[var(--foreground-muted)]">No activity found.</p>
        ) : (
          <div className="space-y-4">
            {activities.map((activity) => (
              <div
                key={activity.id}
                className="rounded-lg border border-[var(--border)]/60 bg-[var(--card-hover)]/40 p-4"
              >
                <div className="mb-3 flex flex-wrap items-center gap-2">
                  <Badge variant="outline">{formatLabel(activity.action)}</Badge>
                  <span className="text-xs text-[var(--foreground-muted)]">{formatDate(activity.created_at)}</span>
                </div>

                <div className="grid gap-3 text-sm text-[var(--foreground)] md:grid-cols-2">
                  <div>
                    <span className="text-[var(--foreground-muted)]">Admin:</span>{' '}
                    {activity.account?.name || activity.account?.full_name || activity.account?.email || 'Unknown'}
                  </div>
                  <div>
                    <span className="text-[var(--foreground-muted)]">Organization:</span>{' '}
                    {activity.organization?.name || '—'}
                  </div>
                  <div>
                    <span className="text-[var(--foreground-muted)]">IP address:</span>{' '}
                    {activity.ip_address || '—'}
                  </div>
                </div>

                {activity.details && Object.keys(activity.details).length > 0 && (
                  <div className="mt-3 rounded-md bg-[var(--card)] p-3">
                    <div className="mb-2 text-xs font-medium uppercase tracking-wide text-[var(--foreground-muted)]">
                      Details
                    </div>
                    <pre className="overflow-x-auto whitespace-pre-wrap break-words text-xs text-[var(--foreground)]">
                      {JSON.stringify(activity.details, null, 2)}
                    </pre>
                  </div>
                )}
              </div>
            ))}
          </div>
        )}
      </CardContent>
    </Card>
  )
}

export default function Show({
  auth,
  account: user,
  activities_by_user,
  activities_on_user,
  can_destroy,
  flash,
}: AdminUsersShowProps) {
  const currentAccount = auth.account
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false)
  const [isDeleting, setIsDeleting] = useState(false)

  const handleDelete = () => {
    if (isDeleting) return

    setIsDeleting(true)
    router.delete(`/admin/users/${user.id}`, {
      onFinish: () => setIsDeleting(false),
    })
  }

  return (
    <AuthenticatedLayout
      title={user.full_name}
      subtitle="User details and recent admin activity"
      account={currentAccount}
      flash={flash}
      headerActions={
        <div className="flex items-center gap-3">
          <Link href="/admin/users">
            <Button variant="secondary">Back to Users</Button>
          </Link>
          <Link href={`/admin/users/${user.id}/edit`}>
            <Button variant="secondary" icon={<Pencil className="h-4 w-4" />}>
              Edit User
            </Button>
          </Link>
          {can_destroy && (
            <Button
              variant="destructive"
              icon={<Trash2 className="h-4 w-4" />}
              onClick={() => setShowDeleteConfirm(true)}
            >
              Delete User
            </Button>
          )}
        </div>
      }
    >
      <div className="mx-auto max-w-5xl space-y-6">
        <Card>
          <CardHeader>
            <div className="flex items-center gap-4">
              <div className="flex h-16 w-16 items-center justify-center rounded-full border border-[var(--accent)]/20 bg-[var(--accent)]/10 text-2xl font-bold text-[var(--accent)]">
                {user.first_name?.[0]}
                {user.last_name?.[0]}
              </div>
              <div>
                <CardTitle className="text-xl">{user.full_name}</CardTitle>
                <div className="mt-1 text-sm text-[var(--foreground-muted)]">{user.email}</div>
              </div>
            </div>
          </CardHeader>
          <CardContent>
            <dl className="grid grid-cols-1 gap-4 md:grid-cols-2">
              <DetailItem icon={User} label="Name" value={user.full_name} />
              <DetailItem icon={Mail} label="Email" value={user.email} />
              <DetailItem
                icon={Shield}
                label="Role"
                badge={<Badge variant={getRoleBadgeVariant(user.role)}>{formatLabel(user.role)}</Badge>}
              />
              <DetailItem
                icon={Activity}
                label="Status"
                badge={<Badge variant={getStatusBadgeVariant(user.status)}>{formatLabel(user.status)}</Badge>}
              />
              <DetailItem
                icon={Building2}
                label="Organization"
                value={user.organization?.name}
              />
              <DetailItem icon={Calendar} label="Created" value={formatDate(user.created_at)} />
            </dl>

            {user.organization?.website && (
              <div className="mt-4 rounded-lg border border-[var(--border)]/50 bg-[var(--card-hover)]/40 p-4 text-sm text-[var(--foreground)]">
                <span className="font-medium text-[var(--foreground-muted)]">Website:</span>{' '}
                <a
                  href={user.organization.website}
                  target="_blank"
                  rel="noreferrer"
                  className="text-[var(--primary)] hover:underline"
                >
                  {user.organization.website}
                </a>
              </div>
            )}
          </CardContent>
        </Card>

        <div className="grid grid-cols-1 gap-6 xl:grid-cols-2">
          <ActivityList
            title="Actions by this user"
            description="Recent admin activity performed by this account."
            activities={activities_by_user}
          />
          <ActivityList
            title="Actions on this user"
            description="Recent admin activity that targeted this account."
            activities={activities_on_user}
          />
        </div>

        {showDeleteConfirm && (
          <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
            <Card className="mx-4 w-full max-w-md">
              <CardContent className="pt-6">
                <h3 className="mb-2 text-lg font-semibold text-[var(--foreground)]">Delete user?</h3>
                <p className="mb-6 text-sm text-[var(--foreground-muted)]">
                  This will deactivate {user.full_name} ({user.email}) and remove their access. Historical records will be preserved.
                </p>
                <div className="flex justify-end gap-3">
                  <Button variant="secondary" onClick={() => setShowDeleteConfirm(false)}>
                    Cancel
                  </Button>
                  <Button variant="destructive" loading={isDeleting} onClick={handleDelete}>
                    Delete user
                  </Button>
                </div>
              </CardContent>
            </Card>
          </div>
        )}
      </div>
    </AuthenticatedLayout>
  )
}
