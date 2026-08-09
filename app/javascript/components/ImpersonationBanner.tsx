import { router } from '@inertiajs/react'
import { Info, LogOut } from 'lucide-react'

interface ImpersonationBannerProps {
  adminName: string
  currentUserName: string
}

export default function ImpersonationBanner({ adminName, currentUserName }: ImpersonationBannerProps) {
  const handleExitImpersonation = () => {
    router.post('/admin/impersonation/exit')
  }

  return (
    <div className="bg-[var(--warning-muted)] border-b border-[var(--warning)]/30">
      <div className="mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex items-center justify-between h-12">
          <div className="flex items-center">
            <Info className="h-5 w-5 text-amber-400 mr-2" />
            <span className="text-sm font-medium text-amber-200">
              You are viewing as <span className="font-semibold text-white">{currentUserName}</span>
            </span>
            <span className="mx-2 text-amber-400">•</span>
            <span className="text-sm text-amber-300">
              Admin: {adminName}
            </span>
          </div>
          <button
            onClick={handleExitImpersonation}
            className="inline-flex items-center px-3 py-1 border border-amber-400/40 text-sm font-medium rounded-lg text-amber-200 bg-[var(--background)] hover:bg-amber-900/30 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-offset-[var(--background)] focus:ring-amber-400 transition-colors"
          >
            <LogOut className="h-4 w-4 mr-1" />
            Exit Impersonation
          </button>
        </div>
      </div>
    </div>
  )
}
