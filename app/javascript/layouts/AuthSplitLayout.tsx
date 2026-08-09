import { Head, usePage } from '@inertiajs/react'
import { ReactNode } from 'react'
import { CheckCircle2, XCircle } from 'lucide-react'
import LanguageSelector from '../components/LanguageSelector'
import { t } from '../lib/i18n'

interface AuthSplitLayoutProps {
  title: string
  notice?: string
  error?: string
  children: ReactNode
}

export default function AuthSplitLayout({
  title,
  notice,
  error,
  children
}: AuthSplitLayoutProps) {
  const { locale } = usePage<{ locale: string }>().props
  const features = [
    t('auth.layout.feature_automation'),
    t('auth.layout.feature_personalization'),
    t('auth.layout.feature_scoring')
  ]

  return (
    <div className="min-h-screen flex bg-[var(--background)] text-[var(--foreground)]">
      <Head title={title} />

      <div className="hidden lg:flex lg:w-1/2 relative overflow-hidden bg-gradient-to-br from-[#0a0a0b] via-[#111113] to-[#0a0a0b]">
        <div className="absolute inset-0">
          <div className="absolute top-1/4 left-1/4 w-96 h-96 bg-[var(--primary)]/20 rounded-full blur-[120px] animate-pulse" />
          <div
            className="absolute bottom-1/4 right-1/4 w-80 h-80 bg-blue-500/10 rounded-full blur-[100px] animate-pulse"
            style={{ animationDelay: '1000ms' }}
          />
          <div
            className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-64 h-64 bg-emerald-500/10 rounded-full blur-[80px] animate-pulse"
            style={{ animationDelay: '500ms' }}
          />
        </div>

        <div
          className="absolute inset-0"
          style={{
            backgroundImage:
              'linear-gradient(rgba(255,255,255,0.02) 1px, transparent 1px), linear-gradient(90deg, rgba(255,255,255,0.02) 1px, transparent 1px)',
            backgroundSize: '64px 64px'
          }}
        />

        <div className="relative z-10 flex flex-col justify-center items-center w-full p-12">
          <div className="relative mb-8">
            <div className="absolute inset-0 bg-[var(--primary)]/30 blur-3xl rounded-full scale-150" />
            <div className="relative flex h-24 w-24 items-center justify-center rounded-3xl bg-white shadow-2xl shadow-[var(--primary)]/20">
              <img
                src="/amplifa-logo-icon-dark.svg"
                alt="Amplifa"
                className="h-14 w-14 object-contain"
              />
            </div>
          </div>

          <p className="text-xl text-[var(--foreground-muted)] text-center max-w-md leading-relaxed">
            {t('auth.layout.tagline')}
          </p>

          <div className="mt-16 space-y-4">
            {features.map((feature) => (
              <div key={feature} className="flex items-center gap-3 text-[var(--foreground-muted)]">
                <div className="h-2 w-2 rounded-full bg-[var(--primary)]" />
                <span>{feature}</span>
              </div>
            ))}
          </div>
        </div>
      </div>

      <div className="w-full lg:w-1/2 flex items-center justify-center p-8 bg-[var(--background)]">
        <div className="w-full max-w-md">
          <div className="lg:hidden flex justify-center mb-8">
            <div className="flex h-16 w-16 items-center justify-center rounded-2xl bg-white shadow-lg">
              <img
                src="/amplifa-logo-icon-dark.svg"
                alt="Amplifa"
                className="h-10 w-10 object-contain"
              />
            </div>
          </div>

          <div className="flex justify-end mb-4">
            <LanguageSelector currentLocale={locale} />
          </div>

          {notice && (
            <div className="mb-6">
              <div
                className="rounded-lg p-4"
                style={{
                  backgroundColor: 'var(--success-muted)',
                  border: '1px solid var(--success)'
                }}
              >
                <div className="flex items-center">
                  <CheckCircle2 className="h-5 w-5 shrink-0 text-[var(--success)]" />
                  <p className="ml-3 text-sm font-medium text-[var(--success)]">{notice}</p>
                </div>
              </div>
            </div>
          )}

          {error && (
            <div className="mb-6">
              <div
                className="rounded-lg p-4"
                style={{
                  backgroundColor: 'var(--error-muted)',
                  border: '1px solid var(--error)'
                }}
              >
                <div className="flex items-center">
                  <XCircle className="h-5 w-5 shrink-0 text-[var(--error)]" />
                  <p className="ml-3 text-sm font-medium text-[var(--error)]">{error}</p>
                </div>
              </div>
            </div>
          )}

          {children}
        </div>
      </div>
    </div>
  )
}
