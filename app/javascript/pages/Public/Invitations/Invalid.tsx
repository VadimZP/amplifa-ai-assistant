import { Head } from '@inertiajs/react'
import { XCircle, CheckCircle2, Mail, LogIn } from 'lucide-react'
import SimpleGuestLayout from '../../../layouts/SimpleGuestLayout'
import { Button } from '../../../components/ui/Button'
import { t } from '../../../lib/i18n'

interface InvalidProps {
  message: string
}

export default function Invalid({ message }: InvalidProps) {
  return (
    <>
      <Head title={t('public_invitations.invalid.page_title')} />
      <SimpleGuestLayout
        title={t('public_invitations.invalid.title')}
        heading={t('public_invitations.invalid.heading')}
        subheading={t('public_invitations.invalid.subheading')}
      >
        <div className="flex flex-col gap-5">
          {/* Error message */}
          <div
            className="rounded-lg p-4"
            style={{
              backgroundColor: 'var(--error-muted)',
              border: '1px solid var(--error)'
            }}
          >
            <div className="flex items-start gap-3">
              <XCircle size={20} className="text-[var(--error)] flex-shrink-0 mt-0.5" />
              <p className="text-sm text-[var(--foreground)] leading-relaxed">
                {message || t('public_invitations.invalid.default_message')}
              </p>
            </div>
          </div>

          {/* Reasons for invalid invitation */}
          <div
            className="p-4 rounded-lg"
            style={{
              backgroundColor: 'var(--card)',
              border: '1px solid var(--border)'
            }}
          >
            <h3 className="text-sm font-semibold text-[var(--foreground)] mb-3">
              {t('public_invitations.invalid.why_title')}
            </h3>
            <div className="space-y-2.5 text-sm">
              <p className="flex items-start gap-2">
                <CheckCircle2 size={16} className="text-[var(--foreground-subtle)] flex-shrink-0 mt-0.5" />
                <span className="text-[var(--foreground-muted)]">{t('public_invitations.invalid.reasons.incomplete')}</span>
              </p>
              <p className="flex items-start gap-2">
                <CheckCircle2 size={16} className="text-[var(--foreground-subtle)] flex-shrink-0 mt-0.5" />
                <span className="text-[var(--foreground-muted)]">{t('public_invitations.invalid.reasons.used')}</span>
              </p>
              <p className="flex items-start gap-2">
                <CheckCircle2 size={16} className="text-[var(--foreground-subtle)] flex-shrink-0 mt-0.5" />
                <span className="text-[var(--foreground-muted)]">{t('public_invitations.invalid.reasons.cancelled')}</span>
              </p>
              <p className="flex items-start gap-2">
                <CheckCircle2 size={16} className="text-[var(--foreground-subtle)] flex-shrink-0 mt-0.5" />
                <span className="text-[var(--foreground-muted)]">{t('public_invitations.invalid.reasons.deleted')}</span>
              </p>
            </div>
          </div>

          {/* Next steps */}
          <div
            className="p-4 rounded-lg"
            style={{
              backgroundColor: 'var(--secondary)',
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
                  <strong className="text-[var(--foreground)]">{t('public_invitations.invalid.next_steps.check_email_title')}</strong> {t('public_invitations.invalid.next_steps.check_email_body')}
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
                  <strong className="text-[var(--foreground)]">{t('public_invitations.invalid.next_steps.contact_admin_title')}</strong> {t('public_invitations.invalid.next_steps.contact_admin_body')}
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
                  3
                </span>
                <span className="text-[var(--foreground-muted)]">
                  <strong className="text-[var(--foreground)]">{t('public_invitations.invalid.next_steps.already_account_title')}</strong> {t('public_invitations.invalid.next_steps.already_account_body')}
                </span>
              </p>
            </div>
          </div>

          {/* Action buttons */}
          <div className="flex flex-col sm:flex-row gap-3">
            <a
              href="mailto:support@amplifa.ai?subject=Invalid%20Invitation&body=Hi%2C%20I%27m%20having%20trouble%20with%20my%20invitation%20link.%20Please%20help.%0A%0AEmail%3A%20"
              className="flex-1"
            >
              <Button
                type="button"
                variant="primary"
                size="md"
                fullWidth
                icon={<Mail size={16} />}
              >
                {t('public_invitations.contact_support')}
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
