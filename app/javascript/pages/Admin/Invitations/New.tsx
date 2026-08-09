/**
 * Admin Invitations New Page
 * Form to create a new invitation
 *
 * Design: Dark theme with Card, Input, Button components
 * Migration: Task 5.3.7 (Phase 5)
 */
import { router, useForm } from '@inertiajs/react'
import AuthenticatedLayout from '../../../layouts/AuthenticatedLayout'
import { t } from '../../../lib/i18n'
import { Card, CardContent, CardFooter } from '../../../components/ui/Card'
import { Input } from '../../../components/ui/Input'
import { Button } from '../../../components/ui/Button'
import { Info } from 'lucide-react'

// WHY: Define TypeScript interfaces for type safety
interface Organization {
  id: number
  name: string
}

interface AdminInvitationsNewProps {
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
  preselected_organization_id?: number | null
  errors?: {
    email?: string[]
    first_name?: string[]
    last_name?: string[]
    role?: string[]
    organization_id?: string[]
  }
  invitation?: {
    email: string
    first_name: string
    last_name: string
    role: string
    organization_id: number
  }
  flash?: {
    notice?: string
    alert?: string
  }
}

export default function New({ auth, organizations, roles, preselected_organization_id, errors: serverErrors, invitation, flash }: AdminInvitationsNewProps) {
  const currentAccount = auth.account

  // WHY: Use Inertia's useForm hook for form state management and validation
  // WHY: Wrap form data in 'invitation' namespace to match Rails strong parameters
  // WHY: Use preselected_organization_id if provided (e.g., from organization edit page invite button)
  const { data, setData, post, processing, errors } = useForm({
    invitation: {
      email: invitation?.email || '',
      first_name: invitation?.first_name || '',
      last_name: invitation?.last_name || '',
      role: invitation?.role || 'customer_user',
      organization_id: invitation?.organization_id || preselected_organization_id || ''
    }
  })

  // WHY: Merge server-side errors with client-side errors from useForm
  const allErrors = { ...errors, ...serverErrors }

  // WHY: Handle form submission via Inertia POST request
  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    post('/admin/invitations')
  }

  // WHY: Navigate back to invitations list on cancel
  const handleCancel = () => {
    router.visit('/admin/invitations')
  }

  // WHY: Format role names for display consistency
  const formatRoleName = (role: string) => {
    return t(`admin.roles.${role}`, { defaultValue: role })
  }

  // WHY: Get role descriptions for user guidance
  const getRoleDescription = (role: string) => {
    return t(`admin.roles.descriptions.${role}`, { defaultValue: '' })
  }

  // WHY: Get the first error string from an error array or string
  const getErrorString = (error: string[] | string | undefined): string | undefined => {
    if (Array.isArray(error)) return error[0]
    return error
  }

  return (
    <AuthenticatedLayout
      title={t('admin.invitations.new.title')}
      subtitle={t('admin.invitations.new.subtitle')}
      account={currentAccount}
      flash={flash}
    >
      <Card className="max-w-2xl">
        <form onSubmit={handleSubmit}>
          <CardContent className="pt-6 space-y-6">
            {/* Organization Selection */}
            <div>
              <label htmlFor="organization_id" className="block text-sm font-medium text-[var(--foreground)] mb-2">
                {t('admin.common.organization')}
              </label>
              <select
                id="organization_id"
                value={data.invitation.organization_id}
                onChange={e => setData('invitation', { ...data.invitation, organization_id: e.target.value })}
                className={`block w-full px-3 py-2.5 bg-[var(--input)] border rounded-lg text-[var(--foreground)] text-sm focus:outline-none focus:ring-2 focus:ring-[var(--ring)] focus:border-transparent transition-all ${
                  allErrors.organization_id ? 'border-[var(--error)]' : 'border-[var(--input-border)]'
                }`}
                required
              >
                <option value="">{t('admin.invitations.new.organization_placeholder')}</option>
                {organizations.map(org => (
                  <option key={org.id} value={org.id}>
                    {org.name}
                  </option>
                ))}
              </select>
              <p className="mt-1 text-xs text-[var(--foreground-muted)]">
                {t('admin.invitations.new.organization_description')}
              </p>
              {allErrors.organization_id && (
                <p className="mt-1 text-sm text-[var(--error)]">
                  {getErrorString(allErrors.organization_id)}
                </p>
              )}
            </div>

            {/* Email Input */}
            <Input
              id="email"
              type="email"
              label={t('admin.common.email')}
              value={data.invitation.email}
              onChange={e => setData('invitation', { ...data.invitation, email: e.target.value })}
              placeholder={t('admin.invitations.new.email_placeholder')}
              description={t('admin.invitations.new.email_description')}
              error={getErrorString(allErrors.email)}
              required
            />

            {/* Name Fields */}
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <Input
                id="first_name"
                type="text"
                label={t('admin.common.first_name')}
                value={data.invitation.first_name}
                onChange={e => setData('invitation', { ...data.invitation, first_name: e.target.value })}
                placeholder={t('admin.invitations.new.first_name_placeholder')}
                error={getErrorString(allErrors.first_name)}
                required
              />

              <Input
                id="last_name"
                type="text"
                label={t('admin.common.last_name')}
                value={data.invitation.last_name}
                onChange={e => setData('invitation', { ...data.invitation, last_name: e.target.value })}
                placeholder={t('admin.invitations.new.last_name_placeholder')}
                error={getErrorString(allErrors.last_name)}
                required
              />
            </div>

            {/* Role Selection */}
            <div>
              <label className="block text-sm font-medium text-[var(--foreground)] mb-3">
                {t('admin.common.role')}
              </label>
              <div className="space-y-3">
                {roles.map(role => (
                  <label
                    key={role}
                    className={`flex items-start p-4 border rounded-lg cursor-pointer transition-all ${
                      data.invitation.role === role
                        ? 'border-[var(--accent)] bg-[var(--accent)]/10'
                        : 'border-[var(--border)] hover:border-[var(--border-strong)] bg-transparent'
                    }`}
                  >
                    <input
                      type="radio"
                      name="role"
                      value={role}
                      checked={data.invitation.role === role}
                      onChange={e => setData('invitation', { ...data.invitation, role: e.target.value })}
                      className="mt-1 h-4 w-4 text-[var(--accent)] bg-[var(--input)] border-[var(--input-border)] focus:ring-[var(--ring)] focus:ring-offset-0"
                    />
                    <div className="ml-3">
                      <div className="text-sm font-semibold text-[var(--foreground)]">
                        {formatRoleName(role)}
                      </div>
                      <div className="text-sm text-[var(--foreground-muted)]">
                        {getRoleDescription(role)}
                      </div>
                    </div>
                  </label>
                ))}
              </div>
              {allErrors.role && (
                <p className="mt-2 text-sm text-[var(--error)]">
                  {getErrorString(allErrors.role)}
                </p>
              )}
            </div>

            {/* Information Box */}
            <div className="rounded-lg bg-[var(--accent)]/10 border border-[var(--accent)]/20 p-4">
              <div className="flex">
                <div className="flex-shrink-0">
                  <Info className="h-5 w-5 text-[var(--accent)]" />
                </div>
                <div className="ml-3 flex-1">
                  <h3 className="text-sm font-semibold text-[var(--accent)]">
                    {t('admin.invitations.new.info_title')}
                  </h3>
                  <div className="mt-2 text-sm text-[var(--accent)]/80">
                    <ul className="list-disc pl-5 space-y-1">
                      <li>{t('admin.invitations.new.info_messages.0')}</li>
                      <li>{t('admin.invitations.new.info_messages.1')}</li>
                      <li>{t('admin.invitations.new.info_messages.2')}</li>
                      <li>{t('admin.invitations.new.info_messages.3')}</li>
                    </ul>
                  </div>
                </div>
              </div>
            </div>
          </CardContent>

          {/* Form Actions */}
          <CardFooter className="flex justify-end gap-3">
            <Button
              type="button"
              variant="secondary"
              onClick={handleCancel}
              disabled={processing}
            >
              {t('admin.common.cancel')}
            </Button>
            <Button
              type="submit"
              loading={processing}
            >
              {processing ? t('admin.invitations.new.submitting') : t('admin.invitations.new.submit')}
            </Button>
          </CardFooter>
        </form>
      </Card>
    </AuthenticatedLayout>
  )
}
