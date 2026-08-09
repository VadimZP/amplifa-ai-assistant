import { useForm } from '@inertiajs/react'
import { FormEvent, useState } from 'react'
import SimpleGuestLayout from '../../layouts/SimpleGuestLayout'
import { PasswordRequirements } from '../../components/ui/PasswordRequirements'
import { Input } from '../../components/ui/Input'
import { Button } from '../../components/ui/Button'
import { t } from '../../lib/i18n'

interface ResetPasswordProps {
  error?: string
  field_error?: string
  password_param?: string
  password_confirm_param?: string
}

export default function ResetPassword({
  error,
  field_error,
  password_param = 'password',
  password_confirm_param = 'password-confirm'
}: ResetPasswordProps) {
  const [password, setPassword] = useState('')

  const { data, setData, post, processing } = useForm({
    [password_param]: '',
    [password_confirm_param]: ''
  })

  const handleSubmit = (e: FormEvent) => {
    e.preventDefault()
    post('/reset-password')
  }

  return (
    <SimpleGuestLayout
      title={t('auth.reset_password.page_title')}
      heading={t('auth.reset_password.heading')}
      subheading={t('auth.reset_password.subheading')}
      error={error}
    >
      <form onSubmit={handleSubmit} className="flex flex-col gap-7">
        {/* New Password Field with Requirements */}
        <div className="flex flex-col gap-3">
          <Input
            id={password_param}
            name={password_param}
            type="password"
            label={t('auth.reset_password.new_password')}
            value={data[password_param]}
            onChange={(e) => {
              setData(password_param, e.target.value)
              setPassword(e.target.value)
            }}
            placeholder={t('auth.reset_password.new_password_placeholder')}
            error={field_error ? [field_error] : undefined}
            autoComplete="new-password"
            required
          />

          {/* Password Requirements Checklist - positioned per Figma: below input, 12px gap */}
          <PasswordRequirements password={password} />
        </div>

        {/* Confirm Password Field */}
        <Input
          id={password_confirm_param}
          name={password_confirm_param}
          type="password"
          label={t('auth.reset_password.confirm_password')}
          value={data[password_confirm_param]}
          onChange={(e) => setData(password_confirm_param, e.target.value)}
          placeholder={t('auth.reset_password.confirm_password_placeholder')}
          autoComplete="new-password"
          required
        />

        {/* Submit Button */}
        <Button
          type="submit"
          variant="primary"
          size="md"
          fullWidth
          loading={processing}
        >
          {t('auth.reset_password.submit')}
        </Button>
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
            {t('auth.reset_password.changed_mind')}
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
