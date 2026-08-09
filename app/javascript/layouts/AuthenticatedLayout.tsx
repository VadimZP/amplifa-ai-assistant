import { Head, Link, router, usePage } from '@inertiajs/react'
import { ReactNode, useState, useEffect, useCallback, useRef, useMemo } from 'react'
import ImpersonationBanner from '../components/ImpersonationBanner'
import LanguageSelector from '../components/LanguageSelector'
import { Badge } from '../components/ui/Badge'
import {
  getLastAssistantChatPath,
  parseAssistantChatId,
  setLastAssistantChatPath,
} from '../lib/assistantLastChat'
import { t } from '../lib/i18n'
import {
  LayoutDashboard,
  Building2,
  Users,
  Activity,
  Mail,
  BookOpen,
  Inbox,
  Settings,
  LogOut,
  Menu,
  X,
  CheckCircle2,
  XCircle,
  Zap,
  MoreHorizontal,
  ArrowLeft,
  ChevronDown,
  CalendarCheck,
  TrendingUp,
  Sparkles
} from 'lucide-react'

/**
 * AuthenticatedLayout - Sidebar navigation layout for authenticated users
 *
 * Design Reference: Figma node 257:8673
 *
 * Features:
 * - Left sidebar with icon navigation (vertical icons with labels)
 * - Active state with white background and glow effect
 * - Page header with title, subtitle, and optional action buttons
 * - Flash message support
 * - Responsive: hamburger menu on mobile
 * - Different navigation items for admin vs customer users
 */

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

interface ImpersonatingAdmin {
  id: number
  name: string
  email: string
}

// Shared props from Inertia (automatically available on all pages)
interface SharedPageProps {
  [key: string]: unknown;
  auth?: {
    current_organization?: Organization
    organizations?: Organization[]
  }
  impersonating?: boolean
  impersonating_admin?: ImpersonatingAdmin
  inbox_unread_count?: number
  locale?: string
  suppress_flash?: boolean
}

interface AuthenticatedLayoutProps {
  title: string
  subtitle?: string
  account: Account
  organization?: Organization
  flash?: Flash
  headerActions?: ReactNode
  stickyNavigation?: ReactNode
  /** Optional back link URL */
  backLink?: string
  /** Optional back link text */
  backLinkText?: string
  /** Whether to remove default padding from main content area */
  fullBleed?: boolean
  /** Whether to hide the page header bar (desktop only; mobile keeps hamburger menu) */
  hideHeader?: boolean
  mainClassName?: string
  children: ReactNode
}

// Nav item type supporting nested children
interface NavItemType {
  id: string
  label: string
  icon: typeof LayoutDashboard
  href?: string
  badge?: string
  disabled?: boolean
  children?: NavItemType[]
}

// Admin navigation items
const ADMIN_NAV_ITEMS: NavItemType[] = [
  { id: 'dashboard', label: 'Dashboard', icon: LayoutDashboard, href: '/admin/dashboard' },
  { id: 'organizations', label: 'Customers', icon: Building2, href: '/admin/organizations' },
  { id: 'invitations', label: 'Invites', icon: Mail, href: '/admin/invitations' },
  { id: 'users', label: 'Users', icon: Users, href: '/admin/users' },
  { id: 'activities', label: 'Activities', icon: Activity, href: '/admin/activities' },
]

// Customer navigation items (Settings is now a regular nav item)
// WHY the assistant is customer-only: this array is only rendered when !isAdmin, and ChatPolicy
// denies amplifa admins, so there is no second place to gate it.
// WHY its label is resolved at render (see `navItems` below) instead of here: this array is built at
// module load, before the locale bundle has been fetched, so a module-level t() would miss.
const CUSTOMER_NAV_ITEMS: NavItemType[] = [
  { id: 'dashboard', label: 'Home', icon: LayoutDashboard, href: '/dashboard' },
  { id: 'assistant', label: 'Assistant', icon: Sparkles, href: '/assistant' },
  { id: 'playbooks', label: 'Playbooks', icon: BookOpen, href: '/playbooks' },
  { id: 'agents', label: 'Agents', icon: Zap, href: '/agents' },
  { id: 'inbox', label: 'Inbox', icon: Inbox, href: '/inbox' },
  { id: 'meetings', label: 'Meetings', icon: CalendarCheck, href: '/meetings' },
  { id: 'roi', label: 'ROI', icon: TrendingUp, href: '/roi' },
]

