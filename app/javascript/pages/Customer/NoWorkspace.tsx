import { Head, Link } from '@inertiajs/react'
import { Building2, LogOut } from 'lucide-react'
import { t } from '../../lib/i18n'

export default function NoWorkspace() {
  return (
    <div className="flex min-h-screen items-center justify-center bg-[#0f1114] px-6 py-12">
      <Head title={t('workspaces.no_workspace.page_title')} />
      <div className="w-full max-w-md rounded-3xl border border-white/[0.08] bg-[var(--background-elevated)] p-8 text-center shadow-[var(--shadow-lg)]">
        <div className="mx-auto mb-6 flex size-14 items-center justify-center rounded-2xl bg-white/[0.05] text-[var(--foreground)]">
          <Building2 className="size-7" strokeWidth={2} />
        </div>
        <h1 className="mb-3 text-2xl font-semibold text-[var(--foreground)]">
          {t('workspaces.no_workspace.heading')}
        </h1>
        <p className="mb-6 text-sm leading-6 text-[var(--foreground-muted)]">
          {t('workspaces.no_workspace.description')}
        </p>
        <Link
          href="/logout"
          method="post"
          as="button"
          className="inline-flex items-center justify-center gap-2 rounded-xl bg-white px-4 py-2 text-sm font-medium text-[#101010] transition-colors hover:bg-white/90"
        >
          <LogOut className="size-4" strokeWidth={2} />
          {t('workspaces.no_workspace.logout')}
        </Link>
      </div>
    </div>
  )
}
