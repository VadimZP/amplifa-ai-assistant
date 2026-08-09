import { Link, router } from '@inertiajs/react'
import { useState } from 'react'
import OrganizationTabLayout from '../../../../components/Admin/OrganizationTabLayout'
import { t } from '../../../../lib/i18n'
import { Card, CardContent, CardHeader, CardTitle } from '../../../../components/ui/Card'
import { Button } from '../../../../components/ui/Button'
import { Badge, BadgeProps } from '../../../../components/ui/Badge'
import { Input } from '../../../../components/ui/Input'
import { Pencil, User, Mail, Shield, Activity, Calendar, Clock, KeyRound, type LucideIcon } from 'lucide-react'

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
  updated_at: string
  last_login_at?: string
  organization_id: number | null
}

interface AdminOrgUsersShowProps {
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
  organization: Organization
  password_errors?: {
    new_password?: string[]
    new_password_confirmation?: string[]
  }
  flash?: {
    notice?: string
    alert?: string
  }
}

export default function Show({ auth, account: user, organization, password_errors, flash }: AdminOrgUsersShowProps) {
  const currentAccount = auth.account
  const [newPassword, setNewPassword] = useState('')
  const [newPasswordConfirmation, setNewPasswordConfirmation] = useState('')
  const [isSendingResetEmail, setIsSendingResetEmail] = useState(false)
  const [isSettingPassword, setIsSettingPassword] = useState(false)

  const formatDate = (dateString: string) => {
    return new Date(dateString).toLocaleDateString('en-US', {
      year: 'numeric',
      month: 'long',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit'
    })
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
      case 'closed': return 'error'
      default: return 'default'
    }
  }

  const DetailItem = ({ icon: Icon, label, value, badge }: { icon: LucideIcon, label: string, value?: string, badge?: React.ReactNode }) => (
    <div className="flex items-start gap-3 p-4 rounded-lg bg-[var(--card-hover)]/50 border border-[var(--border)]/50">
      <div className="p-2 rounded-md bg-[var(--card)] border border-[var(--border)] text-[var(--foreground-muted)]">
        <Icon className="h-4 w-4" />
      </div>
      <div className="flex-1">
        <dt className="text-sm font-medium text-[var(--foreground-muted)] mb-1">{label}</dt>
        <dd className="text-sm text-[var(--foreground)] font-medium">
          {badge ? badge : value || <span className="text-[var(--foreground-subtle)]">—</span>}
        </dd>
      </div>
    </div>
  )

  const handleSendResetEmail = () => {
    if (isSendingResetEmail) return

    setIsSendingResetEmail(true)
    router.post(
      `/admin/organizations/${organization.id}/users/${user.id}/send_reset_password_email`,
      {},
      {
        preserveScroll: true,
        onFinish: () => setIsSendingResetEmail(false)
      }
    )
  }

  const handleSetPassword = (e: React.FormEvent) => {
    e.preventDefault()
    if (isSettingPassword) return

    setIsSettingPassword(true)
    router.post(
      `/admin/organizations/${organization.id}/users/${user.id}/set_password`,
      {
        password: {
          new_password: newPassword,
          new_password_confirmation: newPasswordConfirmation
        }
      },
      {
        preserveScroll: true,
        onSuccess: () => {
          setNewPassword('')
          setNewPasswordConfirmation('')
        },
        onFinish: () => setIsSettingPassword(false)
      }
    )
  }

  return (
    <OrganizationTabLayout
      organization={organization}
      currentTab="users"
      account={currentAccount}
      flash={flash}
      headerActions={
        <Link href={`/admin/organizations/${organization.id}/users/${user.id}/edit`}>
          <Button variant="secondary" icon={<Pencil className="h-4 w-4" />}>
            {t('admin.common.edit')}
          </Button>
        </Link>
      }
    >
      <div className="max-w-4xl mx-auto">
        <Card className="mb-6">
          <CardHeader>
            <div className="flex items-center gap-4">
              <div className="h-16 w-16 rounded-full bg-[var(--accent)]/10 flex items-center justify-center text-[var(--accent)] text-2xl font-bold border border-[var(--accent)]/20">
                {user.first_name?.[0]}{user.last_name?.[0]}
              </div>
              <div>
                <CardTitle className="text-xl">{user.full_name}</CardTitle>
                <div className="text-sm text-[var(--foreground-muted)] mt-1">{user.email}</div>
              </div>
            </div>
          </CardHeader>
          <CardContent>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <DetailItem 
                icon={User} 
                label={t('admin.common.name')} 
                value={user.full_name} 
              />
              <DetailItem 
                icon={Mail} 
                label={t('admin.common.email')} 
                value={user.email} 
              />
              <DetailItem 
                icon={Shield} 
                label={t('admin.common.role')} 
                badge={
                  <Badge variant={getRoleBadgeVariant(user.role)}>
                    {t(`admin.users.roles.${user.role}`)}
                  </Badge>
                }
              />
              <DetailItem 
                icon={Activity} 
                label={t('admin.common.status')} 
                badge={
                  <Badge variant={getStatusBadgeVariant(user.status)}>
                    {t(`admin.users.statuses.${user.status}`)}
                  </Badge>
                }
              />
              <DetailItem 
                icon={Calendar} 
                label={t('admin.common.created')} 
                value={formatDate(user.created_at)} 
              />
              <DetailItem 
                icon={Clock} 
                label={t('admin.users.show.last_login')} 
                value={user.last_login_at ? formatDate(user.last_login_at) : undefined} 
              />
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="text-xl flex items-center gap-2">
              <KeyRound className="h-5 w-5" />
              {t('admin.users.password.title')}
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="space-y-6">
              <div className="flex items-start justify-between gap-4 p-4 rounded-lg bg-[var(--card-hover)]/50 border border-[var(--border)]/50">
                <div>
                  <h3 className="text-sm font-medium text-[var(--foreground)]">{t('admin.users.password.send_email_title')}</h3>
                  <p className="text-sm text-[var(--foreground-muted)] mt-1">{t('admin.users.password.send_email_description')}</p>
                </div>
                <Button
                  variant="secondary"
                  loading={isSendingResetEmail}
                  onClick={handleSendResetEmail}
                  icon={<Mail className="h-4 w-4" />}
                >
                  {t('admin.users.password.send_email_button')}
                </Button>
              </div>

              <form onSubmit={handleSetPassword} className="space-y-4 p-4 rounded-lg bg-[var(--card-hover)]/50 border border-[var(--border)]/50">
                <div>
                  <h3 className="text-sm font-medium text-[var(--foreground)]">{t('admin.users.password.set_direct_title')}</h3>
                  <p className="text-sm text-[var(--foreground-muted)] mt-1">{t('admin.users.password.set_direct_description')}</p>
                </div>

                <Input
                  type="password"
                  label={t('admin.users.password.new_password_label')}
                  value={newPassword}
                  onChange={e => setNewPassword(e.target.value)}
                  error={password_errors?.new_password}
                  autoComplete="new-password"
                  required
                />

                <Input
                  type="password"
                  label={t('admin.users.password.new_password_confirmation_label')}
                  value={newPasswordConfirmation}
                  onChange={e => setNewPasswordConfirmation(e.target.value)}
                  error={password_errors?.new_password_confirmation}
                  autoComplete="new-password"
                  required
                />

                <div className="flex justify-end">
                  <Button type="submit" loading={isSettingPassword} icon={<KeyRound className="h-4 w-4" />}>
                    {t('admin.users.password.set_direct_button')}
                  </Button>
                </div>
              </form>
            </div>
          </CardContent>
        </Card>
      </div>
    </OrganizationTabLayout>
  )
}
