import { Head } from '@inertiajs/react'
import { Clock, Mail, User, LogIn } from 'lucide-react'
import SimpleGuestLayout from '../../../layouts/SimpleGuestLayout'
import { Button } from '../../../components/ui/Button'
import { t } from '../../../lib/i18n'

interface Invitation {
  email: string
  first_name: string
  expires_at: string
}

interface ExpiredProps {
  invitation?: Invitation
  message: string
}

export default function Expired({ invitation, message }: ExpiredProps) {
  const formatDate = (dateString: string) => {
    try {
      const date = new Date(dateString)
      return date.toLocaleDateString('en-US', {
        year: 'numeric',
        month: 'long',
        day: 'numeric'
      })
    } catch {
      return dateString
    }
  }

  return (
    <>
      <Head title={t('public_invitations.expired.page_title')} />
      <SimpleGuestLayout
        title={t('public_invitations.expired.title')}
        heading={t('public_invitations.expired.heading')}
        subheading={t('public_invitations.expired.subheading')}
      >
        <div className="flex flex-col gap-5">
          {/* Informational message */}
          <div
            className="rounded-lg p-4"
            style={{
              backgroundColor: 'var(--warning-muted)',
              border: '1px solid var(--warning)'
            }}
          >
            <div className="flex items-start gap-3">
              <Clock size={20} className="text-[var(--warning)] flex-shrink-0 mt-0.5" />
              <p className="text-sm text-[var(--foreground)] leading-relaxed">
                {message || t('public_invitations.expired.default_message')}
              </p>
            </div>
          </div>

          {/* Invitation details if available */}
          {invitation && (
            <div
              className="p-4 rounded-lg"
              style={{
                backgroundColor: 'var(--secondary)',
                border: '1px solid var(--border)'
              }}
            >
              <h3 className="text-sm font-semibold text-[var(--foreground)] mb-3">
                {t('public_invitations.expired.details_title')}
              </h3>
              <dl className="space-y-2 text-sm">
                <div className="flex justify-between items-center">
                  <dt className="text-[var(--foreground-muted)] flex items-center gap-2">
                    <Mail size={14} />
                    {t('public_invitations.expired.sent_to')}
                  </dt>
                  <dd className="font-medium text-[var(--foreground)]">{invitation.email}</dd>
                </div>
                <div className="flex justify-between items-center">
                  <dt className="text-[var(--foreground-muted)] flex items-center gap-2">
                    <User size={14} />
                    {t('common.name')}:
                  </dt>
                  <dd className="font-medium text-[var(--foreground)]">{invitation.first_name}</dd>
                </div>
                {invitation.expires_at && (
                  <div className="flex justify-between items-center">
                    <dt className="text-[var(--foreground-muted)] flex items-center gap-2">
                      <Clock size={14} />
                      {t('public_invitations.expired.expired_on')}
                    </dt>
                    <dd className="font-medium text-[var(--foreground)]">{formatDate(invitation.expires_at)}</dd>
                  </div>
                )}
              </dl>
            </div>
          )}

          {/* Next steps */}
          <div
            className="p-4 rounded-lg"
            style={{
              backgroundColor: 'var(--card)',
              border: '2px dashed var(--border)'
            }}
          >
            <h3 className="text-sm font-semibold text-[var(--foreground)] mb-3">
              {t('public_invitations.next_steps_title')}
            </h3>
            <div className="space-y-3 text-sm">
              <p className="flex items-start gap-3">
                <span
                  className="flex-shrink-0 h-5 w-5 rounded-full flex items-center justify-center text-xs font-semibold"
                  style={{
                    backgroundColor: 'var(--accent)',
                    color: 'var(--background)'
                  }}
                >
                  1
                </span>
                <span className="text-[var(--foreground-muted)]">
                  <strong className="text-[var(--foreground)]">{t('public_invitations.expired.next_steps.request_title')}</strong> {t('public_invitations.expired.next_steps.request_body')}
                </span>
              </p>
              <p className="flex items-start gap-3">
                <span
                  className="flex-shrink-0 h-5 w-5 rounded-full flex items-center justify-center text-xs font-semibold"
                  style={{
                    backgroundColor: 'var(--accent)',
                    color: 'var(--background)'
                  }}
                >
                  2
                </span>
                <span className="text-[var(--foreground-muted)]">
                  <strong className="text-[var(--foreground)]">{t('public_invitations.expired.next_steps.support_title')}</strong> {t('public_invitations.expired.next_steps.support_body')}
                </span>
              </p>
            </div>
          </div>

          {/* Action buttons */}
          <div className="flex flex-col sm:flex-row gap-3">
            <a
              href="mailto:support@amplifa.ai?subject=Invitation%20Expired&body=Hi%2C%20my%20invitation%20has%20expired.%20Please%20send%20me%20a%20new%20one.%0A%0AEmail%3A%20"
              className="flex-1"
            >
              <Button
                type="button"
                variant="primary"
                size="md"
                fullWidth
                icon={<Mail size={16} />}
              >
                {t('public_invitations.expired.request_new')}
              </Button>
            </a>

            <a
              href="/login"
              className="flex-1"
            >
              <Button
                type="button"
                variant="secondary"
                size="md"
                fullWidth
                icon={<LogIn size={16} />}
              >
                {t('public_invitations.go_to_login')}
              </Button>
            </a>
          </div>
        </div>
      </SimpleGuestLayout>
    </>
  )
}
