import { Link, router, useForm } from '@inertiajs/react'
import { useState } from 'react'
import OrganizationTabLayout from '../../../../components/Admin/OrganizationTabLayout'
import { t } from '../../../../lib/i18n'
import { Card, CardContent, CardFooter, CardHeader } from '../../../../components/ui/Card'
import { Input } from '../../../../components/ui/Input'
import { Button } from '../../../../components/ui/Button'
import { AlertTriangle, Info, KeyRound, Mail } from 'lucide-react'

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
  organization_id: number | null
  status: string
  deactivated_at: string | null
}

interface AdminOrgUsersEditProps {
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
  roles: string[]
  statuses: string[]
  flash?: {
    notice?: string
    alert?: string
  }
  password_errors?: {
    new_password?: string[]
    new_password_confirmation?: string[]
  }
}

export default function Edit({ auth, account: user, organization, roles, flash, password_errors }: AdminOrgUsersEditProps) {
  const currentAccount = auth.account
  const [newPassword, setNewPassword] = useState('')
  const [newPasswordConfirmation, setNewPasswordConfirmation] = useState('')
  const [isSendingResetEmail, setIsSendingResetEmail] = useState(false)
  const [isSettingPassword, setIsSettingPassword] = useState(false)

  const { data, setData, patch, processing, errors } = useForm({
    email: user.email,
    first_name: user.first_name,
    last_name: user.last_name,
    role: user.role,
    organization_id: organization.id,
    status: user.status
  })

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    patch(`/admin/organizations/${organization.id}/users/${user.id}`)
  }

  const handleCancel = () => {
    router.visit(`/admin/organizations/${organization.id}/users`)
  }

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

  const selectBaseClasses = [
    'w-full',
    'px-3',
    'py-2',
    'h-9',
    'bg-[var(--input)]',
    'border',
    'border-[var(--input-border)]',
    'rounded-lg',
    'text-sm',
    'text-[var(--foreground)]',
    'transition-all',
    'duration-150',
    'focus:outline-none',
    'focus:border-[var(--ring)]',
    'focus:shadow-[0_0_0_2px_var(--ring-offset),0_0_0_4px_var(--ring)]',
  ].join(' ')

  return (
    <OrganizationTabLayout
      organization={organization}
      currentTab="users"
      account={currentAccount}
      flash={flash}
    >
      <div className="max-w-2xl mx-auto">
        <div className="mb-6">
          <h1 className="text-2xl font-bold tracking-tight text-[var(--foreground)]">
            {t('admin.users.edit.title')}
          </h1>
          <p className="text-[var(--foreground-muted)]">
            {t('admin.users.edit.subtitle')}
          </p>
        </div>

        <Card>
          <CardContent className="pt-6">
            <form id="user-form" onSubmit={handleSubmit} className="space-y-6">
              <Input
                label={t('admin.common.email')}
                type="email"
                value={data.email}
                disabled
                description={t('admin.users.edit.email_hint')}
              />

              <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                <Input
                  label={t('admin.common.first_name')}
                  type="text"
                  value={data.first_name}
                  onChange={e => setData('first_name', e.target.value)}
                  error={errors.first_name}
                  required
                />

                <Input
                  label={t('admin.common.last_name')}
                  type="text"
                  value={data.last_name}
                  onChange={e => setData('last_name', e.target.value)}
                  error={errors.last_name}
                  required
                />
              </div>

              <div className="flex flex-col gap-3">
                <label htmlFor="role" className="text-sm font-medium text-[var(--foreground)] leading-5">
                  {t('admin.common.role')} <span className="text-[var(--error)]">*</span>
                </label>
                <select
                  id="role"
                  value={data.role}
                  onChange={e => setData('role', e.target.value)}
                  className={selectBaseClasses}
                  required
                >
                  {roles.map(role => (
                    <option key={role} value={role}>
                      {formatRoleName(role)}
                    </option>
                  ))}
                  <option value="amplifa_admin" disabled>
                    {formatRoleName('amplifa_admin')}
                  </option>
                </select>
                <p className="flex items-start gap-2 text-xs text-[var(--foreground-muted)] -mt-1">
                  <Info className="h-4 w-4 shrink-0 text-[var(--foreground-subtle)]" />
                  <span>
                    {t('admin.users.edit.amplifa_admin_global_edit_prefix')}{' '}
                    <Link
                      href={`/admin/users/${user.id}/edit`}
                      className="text-[var(--accent)] hover:underline"
                    >
                      {t('admin.users.edit.amplifa_admin_global_edit_link')}
                    </Link>
                    {t('admin.users.edit.amplifa_admin_global_edit_suffix')}
                  </span>
                </p>
                {errors.role && (
                  <p className="text-xs text-[var(--error)] -mt-1">{errors.role}</p>
                )}
              </div>

              {user.role !== data.role && (
                <div className="bg-[var(--warning)]/10 border border-[var(--warning)]/20 rounded-lg p-4">
                  <div className="flex gap-3">
                    <AlertTriangle className="h-5 w-5 text-[var(--warning)] shrink-0 mt-0.5" />
                    <div>
                      <h3 className="text-sm font-medium text-[var(--warning)]">
                        {t('admin.users.edit.role_change_warning_title')}
                      </h3>
                      <p className="mt-1 text-sm text-[var(--warning)]/80">
                        {t('admin.users.edit.role_change_warning_message', {
                          old_role: formatRoleName(user.role),
                          new_role: formatRoleName(data.role)
                        })}
                      </p>
                    </div>
                  </div>
                </div>
              )}
            </form>
          </CardContent>

          <CardFooter className="flex items-center justify-end gap-3 bg-[var(--card-footer)] border-t border-[var(--border)] rounded-b-xl px-6 py-4">
            <Button
              type="button"
              variant="secondary"
              onClick={handleCancel}
            >
              {t('admin.common.cancel')}
            </Button>
            <Button
              type="submit"
              form="user-form"
              loading={processing}
            >
              {processing ? t('admin.common.saving') : t('admin.common.save_changes')}
            </Button>
          </CardFooter>
        </Card>

        <Card className="mt-6">
          <CardHeader>
            <h2 className="text-lg font-semibold text-[var(--foreground)] flex items-center gap-2">
              <KeyRound className="h-5 w-5" />
              {t('admin.users.password.title')}
            </h2>
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
