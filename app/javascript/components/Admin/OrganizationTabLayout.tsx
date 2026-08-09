import { Link, usePage } from '@inertiajs/react'
import { ReactNode, useRef, useState, useEffect, useCallback } from 'react'
import {
  LayoutDashboard,
  UserCircle,
  ChevronLeft,
  ChevronRight,
  ChevronDown,
} from 'lucide-react'
import AuthenticatedLayout from '../../layouts/AuthenticatedLayout'
import { t } from '../../lib/i18n'

interface Organization {
  id: number
  name: string
}

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

interface Flash {
  notice?: string
  alert?: string
}

interface AgentForDropdown {
  id: number
  name: string
  status: string
}

interface OrganizationTabLayoutProps {
  organization: Organization
  currentTab: string
  account: Account
  flash?: Flash
  headerActions?: ReactNode
  fullBleed?: boolean
  selectedAgentId?: number | null
  children: ReactNode
}

const TABS = [
  { id: 'overview', labelKey: 'admin.organizations.tabs.overview', suffix: '', icon: LayoutDashboard },
  { id: 'users', labelKey: 'admin.organizations.tabs.users', suffix: '/users', icon: UserCircle },
]

export default function OrganizationTabLayout({
  organization,
  currentTab,
  account,
  flash,
  headerActions,
  fullBleed,
  selectedAgentId,
  children
}: OrganizationTabLayoutProps) {
  const { props } = usePage<{ agents_for_dropdown?: AgentForDropdown[] }>()
  const agentsForDropdown = props.agents_for_dropdown ?? []
  const canShowAgentsDropdown = agentsForDropdown.length > 0
  const basePath = `/admin/organizations/${organization.id}`
  const scrollContainerRef = useRef<HTMLElement>(null)
  const [canScrollLeft, setCanScrollLeft] = useState(false)
  const [canScrollRight, setCanScrollRight] = useState(false)
  const [agentsDropdownOpen, setAgentsDropdownOpen] = useState(false)
  const [agentsTabRect, setAgentsTabRect] = useState<DOMRect | null>(null)
  const agentsTabRef = useRef<HTMLDivElement>(null)
  const agentsDropdownTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null)

  const checkScroll = useCallback(() => {
    if (scrollContainerRef.current) {
      const { scrollLeft, scrollWidth, clientWidth } = scrollContainerRef.current
      setCanScrollLeft(scrollLeft > 0)
      setCanScrollRight(scrollLeft < scrollWidth - clientWidth - 1)
    }
  }, [])

  useEffect(() => {
    checkScroll()
    window.addEventListener('resize', checkScroll)
    return () => window.removeEventListener('resize', checkScroll)
  }, [checkScroll])

  useEffect(() => {
    return () => {
      if (agentsDropdownTimeoutRef.current) {
        clearTimeout(agentsDropdownTimeoutRef.current)
      }
    }
  }, [])

  useEffect(() => {
    if (scrollContainerRef.current) {
      const activeTab = scrollContainerRef.current.querySelector(`[data-tab-id="${currentTab}"]`)
      if (activeTab) {
        activeTab.scrollIntoView({ behavior: 'smooth', block: 'nearest', inline: 'center' })
      }
    }
  }, [currentTab])

  const scroll = (direction: 'left' | 'right') => {
    if (scrollContainerRef.current) {
      const scrollAmount = 200
      const currentScroll = scrollContainerRef.current.scrollLeft
      const targetScroll = direction === 'left' 
        ? currentScroll - scrollAmount 
        : currentScroll + scrollAmount
      
      scrollContainerRef.current.scrollTo({
        left: targetScroll,
        behavior: 'smooth'
      })
    }
  }

  const handleAgentsTabEnter = () => {
    if (!canShowAgentsDropdown) return
    if (agentsDropdownTimeoutRef.current) {
      clearTimeout(agentsDropdownTimeoutRef.current)
      agentsDropdownTimeoutRef.current = null
    }
    if (agentsTabRef.current) {
      setAgentsTabRect(agentsTabRef.current.getBoundingClientRect())
    }
    setAgentsDropdownOpen(true)
  }

  const handleAgentsTabLeave = () => {
    if (!canShowAgentsDropdown) return
    agentsDropdownTimeoutRef.current = setTimeout(() => {
      setAgentsDropdownOpen(false)
    }, 150)
  }

  const getAgentStatusDotClass = (status: string) => {
    switch (status) {
      case 'draft':
        return 'bg-[var(--foreground-subtle)]'
      case 'ready':
        return 'bg-blue-400'
      case 'active':
        return 'bg-[var(--success)]'
      case 'paused':
        return 'bg-[var(--warning)]'
      case 'completed':
        return 'bg-[var(--success)]'
      default:
        return 'bg-[var(--foreground-subtle)]'
    }
  }

  const tabs = (
    <div className="relative group -mx-4 lg:-ml-3 lg:mr-0">
      <div
        className={`absolute left-0 top-0 bottom-0 z-10 flex items-center transition-opacity duration-300 ${
          canScrollLeft ? 'opacity-100' : 'opacity-0 pointer-events-none'
        }`}
      >
        <div className="absolute inset-0 bg-gradient-to-r from-[var(--background)] to-transparent w-16 pointer-events-none" />

        <button
          type="button"
          onClick={() => scroll('left')}
          className="relative z-10 p-1 ml-1 text-[var(--foreground-muted)] hover:text-[var(--foreground)] hover:bg-[var(--card-hover)] rounded-full transition-colors focus:outline-none focus:ring-2 focus:ring-[var(--accent)]"
          aria-label="Scroll left"
        >
          <ChevronLeft className="w-5 h-5" />
        </button>
      </div>

      <nav 
        ref={scrollContainerRef}
        className="flex gap-1 -mb-px overflow-x-auto [&::-webkit-scrollbar]:hidden [scrollbar-width:none] scroll-smooth px-4 lg:px-0"
        onScroll={checkScroll}
      >
        {TABS.map((tab) => {
          const isActive = currentTab === tab.id
          const href = tab.id === 'sequences' && selectedAgentId
            ? `${basePath}${tab.suffix}?agent_id=${selectedAgentId}`
            : `${basePath}${tab.suffix}`
          const Icon = tab.icon
          if (tab.id === 'agents') {
            return (
              <div
                key={tab.id}
                ref={agentsTabRef}
                onPointerEnter={handleAgentsTabEnter}
                onPointerLeave={handleAgentsTabLeave}
                className="relative"
              >
                <Link
                  href={href}
                  data-active={isActive}
                  data-tab-id={tab.id}
                  className={`
                    flex items-center gap-2 px-3 py-2 text-sm font-medium whitespace-nowrap border-b-2 transition-all duration-200 select-none
                    ${isActive
                      ? 'border-[var(--accent)] text-[var(--accent)]'
                      : 'border-transparent text-[var(--foreground-muted)] hover:text-[var(--foreground)] hover:border-[var(--border)]'
                    }
                  `}
                >
                  <Icon className="w-4 h-4" />
                  <span>{t(tab.labelKey)}</span>
                  {canShowAgentsDropdown && (
                    <ChevronDown className="w-3.5 h-3.5 text-current opacity-70" />
                  )}
                </Link>
              </div>
            )
          }
          return (
            <Link
              key={tab.id}
              href={href}
              data-active={isActive}
              data-tab-id={tab.id}
              className={`
                flex items-center gap-2 px-3 py-2 text-sm font-medium whitespace-nowrap border-b-2 transition-all duration-200 select-none
                ${isActive
                  ? 'border-[var(--accent)] text-[var(--accent)]'
                  : 'border-transparent text-[var(--foreground-muted)] hover:text-[var(--foreground)] hover:border-[var(--border)]'
                }
              `}
            >
              <Icon className="w-4 h-4" />
              {t(tab.labelKey)}
            </Link>
          )
        })}
      </nav>

      {agentsDropdownOpen && agentsTabRect && canShowAgentsDropdown && (
        <div
          className="fixed z-[100]"
          style={{
            left: agentsTabRect.left,
            top: agentsTabRect.bottom + 6
          }}
          onPointerEnter={handleAgentsTabEnter}
          onPointerLeave={handleAgentsTabLeave}
        >
          <div className="bg-[#171717] border border-white/10 rounded-lg shadow-lg py-2 min-w-[200px] max-h-[300px] overflow-y-auto">
            {agentsForDropdown.map((agent) => (
              <Link
                key={agent.id}
                href={`${basePath}/agents/${agent.id}`}
                className="flex items-center gap-2 px-3 py-2 text-sm text-[var(--foreground-muted)] hover:bg-white/5 hover:text-white transition-colors"
                onClick={() => setAgentsDropdownOpen(false)}
              >
                <span className={`w-2 h-2 rounded-full ${getAgentStatusDotClass(agent.status)}`} />
                <span className="truncate">{agent.name}</span>
              </Link>
            ))}
          </div>
        </div>
      )}

      <div
        className={`absolute right-0 top-0 bottom-0 z-10 flex items-center justify-end transition-opacity duration-300 ${
          canScrollRight ? 'opacity-100' : 'opacity-0 pointer-events-none'
        }`}
      >
        <div className="absolute inset-0 bg-gradient-to-l from-[var(--background)] to-transparent w-16 pointer-events-none" />

        <button
          type="button"
          onClick={() => scroll('right')}
          className="relative z-10 p-1 mr-1 text-[var(--foreground-muted)] hover:text-[var(--foreground)] hover:bg-[var(--card-hover)] rounded-full transition-colors focus:outline-none focus:ring-2 focus:ring-[var(--accent)]"
          aria-label="Scroll right"
        >
          <ChevronRight className="w-5 h-5" />
        </button>
      </div>
    </div>
  )

  return (
    <AuthenticatedLayout
      title={organization.name}
      account={account}
      flash={flash}
      headerActions={headerActions}
      stickyNavigation={tabs}
      fullBleed={fullBleed}
    >
      <div className={`animate-in fade-in duration-300 slide-in-from-bottom-2 ${fullBleed ? 'h-full' : ''}`}>
        {children}
      </div>
    </AuthenticatedLayout>
  )
}
