/**
 * Admin Users Edit Page
 * Form to edit an existing user account
 *
 * Design: Dark theme with Card wrapper, Input/Button components
 * Migration: Task 5.3.3 (Phase 5)
 */
import { router, useForm } from '@inertiajs/react'
import { useState } from 'react'
import AuthenticatedLayout from '../../../layouts/AuthenticatedLayout'
import { t } from '../../../lib/i18n'
import { Card, CardContent, CardFooter, CardHeader } from '../../../components/ui/Card'
import { Input } from '../../../components/ui/Input'
import { Button } from '../../../components/ui/Button'
import { toast } from '../../../components/ui/Toaster'
import { AlertTriangle, Building2, KeyRound, Mail, Plus, ShieldCheck, Trash2 } from 'lucide-react'

interface Organization {
  id: number
  name: string
}

interface Account {
  id: number
  email: string
  first_name: string
  last_name: string
  role: string
  organization_id: number | null
  status: string
  deactivated_at: string | null
  two_factor_authentication_required: boolean
  organization: Organization | null
}

interface OrganizationMembership {
  id: number
  role: string
  status: string
  organization_id: number
  organization: Organization
}

interface Flash {
  notice?: string
  alert?: string
}

interface AdminUsersEditProps {
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
  organizations: Organization[]
  organization_memberships: OrganizationMembership[]
  assignable_organizations: Organization[]
  membership_roles: string[]
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

export default function Edit({
  auth,
  account: user,
  organization_memberships,
  assignable_organizations,
  membership_roles,
  flash,
  password_errors
}: AdminUsersEditProps) {
  const currentAccount = auth.account
  const [newPassword, setNewPassword] = useState('')
  const [newPasswordConfirmation, setNewPasswordConfirmation] = useState('')
  const [isSendingResetEmail, setIsSendingResetEmail] = useState(false)
  const [isSettingPassword, setIsSettingPassword] = useState(false)
  const [membershipOrganizationId, setMembershipOrganizationId] = useState('')
  const [membershipRole, setMembershipRole] = useState('customer_user')
  const [isAddingMembership, setIsAddingMembership] = useState(false)
  const [updatingMembershipId, setUpdatingMembershipId] = useState<number | null>(null)
  const [removingMembershipId, setRemovingMembershipId] = useState<number | null>(null)
  const [isAutosavingPlatformAccess, setIsAutosavingPlatformAccess] = useState(false)

  const { data, setData, patch, processing, errors } = useForm({
    email: user.email,
    first_name: user.first_name,
    last_name: user.last_name,
    platform_admin: user.role === 'amplifa_admin',
    status: user.status,
    two_factor_authentication_required: user.two_factor_authentication_required
  })

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()

    const wasPlatformAdmin = user.role === 'amplifa_admin'

    if (!wasPlatformAdmin && data.platform_admin) {
      const confirmed = window.confirm(t('admin.users.edit.amplifa_admin_promotion_confirm'))
      if (!confirmed) return
    }

    patch(`/admin/users/${user.id}`)
  }

  const handleCancel = () => {
    router.visit('/admin/users')
  }

  const handleSendResetEmail = () => {
    if (isSendingResetEmail) return

    setIsSendingResetEmail(true)
    router.post(
      `/admin/users/${user.id}/send_reset_password_email`,
      {},
      {
        preserveScroll: true,
        onFinish: () => setIsSendingResetEmail(false)
      }
    )
  }

  const autosavePlatformAccess = (nextPlatformAdmin: boolean, nextTwoFactorRequired: boolean) => {
    if (isAutosavingPlatformAccess) return

    const previousPlatformAdmin = data.platform_admin
    const previousTwoFactorRequired = data.two_factor_authentication_required

    setData({
      ...data,
      platform_admin: nextPlatformAdmin,
      two_factor_authentication_required: nextTwoFactorRequired
    })
    setIsAutosavingPlatformAccess(true)

    router.patch(
      `/admin/users/${user.id}`,
      {
        platform_admin: nextPlatformAdmin,
        two_factor_authentication_required: nextTwoFactorRequired,
        platform_access_autosave: true
      },
      {
        preserveScroll: true,
        preserveState: true,
        onSuccess: page => {
          const flash = (page.props as { flash?: Flash }).flash
          if (flash?.alert) {
            setData({
              ...data,
              platform_admin: previousPlatformAdmin,
              two_factor_authentication_required: previousTwoFactorRequired
            })
            toast.error(flash.alert)
          } else if (flash?.notice) {
            toast.success(flash.notice)
          }
        },
        onError: () => {
          setData({
            ...data,
            platform_admin: previousPlatformAdmin,
            two_factor_authentication_required: previousTwoFactorRequired
          })
          toast.error(t('admin.common.error'))
        },
        onFinish: () => setIsAutosavingPlatformAccess(false)
      }
    )
  }

