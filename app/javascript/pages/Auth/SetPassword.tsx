import { useForm } from '@inertiajs/react'
import { FormEvent, useState } from 'react'
import SimpleGuestLayout from '../../layouts/SimpleGuestLayout'
import { PasswordRequirements } from '../../components/ui/PasswordRequirements'
import { Input } from '../../components/ui/Input'
import { Button } from '../../components/ui/Button'
import { t } from '../../lib/i18n'

interface SetPasswordProps {
  token: string
  email: string
  errors?: {
    password?: string[]
    password_confirmation?: string[]
  }
}

export default function SetPassword({ token, email, errors }: SetPasswordProps) {
  const [password, setPassword] = useState('')

  const { data, setData, post, processing } = useForm({
    token,
    email,
    password: '',
    password_confirmation: '',
  })

  const handleSubmit = (e: FormEvent) => {
    e.preventDefault()
    post('/set-password')
  }

  return (
    <SimpleGuestLayout
      title={t('auth.set_password.page_title')}
      heading={t('auth.set_password.heading')}
      subheading={t('auth.set_password.subheading')}
    >
      <form onSubmit={handleSubmit} className="flex flex-col gap-7">
        {/* New Password Field with Requirements */}
        <div className="flex flex-col gap-3">
          <Input
            id="password"
            type="password"
            label={t('auth.reset_password.new_password')}
            value={data.password}
            onChange={(e) => {
              setData('password', e.target.value)
              setPassword(e.target.value)
            }}
            placeholder={t('auth.reset_password.new_password_placeholder')}
            error={errors?.password}
            autoComplete="new-password"
          />

          {/* Password Requirements Checklist - positioned per Figma: below input, 12px gap */}
          <PasswordRequirements password={password} />
        </div>

        {/* Confirm Password Field */}
        <Input
          id="password_confirmation"
          type="password"
          label={t('auth.reset_password.confirm_password')}
          value={data.password_confirmation}
          onChange={(e) => setData('password_confirmation', e.target.value)}
          placeholder={t('auth.reset_password.confirm_password_placeholder')}
          error={errors?.password_confirmation}
          autoComplete="new-password"
        />

        {/* Submit Button */}
        <Button
          type="submit"
          variant="primary"
          size="md"
          fullWidth
          loading={processing}
        >
          {t('auth.set_password.submit')}
        </Button>
      </form>
    </SimpleGuestLayout>
  )
}
