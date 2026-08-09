import { useState } from 'react'
import { Head } from '@inertiajs/react'
import { Eye, EyeOff, CheckCircle, Info, Mail, Building2, User, ShieldCheck } from 'lucide-react'
import SimpleGuestLayout from '../../../layouts/SimpleGuestLayout'
import { Button } from '../../../components/ui/Button'
import { PasswordRequirements } from '../../../components/ui/PasswordRequirements'
import i18n, { t } from '../../../lib/i18n'

interface TimezoneOption {
  value: string
  label: string
}

interface Invitation {
  token: string
  email: string
  first_name: string
  last_name: string
  role: string
  organization: {
    id: number
    name: string
    locale: string
  }
}

interface AcceptProps {
  invitation: Invitation
  locale_options: string[]
  timezones: TimezoneOption[]
  error?: string
}

function getPasswordStrength(password: string): { strength: number; text: string; colorClass: string } {
  if (password.length === 0) return { strength: 0, text: '', colorClass: '' }

  let strength = 0
  if (password.length >= 8) strength++
  if (/[0-9]/.test(password)) strength++
  if (/[^A-Za-z0-9]/.test(password)) strength++
  if (password.length >= 12) strength++

  const strengthMap = {
    1: { text: t('invitation.accept.password_strength.weak'), colorClass: 'bg-[var(--error)]' },
    2: { text: t('invitation.accept.password_strength.fair'), colorClass: 'bg-[var(--warning)]' },
    3: { text: t('invitation.accept.password_strength.good'), colorClass: 'bg-[var(--accent)]' },
    4: { text: t('invitation.accept.password_strength.strong'), colorClass: 'bg-[var(--success)]' }
  }

  return { strength, ...strengthMap[Math.min(strength, 4) as keyof typeof strengthMap] }
}

