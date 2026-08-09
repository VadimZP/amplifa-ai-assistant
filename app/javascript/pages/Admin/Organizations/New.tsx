/**
 * Admin Organizations New Page
 * Form to create a new organization
 *
 * Design: Dark theme with Card wrapper, Input/Button components
 * Migration: Task 5.3.4 (Phase 5)
 */
import { router, useForm } from '@inertiajs/react'
import AuthenticatedLayout from '../../../layouts/AuthenticatedLayout'
import { t } from '../../../lib/i18n'
import { Card, CardContent, CardFooter } from '../../../components/ui/Card'
import { Input } from '../../../components/ui/Input'
import { Button } from '../../../components/ui/Button'

interface AdminOrganizationNewProps {
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
  size_options: string[]
  locale_options: string[]
  currency_options: string[]
  plan_options: {
    identifier: string
    name: string
    monthly_meeting_limit: number
    monthly_price: number
  }[]
  organization?: {
    name?: string
    industry?: string
    size?: string
    onboarded?: boolean
    website?: string
    average_contract_value?: number | string
    meeting_price?: number | string
    monthly_subscription?: number | string
    monthly_meeting_limit?: number | string
    plan_tier?: string
    two_factor_authentication_required?: boolean
    calendly_url?: string
    locale?: string
    currency?: string
  }
  errors?: {
    name?: string[]
    industry?: string[]
    size?: string[]
    onboarded?: string[]
    website?: string[]
    average_contract_value?: string[]
    meeting_price?: string[]
    monthly_subscription?: string[]
    monthly_meeting_limit?: string[]
    plan_tier?: string[]
    two_factor_authentication_required?: string[]
    calendly_url?: string[]
    locale?: string[]
    currency?: string[]
  }
  flash?: {
    notice?: string
    alert?: string
  }
}

