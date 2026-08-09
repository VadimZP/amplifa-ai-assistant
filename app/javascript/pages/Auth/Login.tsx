import { useState } from 'react'
import { Eye, EyeOff, ArrowRight } from 'lucide-react'
import AuthSplitLayout from '../../layouts/AuthSplitLayout'
import { t } from '../../lib/i18n'

interface LoginProps {
  notice?: string
  error?: string
  login_param?: string
  password_param?: string
  csrf_token?: string
}

export default function Login({
  notice,
  error,
  login_param = 'email',
  password_param = 'password',
  csrf_token
}: LoginProps) {
  const [processing, setProcessing] = useState(false)
  const [showPassword, setShowPassword] = useState(false)

  const handleSubmit = () => {
    setProcessing(true)
  }

  const authenticityToken =
    csrf_token ||
    document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') ||
    ''

  return (
    <AuthSplitLayout title={t('auth.login.page_title')} notice={notice} error={error}>
      <div className="text-center lg:text-left mb-6">
        <h2 className="text-2xl font-bold text-[var(--foreground)] mb-2">{t('dashboard.welcome_back')}</h2>
        <p className="text-[var(--foreground-muted)] text-sm">{t('auth.login.subtitle')}</p>
      </div>

      <form method="post" action="/login" onSubmit={handleSubmit} className="space-y-5">
        <input type="hidden" name="authenticity_token" value={authenticityToken} />

        <div className="space-y-2">
          <label
            htmlFor="email"
            className="text-sm font-medium leading-none text-[var(--foreground)]"
          >
            {t('auth.login.email_label')}
          </label>
          <input
            id="email"
            name={login_param}
            type="email"
            autoComplete="email"
            required
            placeholder={t('auth.login.email_placeholder')}
            className="flex w-full rounded-md border px-3 py-2 text-sm h-11 bg-[var(--card)] border-[var(--border)] text-[var(--foreground)] placeholder:text-[var(--foreground-muted)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--ring)] focus-visible:ring-offset-2 focus-visible:ring-offset-[var(--background)]"
          />
        </div>

        <div className="space-y-2">
          <label
            htmlFor="password"
            className="text-sm font-medium leading-none text-[var(--foreground)]"
          >
            {t('auth.login.password_label')}
          </label>
          <div className="relative">
            <input
              id="password"
              name={password_param}
              type={showPassword ? 'text' : 'password'}
              autoComplete="current-password"
              required
              placeholder={t('auth.login.password_placeholder')}
              className="flex w-full rounded-md border px-3 py-2 pr-12 text-sm h-11 bg-[var(--card)] border-[var(--border)] text-[var(--foreground)] placeholder:text-[var(--foreground-muted)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--ring)] focus-visible:ring-offset-2 focus-visible:ring-offset-[var(--background)]"
            />
            <button
              type="button"
              onClick={() => setShowPassword(!showPassword)}
              aria-label={showPassword ? t('invitation.accept.hide_password') : t('invitation.accept.show_password')}
              className="absolute right-4 top-1/2 -translate-y-1/2 text-[var(--foreground-muted)] hover:text-[var(--foreground)] transition-colors"
            >
              {showPassword ? (
                <EyeOff className="h-5 w-5" />
              ) : (
                <Eye className="h-5 w-5" />
              )}
            </button>
          </div>
        </div>

        <div className="flex items-center justify-between gap-4">
          <div className="flex items-center space-x-2">
            <input
              id="remember"
              name="remember"
              type="checkbox"
              className="h-4 w-4 shrink-0 rounded-sm border border-[var(--primary)] bg-[var(--background)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--ring)] focus-visible:ring-offset-2 focus-visible:ring-offset-[var(--background)]"
            />
            <label
              htmlFor="remember"
              className="text-sm text-[var(--foreground-muted)] cursor-pointer select-none"
            >
              {t('auth.login.remember_me')}
            </label>
          </div>

          <a
            href="/reset-password-request"
            className="text-sm font-medium text-[var(--accent)] hover:underline"
          >
            {t('auth.login.forgot_password')}
          </a>
        </div>

        <button
          type="submit"
          disabled={processing}
          className="inline-flex items-center justify-center gap-2 whitespace-nowrap rounded-md text-sm px-4 py-2 w-full h-11 bg-[var(--primary)] hover:bg-[var(--primary-hover)] text-[var(--primary-foreground)] font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--ring)] focus-visible:ring-offset-2 focus-visible:ring-offset-[var(--background)] disabled:pointer-events-none disabled:opacity-50 relative overflow-hidden group"
        >
          {processing ? t('auth.login.signing_in') : t('auth.login.submit')}
          {!processing && (
            <ArrowRight className="h-5 w-5 ml-2 group-hover:translate-x-1 transition-transform" />
          )}
        </button>
      </form>
    </AuthSplitLayout>
  )
}
