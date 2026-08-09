import { Link } from '@inertiajs/react'
import { AlertTriangle } from 'lucide-react'
import { t } from '../lib/i18n'

interface ErrorProps {
  message?: string | null
  status?: number | null
}

export default function Error({ message, status }: ErrorProps) {
  return (
    <div className="flex min-h-screen flex-col items-center justify-center gap-4 bg-[var(--background)] p-8 text-center">
      <div className="flex size-14 items-center justify-center rounded-full border border-[var(--border)] bg-[var(--card)]">
        <AlertTriangle className="size-7 text-[var(--error)]" />
      </div>
      {status ? (
        <p className="text-sm font-semibold uppercase tracking-wider text-[var(--foreground-muted)]">
          {status}
        </p>
      ) : null}
      <h1 className="max-w-md text-xl font-semibold text-[var(--foreground)]">
        {message || t('errors.generic', { defaultValue: 'Something went wrong' })}
      </h1>
      <Link href="/" className="text-sm text-[var(--accent)] hover:underline">
        {t('errors.back_home', { defaultValue: 'Go back home' })}
      </Link>
    </div>
  )
}
