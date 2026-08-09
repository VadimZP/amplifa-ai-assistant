/**
 * Admin Organizations Edit Page
 * Form to edit an existing organization
 *
 * Design: Dark theme with Card wrapper, Input/Button components
 * Migration: Task 5.3.4 (Phase 5)
 */
import { Link, useForm, router } from '@inertiajs/react'
import { useState } from 'react'
import AuthenticatedLayout from '../../../layouts/AuthenticatedLayout'
import { t } from '../../../lib/i18n'
import { Card, CardContent, CardFooter } from '../../../components/ui/Card'
import { Input } from '../../../components/ui/Input'
import { Button } from '../../../components/ui/Button'
import { Badge } from '../../../components/ui/Badge'
import { Table, TableHeader, TableBody, TableRow, TableHead, TableCell } from '../../../components/ui/Table'
import { AlertTriangle, Info, UserPlus, Download } from 'lucide-react'

interface AccountInfo {
  id: number
  email: string
  first_name: string
  last_name: string
  role: string
}



interface Organization {
  id: number
  name: string
  industry: string
  size: string
  onboarded: boolean
  deactivated_at: string | null
  website: string | null
  average_contract_value: number | null
  meeting_price: number | null
  monthly_subscription: number | null
  monthly_meeting_limit: number
  plan_tier: string
  two_factor_authentication_required: boolean
  calendly_url: string | null
  locale: string
  currency: string
  billing_cycle_started_on: string | null
  accounts: AccountInfo[]
}

interface WebsiteCache {
  url: string
  scraped_at: string
  age_in_hours: number
}

interface AdminOrganizationEditProps {
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
  organization: Organization
  size_options: string[]
  locale_options: string[]
  currency_options: string[]
  plan_options: {
    identifier: string
    name: string
    monthly_meeting_limit: number
    monthly_price: number
  }[]
  website_cache: WebsiteCache | null
  flash?: {
    notice?: string
    alert?: string
  }
}