export default function Accept({ invitation, locale_options, timezones, error }: AcceptProps) {
  const [formData, setFormData] = useState({
    password: '',
    password_confirmation: '',
    locale: invitation.organization.locale || 'en',
    timezone: ''
  })

  const [showPassword, setShowPassword] = useState(false)
  const [showPasswordConfirmation, setShowPasswordConfirmation] = useState(false)
  const [processing, setProcessing] = useState(false)
  const [formErrors, setFormErrors] = useState<Record<string, string>>({})
  // WHY: Track locale in state to trigger re-renders when language changes on the fly.
  // Updating i18n.locale alone won't cause React to re-render.
  const [currentLocale, setCurrentLocale] = useState(invitation.organization.locale || 'en')

  const localeFlags: Record<string, string> = {
    en: '🇬🇧',
    de: '🇩🇪',
    es: '🇪🇸',
    'pt-BR': '🇧🇷',
    fr: '🇫🇷',
    pl: '🇵🇱',
    cs: '🇨🇿',
    it: '🇮🇹'
  }

  const passwordStrength = getPasswordStrength(formData.password)
  const passwordsMatch = formData.password && formData.password_confirmation &&
                        formData.password === formData.password_confirmation

  const showRole = invitation.role === 'customer_admin'

  const handleChange = (field: string, value: string) => {
    setFormData(prev => ({ ...prev, [field]: value }))
    if (formErrors[field]) {
      setFormErrors(prev => {
        const newErrors = { ...prev }
        delete newErrors[field]
        return newErrors
      })
    }
  }

  // WHY: Separate handler for locale changes to also update i18n.locale for on-the-fly translation
  const handleLocaleChange = (newLocale: string) => {
    i18n.locale = newLocale
    setCurrentLocale(newLocale)
    setFormData(prev => ({ ...prev, locale: newLocale }))
  }

  const validateForm = (): boolean => {
    const errors: Record<string, string> = {}

    if (!formData.password) {
      errors.password = t('invitation.accept.errors.password_required')
    } else if (formData.password.length < 8) {
      errors.password = t('invitation.accept.errors.password_too_short')
    }

    if (!formData.password_confirmation) {
      errors.password_confirmation = t('invitation.accept.errors.confirmation_required')
    } else if (formData.password !== formData.password_confirmation) {
      errors.password_confirmation = t('invitation.accept.errors.passwords_mismatch')
    }

    setFormErrors(errors)
    return Object.keys(errors).length === 0
  }

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()

    if (!validateForm()) {
      return
    }

    setProcessing(true)

    const csrfToken = document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content || ''

    const form = document.createElement('form')
    form.method = 'POST'
    form.action = `/invitations/${invitation.token}/accept`

    const csrfInput = document.createElement('input')
    csrfInput.type = 'hidden'
    csrfInput.name = 'authenticity_token'
    csrfInput.value = csrfToken
    form.appendChild(csrfInput)

    Object.entries(formData).forEach(([key, value]) => {
      if (value) {
        const input = document.createElement('input')
        input.type = 'hidden'
        input.name = key
        input.value = value
        form.appendChild(input)
      }
    })

    document.body.appendChild(form)
    form.submit()
  }

  return (
    <>
      <Head title={`${t('invitation.accept.title')} - Amplifa`} />
      <SimpleGuestLayout
        title={t('invitation.accept.title')}
        heading={t('invitation.accept.title')}
        subheading={t('invitation.accept.subtitle', { organization: invitation.organization.name })}
        error={error}
      >
        <form onSubmit={handleSubmit} className="flex flex-col gap-6">
          {/* Account Information Section - Read-only display */}
          <div
            className="p-4 rounded-lg"
            style={{
              backgroundColor: 'var(--secondary)',
              border: '1px solid var(--border)'
            }}
          >
            <h3 className="text-sm font-semibold text-[var(--foreground)] mb-3 flex items-center gap-2">
              <Info size={16} className="text-[var(--foreground-muted)]" />
              {t('invitation.accept.account_info_title')}
            </h3>
            <dl className="space-y-2 text-sm">
              <div className="flex justify-between items-center">
                <dt className="text-[var(--foreground-muted)] flex items-center gap-2">
                  <Building2 size={14} />
                  {t('invitation.accept.organization_label')}:
                </dt>
                <dd className="font-medium text-[var(--foreground)]">{invitation.organization.name}</dd>
              </div>
              <div className="flex justify-between items-center">
                <dt className="text-[var(--foreground-muted)] flex items-center gap-2">
                  <Mail size={14} />
                  {t('invitation.accept.email_label')}:
                </dt>
                <dd className="font-medium text-[var(--foreground)]">{invitation.email}</dd>
              </div>
              <div className="flex justify-between items-center">
                <dt className="text-[var(--foreground-muted)] flex items-center gap-2">
                  <User size={14} />
                  {t('invitation.accept.name_label')}:
                </dt>
                <dd className="font-medium text-[var(--foreground)]">{invitation.first_name} {invitation.last_name}</dd>
              </div>
              {/* WHY: Only show role for customer_admin (as "Admin"). Hide for customer_user per AMP-127. */}
              {showRole && (
                <div className="flex justify-between items-center">
                  <dt className="text-[var(--foreground-muted)] flex items-center gap-2">
                    <ShieldCheck size={14} />
                    {t('invitation.accept.role_label')}:
                  </dt>
                  <dd className="font-medium text-[var(--foreground)]">{t('invitation.accept.role_admin')}</dd>
                </div>
              )}
            </dl>
          </div>

          {/* Setup Your Account Section */}
          <div className="flex flex-col gap-5">
            <h3 className="text-base font-semibold text-[var(--foreground)]">{t('invitation.accept.setup_title')}</h3>

            {/* Password Field */}
            <div className="flex flex-col gap-3">
              <div className="flex flex-col gap-1.5">
                <label htmlFor="password" className="text-sm font-medium text-[var(--foreground)]">
                  {t('invitation.accept.password_label')}
                </label>
                <div className="relative">
                  <input
                    id="password"
                    name="password"
                    type={showPassword ? 'text' : 'password'}
                    autoComplete="new-password"
                    required
                    value={formData.password}
                    onChange={(e) => handleChange('password', e.target.value)}
                    className={`w-full h-9 px-3 pr-10 rounded-lg border bg-[var(--input)] text-[var(--foreground)] placeholder:text-[var(--foreground-muted)] transition-all duration-150 ${
                      formErrors.password ? 'border-[var(--error)]' : 'border-[var(--input-border)]'
                    }`}
                    placeholder={t('invitation.accept.password_placeholder')}
                  />
                  <button
                    type="button"
                    onClick={() => setShowPassword(!showPassword)}
                    className="absolute inset-y-0 right-0 pr-3 flex items-center text-[var(--foreground-muted)] hover:text-[var(--foreground)] transition-colors"
                    aria-label={showPassword ? t('invitation.accept.hide_password') : t('invitation.accept.show_password')}
                  >
                    {showPassword ? <EyeOff size={18} /> : <Eye size={18} />}
                  </button>
                </div>
                {formErrors.password && (
                  <p className="text-xs text-[var(--error)]">{formErrors.password}</p>
                )}
              </div>

              {/* Password Strength Indicator */}
              {formData.password && (
                <div className="flex flex-col gap-1.5">
                  <div className="flex items-center justify-between">
                    <span className="text-xs font-medium text-[var(--foreground-muted)]">{t('invitation.accept.password_strength_label')}</span>
                    <span className="text-xs font-semibold text-[var(--foreground)]">
                      {passwordStrength.text}
                    </span>
                  </div>
                  <div className="w-full bg-[var(--secondary)] rounded-full h-1.5">
                    <div
                      className={`h-1.5 rounded-full transition-all duration-300 ${passwordStrength.colorClass}`}
                      style={{ width: `${(passwordStrength.strength / 4) * 100}%` }}
                    />
                  </div>
                </div>
              )}

              {/* Password Requirements */}
              <PasswordRequirements password={formData.password} locale={currentLocale} />
            </div>

            {/* Confirm Password Field */}
            <div className="flex flex-col gap-1.5">
              <label htmlFor="password_confirmation" className="text-sm font-medium text-[var(--foreground)]">
                {t('invitation.accept.confirm_password_label')}
              </label>
              <div className="relative">
                <input
                  id="password_confirmation"
                  name="password_confirmation"
                  type={showPasswordConfirmation ? 'text' : 'password'}
                  autoComplete="new-password"
                  required
                  value={formData.password_confirmation}
                  onChange={(e) => handleChange('password_confirmation', e.target.value)}
                  className={`w-full h-9 px-3 pr-16 rounded-lg border bg-[var(--input)] text-[var(--foreground)] placeholder:text-[var(--foreground-muted)] transition-all duration-150 ${
                    formErrors.password_confirmation ? 'border-[var(--error)]' : 'border-[var(--input-border)]'
                  }`}
                  placeholder={t('invitation.accept.confirm_password_placeholder')}
                />
                <div className="absolute inset-y-0 right-0 flex items-center gap-1 pr-3">
                  {passwordsMatch && (
                    <CheckCircle size={18} className="text-[var(--success)]" />
                  )}
                  <button
                    type="button"
                    onClick={() => setShowPasswordConfirmation(!showPasswordConfirmation)}
                    className="text-[var(--foreground-muted)] hover:text-[var(--foreground)] transition-colors"
                    aria-label={showPasswordConfirmation ? t('invitation.accept.hide_password') : t('invitation.accept.show_password')}
                  >
                    {showPasswordConfirmation ? <EyeOff size={18} /> : <Eye size={18} />}
                  </button>
                </div>
              </div>
              {formErrors.password_confirmation && (
                <p className="text-xs text-[var(--error)]">{formErrors.password_confirmation}</p>
              )}
            </div>

            {/* Language Preference */}
            <div className="flex flex-col gap-1.5">
              <label htmlFor="locale" className="text-sm font-medium text-[var(--foreground)]">
                {t('invitation.accept.language_label')}
              </label>
              <select
                id="locale"
                name="locale"
                value={formData.locale}
                onChange={(e) => handleLocaleChange(e.target.value)}
                className="w-full h-9 px-3 rounded-lg border border-[var(--input-border)] bg-[var(--input)] text-[var(--foreground)] transition-all duration-150 focus:outline-none focus:border-[var(--ring)] focus:ring-2 focus:ring-[var(--ring)]/20"
              >
                {locale_options.map((locale) => (
                  <option key={locale} value={locale}>
                    {(localeFlags[locale] || '🌐')} {t(`languages.${locale}`)}
                  </option>
                ))}
              </select>
            </div>

            {/* Timezone (Optional) */}
            <div className="flex flex-col gap-1.5">
              <label htmlFor="timezone" className="text-sm font-medium text-[var(--foreground)]">
                {t('invitation.accept.timezone_label')}
              </label>
              <select
                id="timezone"
                name="timezone"
                value={formData.timezone}
                onChange={(e) => handleChange('timezone', e.target.value)}
                className="w-full h-9 px-3 rounded-lg border border-[var(--input-border)] bg-[var(--input)] text-[var(--foreground)] transition-all duration-150 focus:outline-none focus:border-[var(--ring)] focus:ring-2 focus:ring-[var(--ring)]/20"
              >
                <option value="">{t('invitation.accept.timezone_placeholder')}</option>
                {timezones.map((tz) => (
                  <option key={tz.value} value={tz.value}>
                    {tz.label}
                  </option>
                ))}
              </select>
              <p className="text-xs text-[var(--foreground-muted)]">
                {t('invitation.accept.timezone_help')}
              </p>
            </div>
          </div>

          {/* Submit Button */}
          <Button
            type="submit"
            variant="primary"
            size="md"
            fullWidth
            loading={processing}
          >
            {t('invitation.accept.submit')}
          </Button>
        </form>
      </SimpleGuestLayout>
    </>
  )
}
