import { useForm } from '@inertiajs/react'
import { FormEvent, useEffect, useMemo, useState } from 'react'
import { ArrowRight, MailCheck, ShieldCheck } from 'lucide-react'
import AuthSplitLayout from '../../layouts/AuthSplitLayout'
import { t } from '../../lib/i18n'

interface TwoFactorEmailProps {
  notice?: string
  error?: string
  email: string
  resend_available_at: string
}

export default function TwoFactorEmail({ notice, error, email, resend_available_at }: TwoFactorEmailProps) {
  const { post, processing } = useForm({})
  const resendAt = useMemo(() => new Date(resend_available_at).getTime(), [resend_available_at])
  const [secondsRemaining, setSecondsRemaining] = useState(() => secondsUntil(resendAt))

  useEffect(() => {
    const interval = window.setInterval(() => {
      setSecondsRemaining(secondsUntil(resendAt))
    }, 1000)

    return () => window.clearInterval(interval)
  }, [resendAt])

  const resendAvailable = secondsRemaining <= 0

  const handleResend = (event: FormEvent) => {
    event.preventDefault()
    if (!resendAvailable) return

    post('/two-factor-email/resend')
  }

  return (
    <AuthSplitLayout title={t('auth.two_factor_email.page_title')} notice={notice} error={error}>
      <div className="text-center lg:text-left mb-8">
        <div className="inline-flex h-14 w-14 items-center justify-center rounded-2xl bg-[var(--primary)]/10 text-[var(--primary)] mb-5">
          <ShieldCheck className="h-7 w-7" />
        </div>
        <h2 className="text-2xl font-bold text-[var(--foreground)] mb-2">
          {t('auth.two_factor_email.heading')}
        </h2>
        <p className="text-[var(--foreground-muted)] text-sm leading-6">
          {t('auth.two_factor_email.subtitle')}
        </p>
      </div>

      <div className="rounded-xl border border-[var(--border)] bg-[var(--card)] p-5 mb-6">
        <div className="flex items-start gap-3">
          <MailCheck className="h-5 w-5 text-[var(--primary)] shrink-0 mt-0.5" />
          <div>
            <p className="text-sm font-medium text-[var(--foreground)]">
              {t('auth.two_factor_email.sent_to')}
            </p>
            <p className="mt-1 text-sm text-[var(--foreground-muted)] break-all">{email}</p>
          </div>
        </div>
      </div>

      <p className="text-sm text-[var(--foreground-muted)] leading-6 mb-6">
        {t('auth.two_factor_email.instructions')}
      </p>

      <form onSubmit={handleResend}>
        <button
          type="submit"
          disabled={!resendAvailable || processing}
          className="inline-flex items-center justify-center gap-2 whitespace-nowrap rounded-md text-sm px-4 py-2 w-full h-11 bg-[var(--primary)] hover:bg-[var(--primary-hover)] text-[var(--primary-foreground)] font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--ring)] focus-visible:ring-offset-2 focus-visible:ring-offset-[var(--background)] disabled:pointer-events-none disabled:opacity-50 relative overflow-hidden group"
        >
          {resendAvailable
            ? t('auth.two_factor_email.resend')
            : t('auth.two_factor_email.resend_countdown', { count: secondsRemaining })}
          {resendAvailable && !processing && (
            <ArrowRight className="h-5 w-5 ml-2 group-hover:translate-x-1 transition-transform" />
          )}
        </button>
      </form>
    </AuthSplitLayout>
  )
}

function secondsUntil(timestamp: number) {
  return Math.max(0, Math.ceil((timestamp - Date.now()) / 1000))
}