export default function Edit({ auth, organization, size_options, locale_options, currency_options, plan_options, website_cache, flash }: AdminOrganizationEditProps) {
  const account = auth.account

  const { data, setData, put, processing, errors } = useForm({
    name: organization.name,
    industry: organization.industry || '',
    size: organization.size || '',
    onboarded: organization.onboarded,
    website: organization.website || '',
    average_contract_value: organization.average_contract_value || '',
    meeting_price: organization.meeting_price || '',
    monthly_subscription: organization.monthly_subscription || '',
    monthly_meeting_limit: organization.monthly_meeting_limit || 5,
    plan_tier: organization.plan_tier || 'basic',
    two_factor_authentication_required: organization.two_factor_authentication_required,
    calendly_url: organization.calendly_url || '',
    locale: organization.locale,
    currency: organization.currency,
    billing_cycle_started_on: organization.billing_cycle_started_on || '',
  })

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

  const [clearingCache, setClearingCache] = useState(false)

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    put(`/admin/organizations/${organization.id}`)
  }

  const handleDeactivate = () => {
    if (confirm('Are you sure you want to deactivate this organization? This will affect all associated accounts.')) {
      router.delete(`/admin/organizations/${organization.id}`)
    }
  }

  const handleClearCache = () => {
    if (!confirm('Clear website cache? The next product discovery will scrape the website fresh.')) {
      return
    }

    setClearingCache(true)
    router.delete(`/admin/organizations/${organization.id}/clear_website_cache`, {
      onFinish: () => setClearingCache(false)
    })
  }

  const handleCancel = () => {
    router.visit(`/admin/organizations/${organization.id}`)
  }

  return (
    <AuthenticatedLayout
      title={t('admin.organizations.edit.title')}
      subtitle={t('admin.organizations.edit.subtitle')}
      account={account}
      flash={flash}
      headerActions={
        <div className="flex gap-3">
          <Button
            type="button"
            variant="secondary"
            onClick={() => {
              window.location.href = `/admin/organizations/${organization.id}/export`
            }}
            icon={<Download className="h-4 w-4" />}
          >
            {t('admin.organizations.export.button')}
          </Button>
        </div>
      }
    >
      {/* Form Card */}
      <Card className="max-w-2xl">
        <CardContent>
          <form id="organization-form" onSubmit={handleSubmit} className="space-y-6">
            {/* Name */}
            <Input
              label={t('admin.organizations.edit.name_label')}
              type="text"
              value={data.name}
              onChange={e => setData('name', e.target.value)}
              error={errors.name}
              required
            />

            {/* Industry */}
            <Input
              label={t('admin.organizations.edit.industry_label')}
              type="text"
              value={data.industry}
              onChange={e => setData('industry', e.target.value)}
              error={errors.industry}
              maxLength={100}
            />

            {/* Size */}
            <div className="flex flex-col gap-3">
              <label htmlFor="size" className="text-sm font-medium text-[var(--foreground)] leading-5">
                {t('admin.organizations.edit.size_label')}
              </label>
              <select
                id="size"
                value={data.size}
                onChange={e => setData('size', e.target.value)}
                className={selectBaseClasses}
              >
                <option value="">{t('admin.organizations.edit.size_placeholder')}</option>
                {size_options.map(size => (
                  <option key={size} value={size}>
                    {size}{t('admin.organizations.new.size_suffix')}
                  </option>
                ))}
              </select>
              {errors.size && (
                <p className="text-xs text-[var(--error)] -mt-1">{errors.size}</p>
              )}
            </div>

            {/* Website & Integration Section */}
            <div className="pt-6 border-t border-[var(--border)]">
              <h3 className="text-base font-semibold text-[var(--foreground)] mb-4">
                {t('admin.organizations.edit.website_integration_section')}
              </h3>

              {/* Website */}
              <Input
                label={t('admin.organizations.edit.website_label')}
                description={t('admin.organizations.edit.website_help')}
                type="url"
                value={data.website}
                onChange={e => setData('website', e.target.value)}
                placeholder="https://www.example.com"
                error={errors.website}
              />

              {/* Website Cache Info */}
              {website_cache && (
                <div className="mt-4 p-4 bg-[var(--accent)]/10 border border-[var(--accent)]/20 rounded-lg">
                  <div className="flex items-start justify-between">
                    <div className="flex gap-3">
                      <Info className="h-5 w-5 text-[var(--accent)] shrink-0 mt-0.5" />
                      <div>
                        <p className="text-sm font-medium text-[var(--accent)]">
                          Website content cached
                        </p>
                        <p className="mt-1 text-sm text-[var(--accent)]/80">
                          Scraped {website_cache.age_in_hours}h ago from {website_cache.url}
                        </p>
                        <p className="text-xs text-[var(--accent)]/70 mt-1">
                          Cache expires after 24 hours. Playbook generation will use cached content.
                        </p>
                      </div>
                    </div>
                    <Button
                      type="button"
                      variant="ghost"
                      size="sm"
                      onClick={handleClearCache}
                      loading={clearingCache}
                      className="text-[var(--accent)]"
                    >
                      {clearingCache ? 'Clearing...' : 'Clear Cache'}
                    </Button>
                  </div>
                </div>
              )}

              {/* Calendly URL */}
              <div className="mt-6">
                <Input
                  label={t('admin.organizations.edit.calendly_url_label')}
                  description={t('admin.organizations.edit.calendly_url_help')}
                  type="url"
                  value={data.calendly_url}
                  onChange={e => setData('calendly_url', e.target.value)}
                  placeholder="https://calendly.com/company-name/meeting"
                  error={errors.calendly_url}
                />
              </div>
            </div>

            {/* Financial Information Section */}
            <div className="pt-6 border-t border-[var(--border)]">
              <h3 className="text-base font-semibold text-[var(--foreground)] mb-4">
                {t('admin.organizations.edit.financial_section')}
              </h3>

              <div className="flex flex-col gap-3">
                <label htmlFor="plan_tier" className="text-sm font-medium text-[var(--foreground)] leading-5">
                  Plan
                </label>
                <select
                  id="plan_tier"
                  value={data.plan_tier}
                  onChange={e => {
                    const nextPlanTier = e.target.value
                    setData('plan_tier', nextPlanTier)

                    const selectedPlan = plan_options.find(plan => plan.identifier === nextPlanTier)
                    if (selectedPlan) {
                      setData('monthly_meeting_limit', selectedPlan.monthly_meeting_limit)
                      setData('monthly_subscription', selectedPlan.monthly_price)
                    }
                  }}
                  className={selectBaseClasses}
                >
                  {plan_options.map(plan => (
                    <option key={plan.identifier} value={plan.identifier}>
                      {plan.name}
                    </option>
                  ))}
                </select>
                {errors.plan_tier && (
                  <p className="text-xs text-[var(--error)] -mt-1">{errors.plan_tier}</p>
                )}
                <p className="text-xs text-[var(--foreground-muted)] -mt-1">
                  Selecting a plan autofills max meetings and monthly price. You can still customize both fields below.
                </p>
              </div>

              {/* Average Contract Value */}
              <Input
                label={t('admin.organizations.edit.average_contract_value_label')}
                description={t('admin.organizations.edit.average_contract_value_help')}
                type="number"
                value={String(data.average_contract_value)}
                onChange={e => setData('average_contract_value', e.target.value)}
                placeholder="--"
                error={errors.average_contract_value}
                step="0.01"
                min="0"
              />

              {/* Meeting Price */}
              <div className="mt-6">
                <Input
                  label={t('admin.organizations.edit.meeting_price_label')}
                  description={t('admin.organizations.edit.meeting_price_help')}
                  type="number"
                  value={String(data.meeting_price)}
                  onChange={e => setData('meeting_price', e.target.value)}
                  placeholder="--"
                  error={errors.meeting_price}
                  step="0.01"
                  min="0"
                />
              </div>

              {/* Monthly Subscription */}
              <div className="mt-6">
                <Input
                  label={t('admin.organizations.edit.monthly_subscription_label')}
                  description={t('admin.organizations.edit.monthly_subscription_help')}
                  type="number"
                  value={String(data.monthly_subscription)}
                  onChange={e => setData('monthly_subscription', e.target.value)}
                  placeholder="--"
                  error={errors.monthly_subscription}
                  step="0.01"
                  min="0"
                />
              </div>

              <div className="mt-6">
                <Input
                  label={t('admin.organizations.edit.monthly_meeting_limit_label')}
                  description={t('admin.organizations.edit.monthly_meeting_limit_help')}
                  type="number"
                  value={String(data.monthly_meeting_limit)}
                  onChange={e => setData('monthly_meeting_limit', Number(e.target.value))}
                  error={errors.monthly_meeting_limit}
                  step="1"
                  min="1"
                  required
                />
              </div>

              <div className="mt-6">
                <Input
                  label={t('admin.organizations.edit.billing_begins_on_label')}
                  description={t('admin.organizations.edit.billing_begins_on_help')}
                  type="date"
                  value={data.billing_cycle_started_on}
                  onChange={e => setData('billing_cycle_started_on', e.target.value)}
                  error={errors.billing_cycle_started_on}
                  required
                />
              </div>
            </div>

            {/* Localization Section */}
            <div className="pt-6 border-t border-[var(--border)]">
              <h3 className="text-base font-semibold text-[var(--foreground)] mb-4">
                {t('admin.organizations.edit.localization_section')}
              </h3>

              {/* Locale */}
              <div className="flex flex-col gap-3">
                <label htmlFor="locale" className="text-sm font-medium text-[var(--foreground)] leading-5">
                  {t('admin.organizations.edit.locale_label')}
                </label>
                <p className="text-xs text-[var(--foreground-muted)] -mt-1">{t('admin.organizations.edit.locale_help')}</p>
                <select
                  id="locale"
                  value={data.locale}
                  onChange={e => setData('locale', e.target.value)}
                  className={selectBaseClasses}
                  required
                >
                  {locale_options.map(locale => (
                    <option key={locale} value={locale}>
                      {t(`languages.${locale}`)}
                    </option>
                  ))}
                </select>
                {errors.locale && (
                  <p className="text-xs text-[var(--error)] -mt-1">{errors.locale}</p>
                )}
              </div>

              {/* Currency */}
              <div className="flex flex-col gap-3 mt-6">
                <label htmlFor="currency" className="text-sm font-medium text-[var(--foreground)] leading-5">
                  {t('admin.organizations.edit.currency_label')}
                </label>
                <p className="text-xs text-[var(--foreground-muted)] -mt-1">{t('admin.organizations.edit.currency_help')}</p>
                <select
                  id="currency"
                  value={data.currency}
                  onChange={e => setData('currency', e.target.value)}
                  className={selectBaseClasses}
                  required
                >
                  {currency_options.map(currency => (
                    <option key={currency} value={currency}>
                      {currency}
                    </option>
                  ))}
                </select>
                {errors.currency && (
                  <p className="text-xs text-[var(--error)] -mt-1">{errors.currency}</p>
                )}
              </div>
            </div>

            {/* Security Section */}
            <div className="pt-6 border-t border-[var(--border)]">
              <h3 className="text-base font-semibold text-[var(--foreground)] mb-4">
                {t('admin.organizations.edit.security_section')}
              </h3>
              <div className="relative flex items-start">
                <div className="flex h-6 items-center">
                  <input
                    type="checkbox"
                    id="two_factor_authentication_required"
                    checked={data.two_factor_authentication_required}
                    onChange={e => setData('two_factor_authentication_required', e.target.checked)}
                    className="h-5 w-5 rounded bg-[var(--input)] border-[var(--input-border)] text-[var(--accent)] focus:ring-[var(--ring)] transition-colors cursor-pointer"
                  />
                </div>
                <div className="ml-3 text-sm leading-6">
                  <label htmlFor="two_factor_authentication_required" className="font-medium text-[var(--foreground)] cursor-pointer">
                    {t('admin.organizations.edit.two_factor_authentication_required_label')}
                  </label>
                  <p className="text-[var(--foreground-muted)]">
                    {t('admin.organizations.edit.two_factor_authentication_required_help')}
                  </p>
                </div>
              </div>
            </div>

            {/* Onboarded */}
            <div className="pt-6 border-t border-[var(--border)]">
              <div className="relative flex items-start">
                <div className="flex h-6 items-center">
                  <input
                    type="checkbox"
                    id="onboarded"
                    checked={data.onboarded}
                    onChange={e => setData('onboarded', e.target.checked)}
                    className="h-5 w-5 rounded bg-[var(--input)] border-[var(--input-border)] text-[var(--accent)] focus:ring-[var(--ring)] transition-colors cursor-pointer"
                  />
                </div>
                <label htmlFor="onboarded" className="ml-3 text-sm font-medium text-[var(--foreground)] cursor-pointer">
                  {t('admin.organizations.edit.onboarded_label')}
                </label>
              </div>
            </div>

            {/* Associated Accounts */}
            <div className="pt-6 border-t border-[var(--border)]">
              <div className="flex items-center justify-between mb-4">
                <h3 className="text-sm font-semibold text-[var(--foreground)]">
                  {t('admin.organizations.edit.associated_accounts', { count: organization.accounts.length })}
                </h3>
                <Link
                  href={`/admin/invitations/new?organization_id=${organization.id}`}
                  className="inline-flex items-center gap-1.5 h-8 px-3 text-sm font-medium rounded-lg bg-[var(--primary)] text-[var(--primary-foreground)] hover:bg-[var(--primary-hover)] transition-colors"
                >
                  <UserPlus className="h-4 w-4" />
                  {t('admin.organizations.edit.invite_button')}
                </Link>
              </div>
              {organization.accounts.length === 0 ? (
                <p className="text-sm text-[var(--foreground-muted)]">{t('admin.organizations.edit.no_accounts')}</p>
              ) : (
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Email</TableHead>
                      <TableHead>Name</TableHead>
                      <TableHead>Role</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {organization.accounts.map((acc) => (
                      <TableRow key={acc.id}>
                        <TableCell variant="primary">{acc.email}</TableCell>
                        <TableCell>
                          {acc.first_name} {acc.last_name}
                        </TableCell>
                        <TableCell>
                          {acc.role === 'org_admin' ? (
                            <Badge variant="info">
                              {t('admin.roles.org_admin')}
                            </Badge>
                          ) : (
                            <Badge variant="default">
                              {t('admin.roles.member')}
                            </Badge>
                          )}
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              )}
            </div>

            {/* Deactivate Warning */}
            {!organization.deactivated_at && (
              <div className="pt-6 border-t border-[var(--border)]">
                <div className="bg-[var(--error)]/10 border border-[var(--error)]/20 rounded-lg p-4">
                  <div className="flex gap-3">
                    <AlertTriangle className="h-5 w-5 text-[var(--error)] shrink-0 mt-0.5" />
                    <div className="flex-1">
                      <h3 className="text-sm font-medium text-[var(--error)]">
                        Danger Zone
                      </h3>
                      <p className="mt-1 text-sm text-[var(--error)]/80">
                        Deactivating this organization will affect all associated accounts.
                      </p>
                      <Button
                        type="button"
                        variant="destructive"
                        size="sm"
                        onClick={handleDeactivate}
                        className="mt-3"
                      >
                        {t('admin.organizations.edit.deactivate_button')}
                      </Button>
                    </div>
                  </div>
                </div>
              </div>
            )}
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
            form="organization-form"
            loading={processing}
          >
            {processing ? t('admin.common.saving') : t('admin.common.save_changes')}
          </Button>
        </CardFooter>
      </Card>
    </AuthenticatedLayout>
  )
}
