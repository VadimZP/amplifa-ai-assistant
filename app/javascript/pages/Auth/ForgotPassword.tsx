import { useForm } from '@inertiajs/react'
import { FormEvent } from 'react'
import SimpleGuestLayout from '../../layouts/SimpleGuestLayout'
import { Input } from '../../components/ui/Input'
import { Button } from '../../components/ui/Button'
import { Mail } from 'lucide-react'
import { t } from '../../lib/i18n'

interface ForgotPasswordProps {
  notice?: string
  error?: string
  field_error?: string
  login_param?: string
}

export default function ForgotPassword({
  notice,
  error,
  field_error,
  login_param = 'email'
}: ForgotPasswordProps) {
  const { data, setData, post, processing } = useForm({
    [login_param]: ''
  })

  const handleSubmit = (e: FormEvent) => {
    e.preventDefault()
    post('/reset-password-request')
  }

  return (
    <SimpleGuestLayout
      title={t('auth.forgot_password.page_title')}
      heading={t('auth.forgot_password.heading')}
      subheading={t('auth.forgot_password.subheading')}
      notice={notice}
      error={error}
    >
      <form onSubmit={handleSubmit} className="flex flex-col gap-7">
        {/* Email field */}
        <Input
          id={login_param}
          name={login_param}
          type="email"
          label={t('auth.forgot_password.email')}
          autoComplete="email"
          required
          value={data[login_param]}
          onChange={(e) => setData(login_param, e.target.value)}
          placeholder={t('auth.forgot_password.email_placeholder')}
          error={field_error ? [field_error] : undefined}
        />

        {/* Submit button */}
        <Button
          type="submit"
          variant="primary"
          size="md"
          fullWidth
          loading={processing}
        >
          {t('auth.forgot_password.submit')}
        </Button>

        {/* Info box */}
        <div
          className="rounded-lg p-4 bg-[var(--secondary)] border border-[var(--border)]"
        >
          <div className="flex items-start gap-3">
            <Mail className="h-5 w-5 text-[var(--foreground-muted)] flex-shrink-0 mt-0.5" />
            <p className="text-sm text-[var(--foreground-muted)]">
              {t('auth.forgot_password.info')}
            </p>
          </div>
        </div>
      </form>

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
            {t('auth.forgot_password.remember_password')}
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
