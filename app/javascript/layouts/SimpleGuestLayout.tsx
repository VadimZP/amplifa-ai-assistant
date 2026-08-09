import { Head } from '@inertiajs/react'
import { ReactNode } from 'react'
import { CheckCircle2, XCircle } from 'lucide-react'
import { DotPattern } from '../components/ui/DotPattern'

interface SimpleGuestLayoutProps {
  title: string
  heading: string
  subheading?: string
  notice?: string
  error?: string
  children: ReactNode
}

export default function SimpleGuestLayout({
  title,
  heading,
  subheading,
  notice,
  error,
  children
}: SimpleGuestLayoutProps) {
  return (
    <div className="min-h-screen relative overflow-hidden bg-[var(--background)]">
      <Head title={title} />

      {/* Decorative dot pattern - top center */}
      <DotPattern position="top-center" className="opacity-40" />

      {/* Main content */}
      <div className="relative flex flex-col items-center justify-center py-12 px-4 sm:px-6 lg:px-8 min-h-screen">
        {/* Logo - 24px height, ~95px width per Figma node 201:7337, 24px gap (mb-6) to card */}
        <div className="mb-6">
          <img
            src="/amplifa-logo-white.svg"
            alt="Amplifa"
            className="h-6 w-[95px]"
          />
        </div>

        <div className="w-full max-w-[384px]">
          {/* Card container */}
          <div
            className="rounded-[14px] px-0 py-6 overflow-hidden"
            style={{
              backgroundColor: 'var(--card)',
              border: '1px solid var(--border)',
              boxShadow: '0 1px 3px rgba(0, 0, 0, 0.1), 0 1px 2px -1px rgba(0, 0, 0, 0.1)'
            }}
          >
            {/* Card Header */}
            <div className="px-6 mb-6">
              <h2
                className="text-base font-semibold leading-none"
                style={{ color: 'var(--foreground)' }}
              >
                {heading}
              </h2>
              {subheading && (
                <p
                  className="mt-1.5 text-sm leading-5"
                  style={{ color: 'var(--foreground-muted)' }}
                >
                  {subheading}
                </p>
              )}
            </div>

            {notice && (
              <div className="px-6 mb-6">
                <div
                  className="rounded-lg p-4"
                  style={{
                    backgroundColor: 'var(--success-muted)',
                    border: '1px solid var(--success)'
                  }}
                >
                  <div className="flex items-center">
                    <div className="flex-shrink-0">
                      <CheckCircle2 className="h-5 w-5 text-[var(--success)]" />
                    </div>
                    <div className="ml-3">
                      <p className="text-sm font-medium text-[var(--success)]">{notice}</p>
                    </div>
                  </div>
                </div>
              </div>
            )}

            {/* Error message */}
            {error && (
              <div className="px-6 mb-6">
                <div
                  className="rounded-lg p-4"
                  style={{
                    backgroundColor: 'var(--error-muted)',
                    border: '1px solid var(--error)'
                  }}
                >
                  <div className="flex items-center">
                    <div className="flex-shrink-0">
                      <XCircle className="h-5 w-5 text-[var(--error)]" />
                    </div>
                    <div className="ml-3">
                      <p
                        className="text-sm font-medium"
                        style={{ color: 'var(--error)' }}
                      >
                        {error}
                      </p>
                    </div>
                  </div>
                </div>
              </div>
            )}

            {/* Card Content */}
            <div className="px-6">
              {children}
            </div>

            {/* Divider line */}
            <div
              className="mt-6"
              style={{ borderTop: '1px solid var(--border)' }}
            />

            {/* Help text - per Figma node 201:7337 */}
            <div className="pt-6 px-6">
              <p
                className="text-xs text-center text-[var(--foreground-muted)]"
              >
                Having trouble? Contact us at{' '}
                <a
                  href="mailto:support@amplifa.com"
                  className="hover:underline transition-colors duration-150"
                  style={{ color: 'var(--accent)' }}
                >
                  support@amplifa.com
                </a>
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