// Nav item measurements (actual rendered heights)
const NAV_ITEM_BASE_HEIGHT = 56 // h-14 = 56px fixed height
const NAV_GAP = 8 // gap-2
const LOGO_AREA_HEIGHT = 76
const BOTTOM_SECTION_HEIGHT = 190
const SIDEBAR_PADDING = 40 // py-5 = 20px * 2

export default function AuthenticatedLayout({
  title,
  subtitle,
  account,
  organization,
  flash,
  headerActions,
  stickyNavigation,
  backLink,
  backLinkText,
  fullBleed = false,
  hideHeader = false,
  mainClassName = '',
  children
}: AuthenticatedLayoutProps) {
  // Get impersonation state from Inertia shared props (automatically available)
  const { auth, impersonating, impersonating_admin, suppress_flash, inbox_unread_count } = usePage<SharedPageProps>().props

  const [mobileMenuOpen, setMobileMenuOpen] = useState(false)
  const [visibleItemCount, setVisibleItemCount] = useState<number | null>(null)
  const [overflowHovered, setOverflowHovered] = useState(false)
  const [moreButtonRect, setMoreButtonRect] = useState<DOMRect | null>(null)
  const [expandedSubmenu, setExpandedSubmenu] = useState<string | null>(null)
  const [submenuButtonRect, setSubmenuButtonRect] = useState<DOMRect | null>(null)
  const submenuButtonRef = useRef<HTMLDivElement>(null)
  const submenuTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const moreButtonRef = useRef<HTMLDivElement>(null)
  const overflowTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const isAdmin = account['amplifa_admin?'] === true
  const switchableOrganizations = auth?.organizations || []
  const currentOrganization = auth?.current_organization || organization
  const showWorkspaceLabel = !isAdmin && Boolean(currentOrganization) && switchableOrganizations.length > 1

  const switchWorkspace = (organizationId: number) => {
    if (currentOrganization?.id === organizationId) return

    router.post('/workspace/switch', { organization_id: organizationId })
  }

  // Handlers for overflow menu hover with delay
  const handleOverflowEnter = () => {
    if (overflowTimeoutRef.current) {
      clearTimeout(overflowTimeoutRef.current)
      overflowTimeoutRef.current = null
    }
    if (moreButtonRef.current) {
      setMoreButtonRect(moreButtonRef.current.getBoundingClientRect())
    }
    setOverflowHovered(true)
  }

  const handleOverflowLeave = () => {
    overflowTimeoutRef.current = setTimeout(() => {
      setOverflowHovered(false)
    }, 150) // Small delay to allow moving to dropdown
  }

  // Handlers for submenu hover with delay
  const handleSubmenuEnter = (itemId: string) => {
    if (submenuTimeoutRef.current) {
      clearTimeout(submenuTimeoutRef.current)
      submenuTimeoutRef.current = null
    }
    if (submenuButtonRef.current) {
      setSubmenuButtonRect(submenuButtonRef.current.getBoundingClientRect())
    }
    setExpandedSubmenu(itemId)
  }

  const handleSubmenuLeave = () => {
    submenuTimeoutRef.current = setTimeout(() => {
      setExpandedSubmenu(null)
    }, 150)
  }

  // Get current locale from Inertia shared data
  const page = usePage<SharedPageProps>()
  const locale = page.props.locale || 'en'

  // Get current path to determine active nav item
  const currentPath = typeof window !== 'undefined' ? window.location.pathname : ''

  // WHY: The sidebar always links to /assistant, but users expect "Assistant" to reopen the chat
  // they were just in. Remember the last conversation per account + workspace in sessionStorage.
  const assistantNavHref = useMemo(() => {
    if (isAdmin || !currentOrganization?.id) return '/assistant'

    const activeChatId = parseAssistantChatId(currentPath)
    if (activeChatId) return `/assistant/${activeChatId}`

    return getLastAssistantChatPath(account.id, currentOrganization.id) ?? '/assistant'
  }, [account.id, currentOrganization?.id, currentPath, isAdmin])

  useEffect(() => {
    if (isAdmin || !currentOrganization?.id) return

    const activeChatId = parseAssistantChatId(currentPath)
    if (activeChatId) {
      setLastAssistantChatPath(account.id, currentOrganization.id, activeChatId)
    }
  }, [account.id, currentOrganization?.id, currentPath, isAdmin])

  // Select navigation items based on user role
  // WHY the assistant label is patched here: CUSTOMER_NAV_ITEMS is built at module load, before the
  // locale bundle resolves, so its label is translated at render time.
  const navItems = isAdmin
    ? ADMIN_NAV_ITEMS
    : CUSTOMER_NAV_ITEMS.map(item =>
        item.id === 'assistant'
          ? { ...item, label: t('assistant.nav'), href: assistantNavHref }
          : item
      )
  const settingsItem = { id: 'settings', label: t('navigation.settings'), icon: Settings, href: '/settings/billing' }
  const SettingsIcon = settingsItem.icon

  // Check if a nav item is active
  const isActive = (href: string) => {
    if (href === '/admin/dashboard') {
      return currentPath === '/admin' || currentPath === '/admin/dashboard'
    }
    if (href === '/dashboard') {
      return currentPath === '/' || currentPath === '/dashboard'
    }
    if (href.startsWith('/assistant')) {
      return currentPath === '/assistant' || /^\/assistant\/\d+/.test(currentPath)
    }
    return currentPath.startsWith(href)
  }

  const settingsActive = isActive(settingsItem.href)

  // Check if any child of a submenu is active
  const hasActiveChild = (item: NavItemType) => {
    if (!item.children) return false
    return item.children.some(child => child.href && isActive(child.href))
  }

  // Calculate how many items can fit in the available space
  // Formula: For N items, total height = N * itemHeight + (N-1) * gap
  // Solving for N: N = (availableHeight + gap) / (itemHeight + gap)
  const calculateVisibleItems = useCallback(() => {
    // Use window.innerHeight since sidebar is fixed with inset-y-0 (full viewport height)
    const sidebarHeight = window.innerHeight

    // Calculate available height for nav items
    const availableHeight = sidebarHeight - LOGO_AREA_HEIGHT - BOTTOM_SECTION_HEIGHT - SIDEBAR_PADDING

    // Calculate max items that fit without More button
    // N items = N * 44px + (N-1) * 8px = N * 52px - 8px
    // So: N * 52 - 8 <= available => N <= (available + 8) / 52
    const maxItemsWithoutMore = Math.floor((availableHeight + NAV_GAP) / (NAV_ITEM_BASE_HEIGHT + NAV_GAP))

    if (maxItemsWithoutMore >= navItems.length) {
      // All items fit, no overflow needed
      setVisibleItemCount(null)
    } else {
      // Need overflow - reserve space for "..." button (same size as nav item)
      // N visible + 1 More = (N+1) items total
      // Height = (N+1) * 44 + N * 8 = 44N + 44 + 8N = 52N + 44
      // So: 52N + 44 <= available => N <= (available - 44) / 52
      const maxItemsWithMore = Math.floor((availableHeight - NAV_ITEM_BASE_HEIGHT) / (NAV_ITEM_BASE_HEIGHT + NAV_GAP))
      setVisibleItemCount(Math.max(1, maxItemsWithMore))
    }
  }, [navItems.length])

  // Recalculate on mount and window resize
  useEffect(() => {
    calculateVisibleItems()

    const handleResize = () => calculateVisibleItems()
    window.addEventListener('resize', handleResize)

    return () => window.removeEventListener('resize', handleResize)
  }, [calculateVisibleItems])

  // Split items into visible and overflow
  const visibleItems = visibleItemCount !== null
    ? navItems.slice(0, visibleItemCount)
    : navItems
  const overflowItems = visibleItemCount !== null
    ? navItems.slice(visibleItemCount)
    : []

  // Check if any overflow item is active (including children of submenu items)
  const hasActiveOverflowItem = overflowItems.some(item => {
    if (item.children) return hasActiveChild(item)
    return item.href ? isActive(item.href) : false
  })

  const shouldUseFixedHeight = fullBleed || Boolean(stickyNavigation)

  return (
    <div className={`bg-[#0f1114] flex ${impersonating ? 'pt-12' : ''} ${shouldUseFixedHeight ? 'h-screen' : 'min-h-screen'}`}>
      <Head title={title} />

      {/* Impersonation Banner - Fixed at top */}
      {impersonating && impersonating_admin && (
        <div className="fixed top-0 left-0 right-0 z-[60]">
          <ImpersonationBanner
            adminName={impersonating_admin.name}
            currentUserName={account.full_name}
          />
        </div>
      )}

      {/* Mobile menu overlay */}
      {mobileMenuOpen && (
        <button
          type="button"
          aria-label="Close navigation"
          className="fixed inset-0 z-40 bg-black/50 lg:hidden"
          onClick={() => setMobileMenuOpen(false)}
        />
      )}

      {/* Sidebar - fixed to viewport on all screen sizes */}
      <aside
        className={`
          fixed left-0 z-50 w-20 bg-[var(--background-sidebar)] flex flex-col
          transform transition-transform duration-200 ease-out
          lg:translate-x-0
          ${impersonating ? 'top-12 bottom-0' : 'inset-y-0'}
          ${mobileMenuOpen ? 'translate-x-0' : '-translate-x-full'}
        `}
      >
        {/* Main sidebar container - justify-between pushes bottom section down */}
        <div className="flex h-full flex-col justify-between py-5">
          {/* Top Section: Logo + Nav - overflow-hidden ensures bottom section stays visible */}
          <div className="flex flex-col items-center min-h-0 flex-1 overflow-hidden">
            {/* Logo */}
            <div className="mb-8 shrink-0">
              <Link href={isAdmin ? '/admin/dashboard' : '/dashboard'} className="block">
                <div className="flex size-11 items-center justify-center rounded-2xl border border-white/10 bg-white shadow-[0_10px_24px_rgba(255,255,255,0.08)]">
                  <img
                    src="https://demo.amplifa.ai/assets/amplifa-logo-kzEFv8v0.png"
                    alt="Amplifa"
                    className="w-[18px] h-[18px] object-contain"
                    onError={(e) => {
                      // Fallback to text if icon not found
                      const target = e.target as HTMLImageElement
                      target.style.display = 'none'
                      target.parentElement!.innerHTML = '<span class="text-[#101010] font-bold text-sm">A</span>'
                    }}
                  />
                </div>
              </Link>
            </div>

            {/* Navigation Items */}
            <nav className="custom-scrollbar flex w-full flex-1 flex-col items-center justify-center gap-2 overflow-x-hidden overflow-y-auto">
                {/* Visible Items */}
                {visibleItems.map((item) => {
                  const Icon = item.icon

                  // Items with children get a submenu popup
                  if (item.children) {
                    const activeChild = hasActiveChild(item)
                    const isExpanded = expandedSubmenu === item.id

                    return (
                      <div
                        key={item.id}
                        ref={submenuButtonRef}
                        className="relative flex w-full justify-center"
                      >
                        <button
                          type="button"
                          className={`group flex h-14 w-14 flex-col items-center justify-center rounded-xl transition-all duration-200 ${activeChild ? 'bg-[#202327]' : 'hover:bg-[#202327]'}`}
                          aria-label={`${item.label} submenu`}
                          onMouseEnter={() => handleSubmenuEnter(item.id)}
                          onMouseLeave={handleSubmenuLeave}
                          onFocus={() => handleSubmenuEnter(item.id)}
                          onBlur={handleSubmenuLeave}
                        >
                          <div className="flex items-center justify-center">
                            <Icon
                              className={`
                                size-5 transition-colors duration-150
                                ${activeChild ? 'text-white' : 'text-[var(--foreground-subtle)] group-hover:text-[var(--foreground-muted)]'}
                              `}
                              strokeWidth={2}
                            />
                          </div>
                          <span
                            className={`
                              mt-1.5 flex max-w-full items-center justify-center gap-0.5 text-center text-[10px] font-medium transition-colors whitespace-normal break-words
                              ${activeChild ? 'text-[var(--foreground)]' : 'text-[var(--foreground-subtle)] group-hover:text-[var(--foreground-muted)]'}
                            `}
                          >
                            {item.label}
                            <ChevronDown className="size-2.5" />
                          </span>
                        </button>

                        {/* Submenu Dropdown */}
                        {isExpanded && submenuButtonRect && (
                          <div
                            className="fixed z-[100]"
                            role="menu"
                            tabIndex={-1}
                            style={{
                              left: submenuButtonRect.right + 8,
                              bottom: window.innerHeight - submenuButtonRect.bottom
                            }}
                            onMouseEnter={() => handleSubmenuEnter(item.id)}
                            onMouseLeave={handleSubmenuLeave}
                            onFocus={() => handleSubmenuEnter(item.id)}
                            onBlur={handleSubmenuLeave}
                          >
                            <div className="bg-[var(--background-elevated)] border border-white/[0.08] rounded-2xl shadow-[var(--shadow-md)] py-2 min-w-[160px]">
                              {item.children.map((child) => {
                                const ChildIcon = child.icon
                                const childActive = child.href ? isActive(child.href) : false

                                return (
                                  <Link
                                    key={child.id}
                                    href={child.href || '#'}
                                    className={`
                                      flex items-center gap-3 px-3 py-2 transition-colors duration-150
                                      ${childActive
                                        ? 'bg-white/[0.08] text-white'
                                        : 'text-[var(--foreground-subtle)] hover:bg-white/[0.05] hover:text-white'
                                      }
                                    `}
                                    onClick={() => setMobileMenuOpen(false)}
                                  >
                                    <ChildIcon className="size-4 shrink-0" strokeWidth={2} />
                                    <span className="text-sm whitespace-nowrap">{child.label}</span>
                                  </Link>
                                )
                              })}
                            </div>
                          </div>
                        )}
                      </div>
                    )
                  }

                  // Regular items with href
                  const isDisabled = item.disabled === true
                  const active = !isDisabled && item.href ? isActive(item.href) : false

                  const labelClasses = `
                    mt-1.5 max-w-full text-center text-[10px] font-medium transition-colors whitespace-normal break-words
                    ${isDisabled ? 'text-gray-500' : active ? 'text-[var(--foreground)]' : 'text-[var(--foreground-subtle)] group-hover:text-[var(--foreground-muted)]'}
                  `

                  const iconContainerClasses = `
                    relative flex items-center justify-center
                    ${isDisabled ? 'rounded-2xl bg-white/[0.03]' : ''}
                  `

                  const iconClasses = `
                    size-5 transition-colors duration-150
                    ${isDisabled
                      ? 'text-gray-500'
                      : active
                        ? 'text-white'
                        : 'text-[var(--foreground-subtle)] group-hover:text-[var(--foreground-muted)]'
                    }
                  `

                  const labelContent = <span className={labelClasses}>{item.label}</span>

                  const badgeOverlay = item.badge ? (
                    <span className="absolute inset-0 flex items-center justify-center pointer-events-none">
                      <Badge
                        variant="outline"
                        size="sm"
                        className="text-[8px] px-1.5 py-0 leading-3 !border-gray-400 !text-gray-700 !bg-gray-400"
                      >
                        {item.badge}
                      </Badge>
                    </span>
                  ) : null

                  if (isDisabled) {
                    return (
                      <div
                        key={item.id}
                         className="flex h-14 w-14 flex-col items-center justify-center rounded-xl cursor-default"
                      >
                        <div className={iconContainerClasses}>
                          <Icon className={iconClasses} strokeWidth={2} />
                          {badgeOverlay}
                        </div>
                        {labelContent}
                      </div>
                    )
                  }

                  const unreadCount = item.id === 'inbox' ? (inbox_unread_count || 0) : 0

                  return (
                    <Link
                      key={item.id}
                      href={item.href || '#'}
                      className={`group flex h-14 w-14 flex-col items-center justify-center rounded-xl transition-all duration-200 ${active ? 'bg-[#202327]' : 'hover:bg-[#202327]'}`}
                      onClick={() => setMobileMenuOpen(false)}
                    >
                      <div className={iconContainerClasses}>
                        <Icon className={iconClasses} strokeWidth={2} />
                        {badgeOverlay}
                        {unreadCount > 0 && (
                          <span className="absolute -top-1.5 -right-3 flex h-[18px] min-w-[18px] items-center justify-center rounded-full bg-[var(--accent)] px-1 text-[10px] font-bold leading-none text-black">
                            {unreadCount > 99 ? '99+' : unreadCount}
                          </span>
                        )}
                      </div>
                      {labelContent}
                    </Link>
                  )
                })}

                {/* Overflow "..." Button */}
                {overflowItems.length > 0 && (
                  <div
                    ref={moreButtonRef}
                    className="relative flex w-full justify-center"
                  >
                    <button
                      type="button"
                      className={`group flex h-14 w-14 flex-col items-center justify-center rounded-xl transition-all duration-200 ${hasActiveOverflowItem ? 'bg-[#202327]' : 'hover:bg-[#202327]'}`}
                      aria-label="More navigation items"
                      onMouseEnter={handleOverflowEnter}
                      onMouseLeave={handleOverflowLeave}
                      onFocus={handleOverflowEnter}
                      onBlur={handleOverflowLeave}
                    >
                      <div className="flex items-center justify-center">
                        <MoreHorizontal
                          className={`
                            size-5 transition-colors duration-150
                             ${hasActiveOverflowItem ? 'text-white' : 'text-[var(--foreground-subtle)] group-hover:text-[var(--foreground-muted)]'}
                           `}
                          strokeWidth={2}
                        />
                      </div>
                      <span
                        className={`
                          mt-1.5 max-w-full text-center text-[10px] font-medium transition-colors whitespace-normal break-words
                          ${hasActiveOverflowItem ? 'text-[var(--foreground)]' : 'text-[var(--foreground-subtle)] group-hover:text-[var(--foreground-muted)]'}
                        `}
                      >
                        More
                      </span>
                    </button>

                    {/* Overflow Dropdown - fixed positioning, bottom-aligned with More button */}
                    {overflowHovered && moreButtonRect && (
                      <div
                        className="fixed z-[100]"
                        role="menu"
                        tabIndex={-1}
                        style={{
                          left: moreButtonRect.right + 8,
                          bottom: window.innerHeight - moreButtonRect.bottom
                        }}
                        onMouseEnter={handleOverflowEnter}
                        onMouseLeave={handleOverflowLeave}
                        onFocus={handleOverflowEnter}
                        onBlur={handleOverflowLeave}
                      >
                        <div className="bg-[var(--background-elevated)] border border-white/[0.08] rounded-2xl shadow-[var(--shadow-md)] py-2 min-w-[160px]">
                          {overflowItems.map((item) => {
                            const Icon = item.icon

                            // Handle items with children - flatten into the overflow menu
                            if (item.children) {
                              return (
                                <div key={item.id}>
                                  <div className="px-3 py-1.5 text-xs font-medium text-gray-500 uppercase tracking-wide">
                                    {item.label}
                                  </div>
                                  {item.children.map((child) => {
                                    const ChildIcon = child.icon
                                    const childActive = child.href ? isActive(child.href) : false

                                    return (
                                      <Link
                                        key={child.id}
                                        href={child.href || '#'}
                                        className={`
                                          flex items-center gap-3 px-3 py-2 transition-colors duration-150
                                          ${childActive
                                            ? 'bg-white/[0.08] text-white'
                                            : 'text-[var(--foreground-subtle)] hover:bg-white/[0.05] hover:text-white'
                                          }
                                        `}
                                        onClick={() => setMobileMenuOpen(false)}
                                      >
                                        <ChildIcon className="size-4 shrink-0" strokeWidth={2} />
                                        <span className="text-sm whitespace-nowrap">{child.label}</span>
                                      </Link>
                                    )
                                  })}
                                </div>
                              )
                            }

                            const isDisabled = item.disabled === true
                            const active = !isDisabled && item.href ? isActive(item.href) : false
                            const labelContent = (
                              <span className="text-sm whitespace-nowrap flex items-center gap-2">
                                {item.label}
                                {item.badge && (
                                  <Badge
                                    variant="outline"
                                    size="sm"
                                    className="text-[8px] px-1.5 py-0 leading-3 !border-gray-400 !text-gray-700 !bg-gray-400"
                                  >
                                    {item.badge}
                                  </Badge>
                                )}
                              </span>
                            )

                            if (isDisabled) {
                              return (
                                <div
                                  key={item.id}
                                   className="flex items-center gap-3 px-3 py-2 text-gray-500 cursor-default"
                                >
                                  <Icon className="size-4 shrink-0" strokeWidth={2} />
                                  {labelContent}
                                </div>
                              )
                            }

                            return (
                              <Link
                                key={item.id}
                                href={item.href || '#'}
                                className={`
                                  flex items-center gap-3 px-3 py-2 transition-colors duration-150
                                  ${active
                                    ? 'bg-white/[0.08] text-white'
                                    : 'text-[var(--foreground-subtle)] hover:bg-white/[0.05] hover:text-white'
                                  }
                                `}
                                onClick={() => setMobileMenuOpen(false)}
                              >
                                <Icon className="size-4 shrink-0" strokeWidth={2} />
                                {labelContent}
                              </Link>
                            )
                          })}
                        </div>
                      </div>
                    )}
                  </div>
                )}
            </nav>
          </div>

          <div className="flex w-full shrink-0 flex-col items-center">
            {!isAdmin && (
              <div className="group relative mb-4 flex w-full justify-center">
                <Link
                  href={settingsItem.href}
                  className={`group flex h-14 w-14 flex-col items-center justify-center rounded-xl transition-all duration-200 ${settingsActive ? 'bg-[#202327]' : 'hover:bg-[#202327]'}`}
                  aria-label={settingsItem.label}
                  title={settingsItem.label}
                >
                  <div className="flex items-center justify-center">
                    <SettingsIcon
                      className={
                        `size-5 transition-colors duration-150 ` +
                        `${settingsActive ? 'text-white' : 'text-[var(--foreground-subtle)] group-hover:text-[var(--foreground-muted)]'}`
                      }
                      strokeWidth={2}
                    />
                  </div>
                  <span className={`mt-1.5 max-w-full text-center text-[10px] font-medium whitespace-normal break-words ${settingsActive ? 'text-[var(--foreground)]' : 'text-[var(--foreground-subtle)] group-hover:text-[var(--foreground-muted)]'}`}>
                    {settingsItem.label}
                  </span>
                </Link>
              </div>
            )}
            {/* User Avatar with Dropdown */}
            <div className="relative group flex flex-col items-center">
              <button
                type="button"
                className="flex size-10 items-center justify-center overflow-hidden rounded-full border border-white/[0.08] bg-white/[0.05] transition-colors duration-150 hover:border-white/20"
                title={account.full_name}
              >
                <span className="text-xs font-medium text-white">
                  {account.first_name?.[0]}{account.last_name?.[0]}
                </span>
              </button>
              {showWorkspaceLabel && currentOrganization && (
                <div
                  className="mt-1 max-w-16 truncate text-center text-[10px] font-medium leading-3 text-[var(--foreground-subtle)]"
                  title={currentOrganization.name}
                >
                  {currentOrganization.name}
                </div>
              )}

              {/* Dropdown on hover - left-aligned with avatar */}
              <div className="absolute bottom-full left-0 mb-2 w-48 opacity-0 invisible group-hover:opacity-100 group-hover:visible transition-all duration-150 z-50">
                <div className="rounded-2xl border border-white/[0.08] bg-[var(--background-elevated)] p-3 shadow-[var(--shadow-md)]">
                  <div className="text-sm font-medium text-white mb-1 truncate">
                    {account.full_name}
                  </div>
                  <div className="text-xs text-gray-500 mb-3 truncate">
                    {account.email}
                  </div>
                  {currentOrganization && !isAdmin && (
                    <div className="mb-3">
                      <div className="mb-1 text-[10px] font-medium uppercase tracking-wide text-[var(--foreground-subtle)]">
                        {t('workspaces.switcher.label')}
                      </div>
                      {switchableOrganizations.length > 1 ? (
                        <div className="space-y-1">
                          {switchableOrganizations.map((switchableOrganization) => {
                            const selected = switchableOrganization.id === currentOrganization.id

                            return (
                              <button
                                key={switchableOrganization.id}
                                type="button"
                                className={`flex w-full items-center gap-2 rounded-lg px-2 py-1.5 text-left text-xs transition-colors ${selected
                                  ? 'bg-white/[0.08] text-white'
                                  : 'text-[var(--foreground-subtle)] hover:bg-white/[0.05] hover:text-white'
                                }`}
                                onClick={() => switchWorkspace(switchableOrganization.id)}
                              >
                                <Building2 className="size-3.5 shrink-0" strokeWidth={2} />
                                <span className="truncate">{switchableOrganization.name}</span>
                              </button>
                            )
                          })}
                        </div>
                      ) : (
                        <div className="truncate text-xs text-[var(--foreground-subtle)]">
                          {currentOrganization.name}
                        </div>
                      )}
                    </div>
                  )}
                  {isAdmin && (
                    <div className="mb-3">
                      <span className="px-2 py-0.5 text-[10px] font-semibold text-[var(--accent)] bg-[var(--accent)]/10 rounded-full border border-[var(--accent)]/20">
                        {t('navigation.admin_badge')}
                      </span>
                    </div>
                  )}
                  {/* Action items - consistent styling */}
                  <div className="border-t border-white/10 pt-2 space-y-1">
                    <LanguageSelector currentLocale={locale} variant="sidebar" />
                    <Link
                      href="/logout"
                      method="post"
                      as="button"
                       className="w-full flex items-center gap-3 rounded-lg px-2 py-2 text-sm text-[var(--foreground-subtle)] transition-colors duration-150 hover:bg-white/[0.05] hover:text-white"
                     >
                      <LogOut className="size-4" />
                      {t('navigation.logout')}
                    </Link>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </aside>

      {/* Main Content Area - ml-20 to account for fixed sidebar width, z-0 to stay below sidebar dropdown */}
      <div className="relative z-0 ml-0 flex min-h-0 min-w-0 flex-1 flex-col pb-4 pr-4 pt-4 lg:ml-20">
        {/* Main Content Container with rounded corners */}
        <div className="flex min-h-0 flex-1 flex-col overflow-hidden rounded-[30px] border border-white/[0.06] bg-[var(--background)] shadow-[var(--shadow-lg)]">
          {/* Page Header */}
          <div className={`shrink-0 z-30 bg-[var(--background)]/94 backdrop-blur-sm ${hideHeader ? 'lg:hidden' : ''}`}>
            <header className={`${stickyNavigation ? '' : 'border-b border-white/10'}`}>
              <div className="flex items-center justify-between px-6 py-4 lg:px-8">
                {/* Mobile Menu Button */}
                <button
                  type="button"
                  className="lg:hidden -ml-2 p-2 rounded-lg hover:bg-white/10 transition-colors"
                  onClick={() => setMobileMenuOpen(!mobileMenuOpen)}
                >
                  {mobileMenuOpen ? (
                    <X className="size-5 text-white" />
                  ) : (
                    <Menu className="size-5 text-white" />
                  )}
                </button>

                {/* Title */}
                <div className="flex-1 lg:flex-none">
                  {backLink && (
                    <Link
                      href={backLink}
                      className="inline-flex items-center gap-1.5 text-xs text-[var(--foreground-muted)] hover:text-white transition-colors mb-1"
                    >
                      <ArrowLeft className="h-3.5 w-3.5" />
                      {backLinkText || 'Back'}
                    </Link>
                  )}
                  <div className="flex flex-col gap-1 lg:min-w-[280px]">
                    <h1 className="text-[28px] font-semibold tracking-[-0.03em] text-white">
                      {title}
                    </h1>
                    {subtitle && (
                      <p className="max-w-2xl text-sm leading-6 text-[var(--foreground-muted)]">
                        {subtitle}
                      </p>
                    )}
                  </div>
                </div>

                {/* Header Actions */}
                {headerActions && (
                  <div className="flex items-center gap-3">
                    {headerActions}
                  </div>
                )}
              </div>
            </header>

            {stickyNavigation && (
              <div className="relative px-6 lg:px-8">
                {stickyNavigation}
                <div className="absolute bottom-0 inset-x-0 h-px bg-white/10 pointer-events-none" aria-hidden="true" />
              </div>
            )}
          </div>



          {/* Scrollable Content Area */}
          <main className={`flex-1 min-h-0 ${fullBleed ? 'overflow-hidden flex flex-col' : 'overflow-y-auto p-6 lg:p-8'} ${mainClassName}`}>
            {/* Flash Messages */}
            {flash?.notice && !suppress_flash && (
              <div className={`mb-6 rounded-lg bg-[var(--success-muted)] border border-[var(--success)]/20 p-4 ${fullBleed ? 'mx-6 mt-6 lg:mx-10 lg:mt-10' : ''}`}>
                <div className="flex items-center">
                  <div className="flex-shrink-0">
                    <CheckCircle2 className="h-5 w-5 text-[var(--success)]" />
                  </div>
                  <div className="ml-3">
                    <p className="text-sm font-medium text-[var(--success)]">{flash.notice}</p>
                  </div>
                </div>
              </div>
            )}
            {flash?.alert && !suppress_flash && (
              <div className={`mb-6 rounded-lg bg-[var(--error-muted)] border border-[var(--error)]/20 p-4 ${fullBleed ? 'mx-6 mt-6 lg:mx-10 lg:mt-10' : ''}`}>
                <div className="flex items-center">
                  <div className="flex-shrink-0">
                    <XCircle className="h-5 w-5 text-[var(--error)]" />
                  </div>
                  <div className="ml-3">
                    <p className="text-sm font-medium text-[var(--error)]">{flash.alert}</p>
                  </div>
                </div>
              </div>
            )}

            {/* Page Content */}
            {children}
          </main>
        </div>
      </div>
    </div>
  )
}
