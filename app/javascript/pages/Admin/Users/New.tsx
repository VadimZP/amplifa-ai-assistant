/**
 * Admin Users New Page
 * Form to create a new user account
 *
 * Design: Dark theme with Card wrapper, Input/Button components
 * Migration: Task 5.3.3 (Phase 5)
 */
import { useState, useMemo } from 'react'
import { router, useForm } from '@inertiajs/react'
import AuthenticatedLayout from '../../../layouts/AuthenticatedLayout'
import { t } from '../../../lib/i18n'
import { Card, CardContent, CardFooter } from '../../../components/ui/Card'
import { Input } from '../../../components/ui/Input'
import { Button } from '../../../components/ui/Button'
import { Eye, EyeOff, Info } from 'lucide-react'

const getUrlParams = () => {
  if (typeof window !== 'undefined') {
    return new URLSearchParams(window.location.search)
  }
  return new URLSearchParams()
}

interface Organization {
  id: number
  name: string
}

interface AdminUsersNewProps {
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
  organizations: Organization[]
  roles: string[]
  flash?: {
    notice?: string
    alert?: string
  }
}

export default function New({ auth, organizations, roles, flash }: AdminUsersNewProps) {
  const currentAccount = auth.account
  
  const urlParams = useMemo(getUrlParams, [])
  const preselectedOrgId = urlParams.get('organization_id') || ''
  const returnTo = urlParams.get('return_to') || '/admin/users'

  const { data, setData, post, processing, errors } = useForm({
    email: '',
    first_name: '',
    last_name: '',
    password: '',
    password_confirmation: '',
    role: 'customer_user',
    organization_id: preselectedOrgId
  })

  const [showPassword, setShowPassword] = useState(false)
  const [showPasswordConfirmation, setShowPasswordConfirmation] = useState(false)

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    post('/admin/users')
  }

  const handleCancel = () => {
    router.visit(returnTo)
  }

  const requiresOrganization = data.role === 'customer_admin' || data.role === 'customer_user'

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

  // Password strength indicator
  const getPasswordStrength = (password: string) => {
    if (password.length === 0) return { strength: 0, text: '', color: '' }

    let strength = 0
    if (password.length >= 8) strength++
    if (/[0-9]/.test(password)) strength++
    if (/[^A-Za-z0-9]/.test(password)) strength++
    if (password.length >= 12) strength++

    const strengthMap = {
      1: { text: t('admin.password_strength.weak'), color: 'bg-[var(--error)]' },
      2: { text: t('admin.password_strength.fair'), color: 'bg-[var(--warning)]' },
      3: { text: t('admin.password_strength.good'), color: 'bg-blue-500' },
      4: { text: t('admin.password_strength.strong'), color: 'bg-[var(--success)]' }
    }

    return { strength, ...strengthMap[Math.min(strength, 4) as keyof typeof strengthMap] }
  }

  const passwordStrength = getPasswordStrength(data.password)

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

  const selectDisabledClasses = 'bg-[var(--secondary)] cursor-not-allowed text-[var(--foreground-muted)]'

  return (
    <AuthenticatedLayout
      title={t('admin.users.new.title')}
      subtitle={t('admin.users.new.subtitle')}
      account={currentAccount}
      flash={flash}
      backLink={returnTo}
      backLinkText={t('admin.common.back')}
    >
      {/* Form Card */}
      <Card className="max-w-2xl">
        <CardContent>
          <form id="user-form" onSubmit={handleSubmit} className="space-y-6">
            {/* Email */}
            <Input
              label={t('admin.common.email')}
              type="email"
              value={data.email}
              onChange={e => setData('email', e.target.value)}
              placeholder="user@example.com"
              error={errors.email}
              required
            />

            {/* First Name */}
            <Input
              label={t('admin.common.first_name')}
              type="text"
              value={data.first_name}
              onChange={e => setData('first_name', e.target.value)}
              placeholder="John"
              error={errors.first_name}
              required
            />

            {/* Last Name */}
            <Input
              label={t('admin.common.last_name')}
              type="text"
              value={data.last_name}
              onChange={e => setData('last_name', e.target.value)}
              placeholder="Doe"
              error={errors.last_name}
              required
            />

            {/* Password */}
            <div className="flex flex-col gap-3">
              <label htmlFor="password" className="text-sm font-medium text-[var(--foreground)] leading-5">
                {t('admin.users.new.password_label')} <span className="text-[var(--error)]">*</span>
              </label>
              <div className="relative">
                <input
                  type={showPassword ? 'text' : 'password'}
                  id="password"
                  value={data.password}
                  onChange={e => setData('password', e.target.value)}
                  placeholder={t('admin.users.new.password_placeholder')}
                  className={`w-full h-9 px-3 pr-10 bg-[var(--input)] border rounded-lg text-sm text-[var(--foreground)] placeholder:text-[var(--foreground-muted)] transition-all duration-150 focus:outline-none focus:shadow-[0_0_0_2px_var(--ring-offset),0_0_0_4px_var(--ring)] ${
                    errors.password ? 'border-[var(--error)]' : 'border-[var(--input-border)] focus:border-[var(--ring)]'
                  }`}
                  required
                />
                <button
                  type="button"
                  onClick={() => setShowPassword(!showPassword)}
                  className="absolute inset-y-0 right-0 pr-3 flex items-center text-[var(--foreground-muted)] hover:text-[var(--foreground)] transition-colors"
                >
                  {showPassword ? (
                    <EyeOff className="h-4 w-4" />
                  ) : (
                    <Eye className="h-4 w-4" />
                  )}
                </button>
              </div>
              {data.password && (
                <div className="-mt-1">
                  <div className="flex items-center justify-between mb-1">
                    <span className="text-xs text-[var(--foreground-muted)]">{t('admin.users.new.password_strength_label')}</span>
                    <span className={`text-xs font-semibold ${
                      passwordStrength.strength >= 3 ? 'text-[var(--success)]' :
                      passwordStrength.strength >= 2 ? 'text-[var(--warning)]' : 'text-[var(--error)]'
                    }`}>
                      {passwordStrength.text}
                    </span>
                  </div>
                  <div className="w-full bg-[var(--secondary)] rounded-full h-1.5">
                    <div
                      className={`h-1.5 rounded-full transition-all duration-300 ${passwordStrength.color}`}
                      style={{ width: `${(passwordStrength.strength / 4) * 100}%` }}
                    />
                  </div>
                </div>
              )}
              <p className="text-xs text-[var(--foreground-muted)] -mt-1">{t('admin.users.new.password_hint')}</p>
              {errors.password && (
                <p className="text-xs text-[var(--error)] -mt-1">{errors.password}</p>
              )}
            </div>

            {/* Password Confirmation */}
            <div className="flex flex-col gap-3">
              <label htmlFor="password_confirmation" className="text-sm font-medium text-[var(--foreground)] leading-5">
                {t('admin.users.new.password_confirmation_label')} <span className="text-[var(--error)]">*</span>
              </label>
              <div className="relative">
                <input
                  type={showPasswordConfirmation ? 'text' : 'password'}
                  id="password_confirmation"
                  value={data.password_confirmation}
                  onChange={e => setData('password_confirmation', e.target.value)}
                  placeholder={t('admin.users.new.confirm_password_placeholder')}
                  className={`w-full h-9 px-3 pr-10 bg-[var(--input)] border rounded-lg text-sm text-[var(--foreground)] placeholder:text-[var(--foreground-muted)] transition-all duration-150 focus:outline-none focus:shadow-[0_0_0_2px_var(--ring-offset),0_0_0_4px_var(--ring)] ${
                    errors.password_confirmation ? 'border-[var(--error)]' : 'border-[var(--input-border)] focus:border-[var(--ring)]'
                  }`}
                  required
                />
                <button
                  type="button"
                  onClick={() => setShowPasswordConfirmation(!showPasswordConfirmation)}
                  className="absolute inset-y-0 right-0 pr-3 flex items-center text-[var(--foreground-muted)] hover:text-[var(--foreground)] transition-colors"
                >
                  {showPasswordConfirmation ? (
                    <EyeOff className="h-4 w-4" />
                  ) : (
                    <Eye className="h-4 w-4" />
                  )}
                </button>
              </div>
              {errors.password_confirmation && (
                <p className="text-xs text-[var(--error)] -mt-1">{errors.password_confirmation}</p>
              )}
            </div>

            {/* Role */}
            <div className="flex flex-col gap-3">
              <label htmlFor="role" className="text-sm font-medium text-[var(--foreground)] leading-5">
                {t('admin.common.role')} <span className="text-[var(--error)]">*</span>
              </label>
              <select
                id="role"
                value={data.role}
                onChange={e => {
                  setData('role', e.target.value)
                  // Clear organization if switching to amplifa_admin
                  if (e.target.value === 'amplifa_admin') {
                    setData('organization_id', '')
                  }
                }}
                className={selectBaseClasses}
                required
              >
                {roles.map(role => (
                  <option key={role} value={role}>
                    {formatRoleName(role)}
                  </option>
                ))}
              </select>
              {errors.role && (
                <p className="text-xs text-[var(--error)] -mt-1">{errors.role}</p>
              )}
            </div>

            {/* Organization - Always show, but disabled for amplifa_admin */}
            <div className="flex flex-col gap-3">
              <label htmlFor="organization_id" className="text-sm font-medium text-[var(--foreground)] leading-5">
                {t('admin.common.organization')} {requiresOrganization && <span className="text-[var(--error)]">*</span>}
              </label>
              <select
                id="organization_id"
                value={data.organization_id}
                onChange={e => setData('organization_id', e.target.value)}
                disabled={!requiresOrganization}
                className={`${selectBaseClasses} ${!requiresOrganization ? selectDisabledClasses : ''}`}
                required={requiresOrganization}
              >
                {requiresOrganization ? (
                  <>
                    <option value="">{t('admin.users.new.select_organization')}</option>
                    {organizations.map(org => (
                      <option key={org.id} value={org.id}>
                        {org.name}
                      </option>
                    ))}
                  </>
                ) : (
                  <option value="">{t('admin.users.new.organization_na')}</option>
                )}
              </select>
              {!requiresOrganization && (
                <p className="text-xs text-[var(--foreground-muted)] -mt-1">{t('admin.users.new.organization_hint')}</p>
              )}
              {errors.organization_id && (
                <p className="text-xs text-[var(--error)] -mt-1">{errors.organization_id}</p>
              )}
            </div>

            {/* Info box */}
            <div className="bg-[var(--accent)]/10 border border-[var(--accent)]/20 rounded-lg p-4">
              <div className="flex gap-3">
                <Info className="h-5 w-5 text-[var(--accent)] shrink-0 mt-0.5" />
                <div>
                  <h3 className="text-sm font-medium text-[var(--accent)]">
                    {t('admin.users.new.info_title')}
                  </h3>
                  <p className="mt-1 text-sm text-[var(--accent)]/80">
                    {t('admin.users.new.info_message')}
                  </p>
                </div>
              </div>
            </div>
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
            {processing ? t('admin.common.creating') : t('admin.users.new.create_button')}
          </Button>
        </CardFooter>
      </Card>
    </AuthenticatedLayout>
  )
}
