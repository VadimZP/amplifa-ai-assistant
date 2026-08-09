import { Link } from '@inertiajs/react'
import AuthenticatedLayout from '../../layouts/AuthenticatedLayout'
import { t } from '../../lib/i18n'
import { Building2, Users, Activity } from 'lucide-react'

interface AdminDashboardProps {
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
  stats: {
    organizations_count: number
    accounts_count: number
    admin_activities_count: number
  }
  flash?: {
    notice?: string
    alert?: string
  }
}

export default function Dashboard({ auth, stats, flash }: AdminDashboardProps) {
  const account = auth.account

  const statCards = [
    {
      label: t('admin.dashboard.stats.organizations', { defaultValue: 'Organizations' }),
      value: stats.organizations_count,
      icon: Building2,
      href: '/admin/organizations'
    },
    {
      label: t('admin.dashboard.stats.accounts', { defaultValue: 'Accounts' }),
      value: stats.accounts_count,
      icon: Users,
      href: '/admin/users'
    },
    {
      label: t('admin.dashboard.stats.activities', { defaultValue: 'Activities' }),
      value: stats.admin_activities_count,
      icon: Activity,
      href: '/admin/activities'
    }
  ]

  return (
    <AuthenticatedLayout
      title={t('admin.dashboard.title', { defaultValue: 'Dashboard' })}
      account={account}
      flash={flash}
    >
      <div className="mx-auto max-w-5xl">
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
          {statCards.map((stat) => {
            const Icon = stat.icon
            return (
              <Link
                key={stat.label}
                href={stat.href}
                className="block rounded-lg border border-[var(--border)] bg-[var(--card)] p-5 transition-colors hover:border-[var(--border-hover)]"
              >
                <div className="mb-3 flex items-center gap-2">
                  <Icon className="size-4 text-[var(--foreground-muted)]" />
                  <span className="text-sm text-[var(--foreground-muted)]">{stat.label}</span>
                </div>
                <p className="text-3xl font-semibold text-[var(--foreground)]">
                  {stat.value.toLocaleString()}
                </p>
              </Link>
            )
          })}
        </div>
      </div>
    </AuthenticatedLayout>
  )
}