export default function New({ auth, size_options, locale_options, currency_options, plan_options, organization, errors: serverErrors, flash }: AdminOrganizationNewProps) {
  const account = auth.account

  // WHY: Initialize form with empty values or pre-filled values if validation failed
  const { data, setData, post, processing, errors } = useForm({
    name: organization?.name || '',
    industry: organization?.industry || '',
    size: organization?.size || '',
    onboarded: organization?.onboarded || false,
    website: organization?.website || '',
    average_contract_value: organization?.average_contract_value || '',
    meeting_price: organization?.meeting_price || '',
    monthly_subscription: organization?.monthly_subscription || '',
    monthly_meeting_limit: organization?.monthly_meeting_limit || 5,
    plan_tier: organization?.plan_tier || 'basic',
    two_factor_authentication_required: organization?.two_factor_authentication_required || false,
    calendly_url: organization?.calendly_url || '',
    locale: organization?.locale || 'en',
    currency: organization?.currency || 'EUR'
  })

  // WHY: Merge server-side validation errors with client-side errors
  const allErrors = { ...errors, ...serverErrors }

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    // WHY: Post to admin organizations path to create new organization
    post('/admin/organizations')
  }

  const handleCancel = () => {
    router.visit('/admin/organizations')
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

  const getErrorMessage = (field: keyof typeof allErrors) => {
    const error = allErrors[field]
    if (!error) return undefined
    return Array.isArray(error) ? error[0] : error
  }

  return (
    <AuthenticatedLayout
      title={t('admin.organizations.new.title')}
      subtitle={t('admin.organizations.new.subtitle')}
      account={account}
      flash={flash}
    >
      {/* Form Card */}
      <Card className="max-w-2xl">
        <CardContent>
          <form id="organization-form" onSubmit={handleSubmit} className="space-y-6">
            {/* Name */}
            <Input
              label={t('admin.organizations.new.name_label')}
              description={t('admin.organizations.new.name_description')}
              type="text"
              value={data.name}
              onChange={e => setData('name', e.target.value)}
              placeholder={t('admin.organizations.new.name_placeholder')}
              error={getErrorMessage('name')}
              required
            />

            {/* Industry */}
            <Input
              label={t('admin.organizations.new.industry_label')}
              description={t('admin.organizations.new.industry_description')}
              type="text"
              value={data.industry}
              onChange={e => setData('industry', e.target.value)}
              placeholder={t('admin.organizations.new.industry_placeholder')}
              error={getErrorMessage('industry')}
            />

            {/* Size */}
            <div className="flex flex-col gap-3">
              <label htmlFor="size" className="text-sm font-medium text-[var(--foreground)] leading-5">
                {t('admin.organizations.new.size_label')}
              </label>
              <p className="text-xs text-[var(--foreground-muted)] -mt-1">{t('admin.organizations.new.size_description')}</p>
              <select
                id="size"
                value={data.size}
                onChange={e => setData('size', e.target.value)}
                className={selectBaseClasses}
              >
                <option value="">{t('admin.organizations.new.size_placeholder')}</option>
                {size_options.map(size => (
                  <option key={size} value={size}>
                    {size}{t('admin.organizations.new.size_suffix')}
                  </option>
                ))}
              </select>
              {allErrors.size && (
                <p className="text-xs text-[var(--error)] -mt-1">{getErrorMessage('size')}</p>
              )}
            </div>

            {/* Website & Integration Section */}
            <div className="pt-6 border-t border-[var(--border)]">
              <h3 className="text-base font-semibold text-[var(--foreground)] mb-4">
                {t('admin.organizations.new.website_integration_section')}
              </h3>

              {/* Website */}
              <Input
                label={t('admin.organizations.new.website_label')}
                description={t('admin.organizations.new.website_description')}
                type="url"
                value={data.website}
                onChange={e => setData('website', e.target.value)}
                placeholder={t('admin.organizations.new.website_placeholder')}
                error={getErrorMessage('website')}
              />

              {/* Calendly URL */}
              <div className="mt-6">
                <Input
                  label={t('admin.organizations.new.calendly_url_label')}
                  description={t('admin.organizations.new.calendly_url_description')}
                  type="url"
                  value={data.calendly_url}
                  onChange={e => setData('calendly_url', e.target.value)}
                  placeholder={t('admin.organizations.new.calendly_url_placeholder')}
                  error={getErrorMessage('calendly_url')}
                />
              </div>
            </div>

            {/* Financial Information Section */}
            <div className="pt-6 border-t border-[var(--border)]">
              <h3 className="text-base font-semibold text-[var(--foreground)] mb-4">
                {t('admin.organizations.new.financial_section')}
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
                {allErrors.plan_tier && (
                  <p className="text-xs text-[var(--error)] -mt-1">{getErrorMessage('plan_tier')}</p>
                )}
                <p className="text-xs text-[var(--foreground-muted)] -mt-1">
                  Selecting a plan autofills max meetings and monthly price. You can customize both fields below.
                </p>
              </div>

              {/* Average Contract Value */}
              <Input
                label={t('admin.organizations.new.average_contract_value_label')}
                description={t('admin.organizations.new.average_contract_value_description')}
                type="number"
                value={String(data.average_contract_value)}
                onChange={e => setData('average_contract_value', e.target.value)}
                placeholder={t('admin.organizations.new.average_contract_value_placeholder')}
                error={getErrorMessage('average_contract_value')}
                step="0.01"
                min="0"
              />

              {/* Meeting Price */}
              <div className="mt-6">
                <Input
                  label={t('admin.organizations.new.meeting_price_label')}
                  description={t('admin.organizations.new.meeting_price_description')}
                  type="number"
                  value={String(data.meeting_price)}
                  onChange={e => setData('meeting_price', e.target.value)}
                  placeholder={t('admin.organizations.new.meeting_price_placeholder')}
                  error={getErrorMessage('meeting_price')}
                  step="0.01"
                  min="0"
                />
              </div>

              {/* Monthly Subscription */}
              <div className="mt-6">
                <Input
                  label={t('admin.organizations.new.monthly_subscription_label')}
                  description={t('admin.organizations.new.monthly_subscription_description')}
                  type="number"
                  value={String(data.monthly_subscription)}
                  onChange={e => setData('monthly_subscription', e.target.value)}
                  placeholder={t('admin.organizations.new.monthly_subscription_placeholder')}
                  error={getErrorMessage('monthly_subscription')}
                  step="0.01"
                  min="0"
                />
              </div>

              <div className="mt-6">
                <Input
                  label={t('admin.organizations.new.monthly_meeting_limit_label')}
                  description={t('admin.organizations.new.monthly_meeting_limit_description')}
                  type="number"
                  value={String(data.monthly_meeting_limit)}
                  onChange={e => setData('monthly_meeting_limit', Number(e.target.value))}
                  error={getErrorMessage('monthly_meeting_limit')}
                  step="1"
                  min="1"
                  required
                />
              </div>
            </div>

            {/* Localization Section */}
            <div className="pt-6 border-t border-[var(--border)]">
              <h3 className="text-base font-semibold text-[var(--foreground)] mb-4">
                {t('admin.organizations.new.localization_section')}
              </h3>

              {/* Locale */}
              <div className="flex flex-col gap-3">
                <label htmlFor="locale" className="text-sm font-medium text-[var(--foreground)] leading-5">
                  {t('admin.organizations.new.locale_label')}
                </label>
                <p className="text-xs text-[var(--foreground-muted)] -mt-1">{t('admin.organizations.new.locale_description')}</p>
                <select
                  id="locale"
                  value={data.locale}
                  onChange={e => setData('locale', e.target.value)}
                  className={selectBaseClasses}
                >
                  {locale_options.map(locale => (
                    <option key={locale} value={locale}>
                      {t(`languages.${locale}`)}
                    </option>
                  ))}
                </select>
                {allErrors.locale && (
                  <p className="text-xs text-[var(--error)] -mt-1">{getErrorMessage('locale')}</p>
                )}
              </div>

              {/* Currency */}
              <div className="flex flex-col gap-3 mt-6">
                <label htmlFor="currency" className="text-sm font-medium text-[var(--foreground)] leading-5">
                  {t('admin.organizations.new.currency_label')}
                </label>
                <p className="text-xs text-[var(--foreground-muted)] -mt-1">{t('admin.organizations.new.currency_description')}</p>
                <select
                  id="currency"
                  value={data.currency}
                  onChange={e => setData('currency', e.target.value)}
                  className={selectBaseClasses}
                >
                  {currency_options.map(currency => (
                    <option key={currency} value={currency}>
                      {currency}
                    </option>
                  ))}
                </select>
                {allErrors.currency && (
                  <p className="text-xs text-[var(--error)] -mt-1">{getErrorMessage('currency')}</p>
                )}
              </div>
            </div>

            {/* Security Section */}
            <div className="pt-6 border-t border-[var(--border)]">
              <h3 className="text-base font-semibold text-[var(--foreground)] mb-4">
                {t('admin.organizations.new.security_section')}
              </h3>
              <div className="relative flex items-start">
                <div className="flex h-6 items-center">
                  <input
                    id="two_factor_authentication_required"
                    type="checkbox"
                    checked={data.two_factor_authentication_required}
                    onChange={e => setData('two_factor_authentication_required', e.target.checked)}
                    className="h-5 w-5 rounded bg-[var(--input)] border-[var(--input-border)] text-[var(--accent)] focus:ring-[var(--ring)] transition-colors cursor-pointer"
                  />
                </div>
                <div className="ml-3 text-sm leading-6">
                  <label htmlFor="two_factor_authentication_required" className="font-medium text-[var(--foreground)] cursor-pointer">
                    {t('admin.organizations.new.two_factor_authentication_required_label')}
                  </label>
                  <p className="text-[var(--foreground-muted)]">
                    {t('admin.organizations.new.two_factor_authentication_required_description')}
                  </p>
                </div>
              </div>
              {allErrors.two_factor_authentication_required && (
                <p className="mt-2 text-xs text-[var(--error)]">{getErrorMessage('two_factor_authentication_required')}</p>
              )}
            </div>

            {/* Onboarded Status */}
            <div className="pt-6 border-t border-[var(--border)]">
              <div className="relative flex items-start">
                <div className="flex h-6 items-center">
                  <input
                    id="onboarded"
                    type="checkbox"
                    checked={data.onboarded}
                    onChange={e => setData('onboarded', e.target.checked)}
                    className="h-5 w-5 rounded bg-[var(--input)] border-[var(--input-border)] text-[var(--accent)] focus:ring-[var(--ring)] transition-colors cursor-pointer"
                  />
                </div>
                <div className="ml-3 text-sm leading-6">
                  <label htmlFor="onboarded" className="font-medium text-[var(--foreground)] cursor-pointer">
                    {t('admin.organizations.new.onboarded_label')}
                  </label>
                  <p className="text-[var(--foreground-muted)]">
                    {t('admin.organizations.new.onboarded_description')}
                  </p>
                </div>
              </div>
              {allErrors.onboarded && (
                <p className="mt-2 text-xs text-[var(--error)]">{getErrorMessage('onboarded')}</p>
              )}
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
            form="organization-form"
            loading={processing}
          >
            {processing ? t('admin.common.creating') : t('admin.organizations.new.submit')}
          </Button>
        </CardFooter>
      </Card>
    </AuthenticatedLayout>
  )
}
