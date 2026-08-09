import { Link, usePage } from '@inertiajs/react'
import { ReactNode, useRef, useCallback, useEffect, useState } from 'react'
import {
  Building2,
  CreditCard,
  User,
  Users2,
  Ban,
} from 'lucide-react'
import AuthenticatedLayout from './AuthenticatedLayout'
import { t } from '../lib/i18n'

interface Account {
  id: number
  email: string
  first_name: string
  last_name: string
  full_name: string
  role: string
  'amplifa_admin?'?: boolean
  'customer_admin?'?: boolean
  'customer_user?'?: boolean
}

interface Organization {
  id: number
  name: string
}

interface Flash {
  notice?: string
  alert?: string
}

interface SidebarSection {
  id: string
  label: string
}

interface SettingsLayoutProps {
  currentTab: string
  sidebarSections?: SidebarSection[]
  children: ReactNode
}

const TABS = [
  { id: 'billing', labelKey: 'customer_settings.tabs.billing', href: '/settings/billing', icon: CreditCard },
  { id: 'company', labelKey: 'customer_settings.tabs.company', href: '/settings/company/edit', icon: Building2 },
  { id: 'team', labelKey: 'customer_settings.tabs.team', href: '/settings/team', icon: Users2 },
  { id: 'profile', labelKey: 'customer_settings.tabs.profile', href: '/settings/profile', icon: User },
  { id: 'blacklists', labelKey: 'customer_settings.tabs.blacklists', href: '/settings/blacklists', icon: Ban },
]

export default function SettingsLayout({
  currentTab,
  sidebarSections,
  children,
}: SettingsLayoutProps) {
  const { auth, flash } = usePage<{
    auth: { account: Account; organization?: Organization }
    flash?: Flash
    [key: string]: unknown
  }>().props

  const { account, organization } = auth
  const mainContentRef = useRef<HTMLDivElement>(null)
  const [activeSection, setActiveSection] = useState<string | null>(
    sidebarSections?.[0]?.id ?? null
  )

  const scrollToSection = useCallback((sectionId: string) => {
    const el = document.getElementById(sectionId)
    if (el && mainContentRef.current) {
      mainContentRef.current.scrollTo({
        top: el.offsetTop - 24,
        behavior: 'smooth',
      })
    }
  }, [])

  // Track active section based on scroll position
  useEffect(() => {
    if (!sidebarSections || sidebarSections.length === 0) return

    const container = mainContentRef.current
    if (!container) return

    const handleScroll = () => {
      const scrollTop = container.scrollTop + 48

      for (let i = sidebarSections.length - 1; i >= 0; i--) {
        const el = document.getElementById(sidebarSections[i].id)
        if (el && el.offsetTop <= scrollTop) {
          setActiveSection(sidebarSections[i].id)
          return
        }
      }
      setActiveSection(sidebarSections[0]?.id ?? null)
    }

    container.addEventListener('scroll', handleScroll)
    return () => container.removeEventListener('scroll', handleScroll)
  }, [sidebarSections])

  const tabs = (
    <nav className="relative z-[1] flex items-stretch gap-0.5 overflow-x-auto [&::-webkit-scrollbar]:hidden [scrollbar-width:none] -mx-4 px-4 pt-2 lg:mx-0 lg:px-0">
      {TABS.map((tab) => {
        const isActive = currentTab === tab.id
        const Icon = tab.icon

        return (
          <Link
            key={tab.id}
            href={tab.href}
            className={`
              flex items-center gap-2 px-4 py-2.5 text-sm font-medium whitespace-nowrap border transition-all duration-200 select-none
              ${isActive
                ? 'rounded-t-lg border-white/[0.08] border-b-transparent bg-[var(--background)] text-[var(--accent)]'
                : 'border-transparent border-b-white/[0.06] text-[var(--foreground-subtle)] hover:text-[var(--foreground)] hover:bg-white/[0.03] hover:rounded-t-lg'
              }
            `}
          >
            <Icon className="w-4 h-4" />
            <span>{t(tab.labelKey)}</span>
          </Link>
        )
      })}
    </nav>
  )

  return (
    <AuthenticatedLayout
      title={t('customer_settings.title')}
      subtitle={t('customer_settings.subtitle')}
      account={account}
      organization={organization}
      flash={flash}
      stickyNavigation={tabs}
      fullBleed
    >
      <div className="flex h-full">
        {/* Optional Left Sidebar */}
        {sidebarSections && sidebarSections.length > 0 && (
          <div className="hidden lg:block w-60 shrink-0 overflow-y-auto border-r border-[var(--border)] bg-[var(--background-secondary)]/55 p-5">
            <nav className="flex flex-col gap-1">
              {sidebarSections.map((section) => (
                <button
                  type="button"
                  key={section.id}
                  onClick={() => scrollToSection(section.id)}
                  className={`
                    text-left px-3.5 py-2.5 text-sm rounded-xl transition-colors duration-150
                    ${activeSection === section.id
                      ? 'border border-[var(--accent)]/15 bg-[var(--accent)]/10 text-[var(--foreground)]'
                      : 'border border-transparent text-[var(--foreground-subtle)] hover:text-[var(--foreground)] hover:bg-white/[0.04]'
                    }
                  `}
                >
                  {section.label}
                </button>
              ))}
            </nav>
          </div>
        )}

        {/* Main Content */}
        <div
          ref={mainContentRef}
          className="flex-1 overflow-y-auto p-6 lg:p-8"
        >
          {children}
        </div>
      </div>
    </AuthenticatedLayout>
  )
}