  const handlePlatformAdminChange = (enabled: boolean) => {
    const wasPlatformAdmin = user.role === 'amplifa_admin'

    if (!wasPlatformAdmin && enabled) {
      const confirmed = window.confirm(t('admin.users.edit.amplifa_admin_promotion_confirm'))
      if (!confirmed) return
    }

    autosavePlatformAccess(enabled, data.two_factor_authentication_required)
  }

  const handleTwoFactorChange = (enabled: boolean) => {
    autosavePlatformAccess(data.platform_admin, enabled)
  }

  const handleSetPassword = (e: React.FormEvent) => {
    e.preventDefault()
    if (isSettingPassword) return

    setIsSettingPassword(true)
    router.post(
      `/admin/users/${user.id}/set_password`,
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

  const handleAddMembership = (e: React.FormEvent) => {
    e.preventDefault()
    if (isAddingMembership || !membershipOrganizationId) return

    setIsAddingMembership(true)
    router.post(
      `/admin/users/${user.id}/add_organization_membership`,
      {
        organization_membership: {
          organization_id: membershipOrganizationId,
          role: membershipRole
        }
      },
      {
        preserveScroll: true,
        onSuccess: page => {
          const flash = (page.props as { flash?: Flash }).flash
          if (flash?.alert) {
            toast.error(flash.alert)
          } else {
            if (flash?.notice) toast.success(flash.notice)
            setMembershipOrganizationId('')
            setMembershipRole('customer_user')
          }
        },
        onError: () => toast.error(t('admin.users.memberships.update_failed')),
        onFinish: () => setIsAddingMembership(false)
      }
    )
  }

  const handleUpdateMembershipRole = (membership: OrganizationMembership, role: string) => {
    if (membership.role === role || updatingMembershipId) return

    setUpdatingMembershipId(membership.id)
    router.patch(
      `/admin/users/${user.id}/organization_memberships/${membership.id}`,
      {
        organization_membership: { role }
      },
      {
        preserveScroll: true,
        onSuccess: page => {
          const flash = (page.props as { flash?: Flash }).flash
          if (flash?.alert) {
            toast.error(flash.alert)
          } else {
            toast.success(t('admin.users.memberships.role_change_success', {
              organization: membership.organization.name,
              role: formatRoleName(role)
            }))
          }
        },
        onError: () => toast.error(t('admin.users.memberships.update_failed')),
        onFinish: () => setUpdatingMembershipId(null)
      }
    )
  }

  const handleRemoveMembership = (membership: OrganizationMembership) => {
    if (removingMembershipId) return
    if (!window.confirm(t('admin.users.memberships.remove_confirm', { organization: membership.organization.name }))) return

    setRemovingMembershipId(membership.id)
    router.delete(`/admin/users/${user.id}/organization_memberships/${membership.id}`, {
      preserveScroll: true,
      onSuccess: page => {
        const flash = (page.props as { flash?: Flash }).flash
        if (flash?.alert) {
          toast.error(flash.alert)
        } else if (flash?.notice) {
          toast.success(flash.notice)
        }
      },
      onError: () => toast.error(t('admin.users.memberships.update_failed')),
      onFinish: () => setRemovingMembershipId(null)
    })
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

  // Common select classes for dark theme
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
    <AuthenticatedLayout
      title={t('admin.users.edit.title')}
      subtitle={t('admin.users.edit.subtitle')}
      account={currentAccount}
      flash={flash}
    >
      <div className="max-w-2xl space-y-6">
        {/* Form Card */}
        <Card>
          <CardContent>
            <form id="user-form" onSubmit={handleSubmit} className="space-y-6">
            {/* Email (Read-only) */}
            <Input
              label={t('admin.common.email')}
              type="email"
              value={data.email}
              disabled
              description={t('admin.users.edit.email_hint')}
            />

            {/* First Name */}
            <Input
              label={t('admin.common.first_name')}
              type="text"
              value={data.first_name}
              onChange={e => setData('first_name', e.target.value)}
              error={errors.first_name}
              required
            />

            {/* Last Name */}
            <Input
              label={t('admin.common.last_name')}
              type="text"
              value={data.last_name}
              onChange={e => setData('last_name', e.target.value)}
              error={errors.last_name}
              required
            />

            </form>
          </CardContent>

          {/* Actions Footer */}
          <CardFooter className="flex items-center justify-end gap-3">
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

        <Card>
            <CardHeader>
              <h2 className="text-lg font-semibold text-[var(--foreground)] flex items-center gap-2">
                <Building2 className="h-5 w-5" />
                {t('admin.users.memberships.title')}
              </h2>
            </CardHeader>
            <CardContent>
              <div className="space-y-5">
                <div className="space-y-2">
                  {organization_memberships.length > 0 ? (
                    organization_memberships.map(membership => (
                      <div
                        key={membership.id}
                        className="flex flex-col gap-3 rounded-lg border border-[var(--border)]/50 bg-[var(--card-hover)]/50 px-4 py-3 sm:flex-row sm:items-center sm:justify-between"
                      >
                        <div className="min-w-0">
                          <div className="truncate text-sm font-medium text-[var(--foreground)]">
                            {membership.organization.name}
                          </div>
                          <div className="text-xs text-[var(--foreground-muted)]">
                            {formatRoleName(membership.role)}
                          </div>
                        </div>
                        <div className="flex flex-wrap items-center gap-2">
                          <select
                            value={membership.role}
                            onChange={event => handleUpdateMembershipRole(membership, event.target.value)}
                            className="h-9 rounded-lg border border-[var(--input-border)] bg-[var(--input)] px-3 text-sm text-[var(--foreground)] focus:border-[var(--ring)] focus:outline-none"
                            disabled={updatingMembershipId === membership.id}
                            aria-label={t('admin.users.memberships.edit_role_label', { organization: membership.organization.name })}
                          >
                            {membership_roles.map(role => (
                              <option key={role} value={role}>{formatRoleName(role)}</option>
                            ))}
                          </select>
                          <Button
                            type="button"
                            variant="secondary"
                            loading={removingMembershipId === membership.id}
                            onClick={() => handleRemoveMembership(membership)}
                            icon={<Trash2 className="h-4 w-4" />}
                          >
                            {t('admin.users.memberships.remove_button')}
                          </Button>
                        </div>
                      </div>
                    ))
                  ) : (
                    <p className="text-sm text-[var(--foreground-muted)]">
                      {t('admin.users.memberships.empty')}
                    </p>
                  )}
                </div>

                <form onSubmit={handleAddMembership} className="space-y-4 rounded-lg border border-[var(--border)]/50 bg-[var(--card-hover)]/50 p-4">
                  <div>
                    <h3 className="text-sm font-medium text-[var(--foreground)]">
                      {t('admin.users.memberships.add_title')}
                    </h3>
                    <p className="mt-1 text-sm text-[var(--foreground-muted)]">
                      {t('admin.users.memberships.add_description')}
                    </p>
                  </div>

                  <div className="grid gap-4 sm:grid-cols-[1fr_180px]">
                    <div className="flex flex-col gap-3">
                      <label htmlFor="membership_organization_id" className="text-sm font-medium text-[var(--foreground)] leading-5">
                        {t('admin.users.memberships.organization_label')}
                      </label>
                      <select
                        id="membership_organization_id"
                        value={membershipOrganizationId}
                        onChange={e => setMembershipOrganizationId(e.target.value)}
                        className={selectBaseClasses}
                        disabled={assignable_organizations.length === 0}
                        required
                      >
                        <option value="">{t('admin.users.memberships.select_organization')}</option>
                        {assignable_organizations.map(org => (
                          <option key={org.id} value={org.id}>
                            {org.name}
                          </option>
                        ))}
                      </select>
                    </div>

                    <div className="flex flex-col gap-3">
                      <label htmlFor="membership_role" className="text-sm font-medium text-[var(--foreground)] leading-5">
                        {t('admin.users.memberships.role_label')}
                      </label>
                      <select
                        id="membership_role"
                        value={membershipRole}
                        onChange={e => setMembershipRole(e.target.value)}
                        className={selectBaseClasses}
                        disabled={assignable_organizations.length === 0}
                        required
                      >
                        {membership_roles.map(role => (
                          <option key={role} value={role}>
                            {formatRoleName(role)}
                          </option>
                        ))}
                      </select>
                    </div>
                  </div>

                  <div className="flex items-center justify-between gap-4">
                    <p className="text-xs text-[var(--foreground-muted)]">
                      {assignable_organizations.length === 0
                        ? t('admin.users.memberships.no_assignable_organizations')
                        : t('admin.users.memberships.available_count', { count: assignable_organizations.length })}
                    </p>
                    <Button
                      type="submit"
                      loading={isAddingMembership}
                      disabled={assignable_organizations.length === 0 || !membershipOrganizationId}
                      icon={<Plus className="h-4 w-4" />}
                    >
                      {t('admin.users.memberships.add_button')}
                    </Button>
                  </div>
                </form>
              </div>
            </CardContent>
        </Card>

        <Card>
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

        <Card>
          <CardHeader>
            <h2 className="text-lg font-semibold text-[var(--foreground)] flex items-center gap-2">
              <ShieldCheck className="h-5 w-5" />
              {t('admin.users.platform_access.title')}
            </h2>
          </CardHeader>
          <CardContent>
            <div className="space-y-5">
              <div className="relative flex items-start rounded-lg border border-[var(--border)]/50 bg-[var(--card-hover)]/50 p-4">
                <div className="flex h-6 items-center">
                  <input
                    type="checkbox"
                    id="platform_admin"
                    checked={data.platform_admin}
                    onChange={event => handlePlatformAdminChange(event.target.checked)}
                    disabled={isAutosavingPlatformAccess}
                    className="h-5 w-5 rounded bg-[var(--input)] border-[var(--input-border)] text-[var(--accent)] focus:ring-[var(--ring)] transition-colors cursor-pointer"
                  />
                </div>
                <div className="ml-3 text-sm leading-6">
                  <label htmlFor="platform_admin" className="font-medium text-[var(--foreground)] cursor-pointer">
                    {t('admin.users.platform_access.amplifa_admin_label')}
                  </label>
                  <p className="text-[var(--foreground-muted)]">
                    {t('admin.users.platform_access.amplifa_admin_help')}
                  </p>
                </div>
              </div>

              <div className="rounded-lg border border-[var(--warning)]/20 bg-[var(--warning)]/10 p-4">
                <div className="flex gap-3">
                  <AlertTriangle className="h-5 w-5 text-[var(--warning)] shrink-0 mt-0.5" />
                  <p className="text-sm text-[var(--warning)]/85">
                    {t('admin.users.platform_access.amplifa_admin_warning')}
                  </p>
                </div>
              </div>

              {data.platform_admin && (
                <div className="relative flex items-start">
                  <div className="flex h-6 items-center">
                    <input
                      type="checkbox"
                      id="two_factor_authentication_required"
                      checked={data.two_factor_authentication_required}
                      onChange={e => handleTwoFactorChange(e.target.checked)}
                      disabled={isAutosavingPlatformAccess}
                      className="h-5 w-5 rounded bg-[var(--input)] border-[var(--input-border)] text-[var(--accent)] focus:ring-[var(--ring)] transition-colors cursor-pointer"
                    />
                  </div>
                  <div className="ml-3 text-sm leading-6">
                    <label htmlFor="two_factor_authentication_required" className="font-medium text-[var(--foreground)] cursor-pointer">
                      {t('admin.users.edit.two_factor_authentication_required_label')}
                    </label>
                    <p className="text-[var(--foreground-muted)]">
                      {t('admin.users.edit.two_factor_authentication_required_help')}
                    </p>
                  </div>
                </div>
              )}

              {user.role === 'amplifa_admin' && !data.platform_admin && (
                <p className="text-sm text-[var(--foreground-muted)]">
                  {t('admin.users.platform_access.demote_help')}
                </p>
              )}
            </div>
          </CardContent>
        </Card>
      </div>
    </AuthenticatedLayout>
  )
}
