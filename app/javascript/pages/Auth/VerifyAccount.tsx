import { useForm } from '@inertiajs/react'
import { FormEvent } from 'react'
import SimpleGuestLayout from '../../layouts/SimpleGuestLayout'
import { Input } from '../../components/ui/Input'
import { Button } from '../../components/ui/Button'
import { CheckCircle2, Info } from 'lucide-react'
import { t } from '../../lib/i18n'

interface VerifyAccountProps {
  error?: string
  field_error?: string
  login_param?: string
}

export default function VerifyAccount({
  error,
  field_error,
  login_param = 'email'
}: VerifyAccountProps) {
  const { data, setData, post, processing } = useForm({
    [login_param]: ''
  })

  const handleResend = (e: FormEvent) => {
    e.preventDefault()
    post('/verify-account-resend')
  }

  return (
    <SimpleGuestLayout
      title={t('auth.verify_account.page_title')}
      heading={t('auth.verify_account.heading')}
      subheading={t('auth.verify_account.subheading')}
      error={error}
    >
      <div className="flex flex-col gap-7">
        {/* Success message box */}
        <div
          className="rounded-lg p-4 bg-[var(--success-muted)] border border-[var(--success)]"
        >
          <div className="flex items-start gap-3">
            <CheckCircle2 className="h-5 w-5 text-[var(--success)] flex-shrink-0 mt-0.5" />
            <div>
              <p className="text-sm font-medium text-[var(--success)]">
                {t('auth.verify_account.email_sent')}
              </p>
              <p className="text-sm mt-1 text-[var(--foreground-muted)]">
                {t('auth.verify_account.check_inbox')}
              </p>
            </div>
          </div>
        </div>

        {/* Info box */}
        <div
          className="rounded-lg p-4 bg-[var(--secondary)] border border-[var(--border)]"
        >
          <div className="flex items-start gap-3">
            <Info className="h-5 w-5 text-[var(--foreground-muted)] flex-shrink-0 mt-0.5" />
            <p className="text-sm text-[var(--foreground-muted)]">
              {t('auth.verify_account.didnt_receive')}
            </p>
          </div>
        </div>

        {/* Divider with text */}
        <div className="relative">
          <div
            className="absolute inset-0 flex items-center"
            aria-hidden="true"
          >
            <div className="w-full border-t border-[var(--border)]" />
          </div>
          <div className="relative flex justify-center text-sm">
            <span className="px-4 bg-[var(--card)] text-[var(--foreground-muted)]">
              {t('auth.verify_account.need_resend')}
            </span>
          </div>
        </div>

        {/* Resend form */}
        <form onSubmit={handleResend} className="flex flex-col gap-7">
          <Input
            id={login_param}
            name={login_param}
            type="email"
            label={t('auth.verify_account.email')}
            autoComplete="email"
            required
            value={data[login_param]}
            onChange={(e) => setData(login_param, e.target.value)}
            placeholder={t('auth.verify_account.email_placeholder')}
            error={field_error ? [field_error] : undefined}
          />

          <Button
            type="submit"
            variant="primary"
            size="md"
            fullWidth
            loading={processing}
          >
            {t('auth.verify_account.resend')}
          </Button>
        </form>
      </div>

      {/* Divider with text */}
      <div className="mt-7 relative">
        <div
          className="absolute inset-0 flex items-center"
          aria-hidden="true"
        >
          <div className="w-full border-t border-[var(--border)]" />
        </div>
        <div className="relative flex justify-center text-sm">
          <span className="px-4 bg-[var(--card)] text-[var(--foreground-muted)]">
            {t('auth.verify_account.already_verified')}
          </span>
        </div>
      </div>

      {/* Back to sign in link styled as secondary button */}
      <div className="mt-6">
        <a
          href="/login"
          className="inline-flex items-center justify-center w-full h-9 px-4 text-sm font-medium rounded-lg border border-[var(--border-strong)] bg-transparent text-[var(--foreground)] hover:bg-[rgba(255,255,255,0.05)] focus:outline-none focus-visible:shadow-[0_0_0_2px_var(--ring-offset),0_0_0_4px_var(--ring)] transition-all duration-150 active:scale-[0.98]"
        >
          {t('auth.reset_password.back_to_sign_in')}
        </a>
      </div>
    </SimpleGuestLayout>
  )
}
