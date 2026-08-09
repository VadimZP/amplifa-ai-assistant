import { useForm } from '@inertiajs/react'
import { FormEvent, useState } from 'react'
import SimpleGuestLayout from '../../layouts/SimpleGuestLayout'
import { Input } from '../../components/ui/Input'
import { Button } from '../../components/ui/Button'
import { PasswordRequirements } from '../../components/ui/PasswordRequirements'
import { t } from '../../lib/i18n'

interface RegisterProps {
  error?: string
  field_error?: string
  errors?: {
    first_name?: string[]
    last_name?: string[]
    email?: string[]
    organization_name?: string[]
    password?: string[]
  }
}

export default function Register({ error, field_error, errors }: RegisterProps) {
  const [password, setPassword] = useState('')

  const { data, setData, post, processing } = useForm({
    email: '',
    password: '',
    first_name: '',
    last_name: '',
    organization_name: ''
  })

  const handleSubmit = (e: FormEvent) => {
    e.preventDefault()
    post('/create-account')
  }

  return (
    <SimpleGuestLayout
      title={t('auth.register.page_title')}
      heading={t('auth.register.heading')}
      subheading={t('auth.register.subheading')}
      error={error}
    >
      <form onSubmit={handleSubmit} className="flex flex-col gap-7">
        {/* Name fields - 2 column grid */}
        <div className="grid grid-cols-2 gap-4">
          <Input
            id="first_name"
            name="first_name"
            type="text"
            label={t('auth.register.first_name')}
            required
            value={data.first_name}
            onChange={(e) => setData('first_name', e.target.value)}
            placeholder={t('auth.register.first_name_placeholder')}
            error={errors?.first_name}
            autoComplete="given-name"
          />

          <Input
            id="last_name"
            name="last_name"
            type="text"
            label={t('auth.register.last_name')}
            required
            value={data.last_name}
            onChange={(e) => setData('last_name', e.target.value)}
            placeholder={t('auth.register.last_name_placeholder')}
            error={errors?.last_name}
            autoComplete="family-name"
          />
        </div>

        {/* Email field */}
        <Input
          id="email"
          name="email"
          type="email"
          label={t('auth.register.email')}
          autoComplete="email"
          required
          value={data.email}
          onChange={(e) => setData('email', e.target.value)}
          placeholder={t('auth.register.email_placeholder')}
          error={field_error ? [field_error] : errors?.email}
        />

        {/* Organization field */}
        <Input
          id="organization_name"
          name="organization_name"
          type="text"
          label={t('auth.register.organization_name')}
          required
          value={data.organization_name}
          onChange={(e) => setData('organization_name', e.target.value)}
          placeholder={t('auth.register.organization_placeholder')}
          error={errors?.organization_name}
          autoComplete="organization"
        />

        {/* Password field with requirements */}
        <div className="flex flex-col gap-3">
          <Input
            id="password"
            name="password"
            type="password"
            label={t('auth.register.password')}
            autoComplete="new-password"
            required
            value={data.password}
            onChange={(e) => {
              setData('password', e.target.value)
              setPassword(e.target.value)
            }}
            placeholder={t('auth.register.password_placeholder')}
            error={errors?.password}
          />

          {/* Password Requirements Checklist */}
          <PasswordRequirements password={password} />
        </div>

        {/* Submit button */}
        <Button
          type="submit"
          variant="primary"
          size="md"
          fullWidth
          loading={processing}
        >
          {t('auth.register.submit')}
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
            {t('auth.register.already_have_account')}
          </span>
        </div>
      </div>

      {/* Sign in link styled as secondary button */}
      <div className="mt-6">
        <a
          href="/login"
          className="inline-flex items-center justify-center w-full h-9 px-4 text-sm font-medium rounded-lg border border-[var(--border-strong)] bg-transparent text-[var(--foreground)] hover:bg-[rgba(255,255,255,0.05)] focus:outline-none focus-visible:shadow-[0_0_0_2px_var(--ring-offset),0_0_0_4px_var(--ring)] transition-all duration-150 active:scale-[0.98]"
        >
          {t('auth.register.sign_in_instead')}
        </a>
      </div>
    </SimpleGuestLayout>
  )
}
