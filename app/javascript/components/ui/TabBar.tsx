/**
 * TabBar component for filtering table data
 * Based on Figma node 257:10401
 *
 * Design specs from Figma:
 * - Container: flex, gap-2 (8px)
 * - Active tab: white bg, black text, Geist Medium 13px, rounded-lg
 * - Active count badge: black/10 bg, 18px size, neutral-700 text
 * - Inactive tab: transparent bg, text #99a1af, Geist Regular 13px
 * - Inactive count badge: white/10 bg, 18px size, #939393 text
 */

export interface Tab {
  /** Unique identifier for the tab */
  id: string
  /** Display label for the tab */
  label: string
  /** Optional count to display in badge */
  count?: number
  /** Optional Lucide icon component */
  icon?: React.ComponentType<{ className?: string; strokeWidth?: number }>
}

export interface TabBarProps {
  /** Array of tab configurations */
  tabs: Tab[]
  /** ID of the currently active tab */
  activeTab: string
  /** Callback when tab is changed */
  onTabChange: (tabId: string) => void
  /** Additional CSS classes */
  className?: string
}

/**
 * Individual tab button component
 */
interface TabButtonProps {
  tab: Tab
  isActive: boolean
  onClick: () => void
}

function TabButton({ tab, isActive, onClick }: TabButtonProps) {
  // Base classes for all tabs
  const baseClasses = [
    'inline-flex',
    'items-center',
    'justify-center',
    'gap-1.5',
    'rounded-lg', // 8px
    'capitalize',
    'transition-all',
    'duration-150',
    'whitespace-nowrap',
    'cursor-pointer',
    // Focus state
    'focus:outline-none',
    'focus-visible:shadow-[0_0_0_2px_var(--ring-offset),0_0_0_4px_var(--ring)]',
  ].join(' ')

  // Active tab styles from Figma
  const activeClasses = [
    'bg-white/[0.08]',
    'px-[15px]',
    'py-2', // 8px
    'text-white',
    'font-medium', // Geist Medium
    'text-[13px]',
    'leading-normal',
    'border',
    'border-white/[0.08]',
  ].join(' ')

  // Inactive tab styles from Figma
  const inactiveClasses = [
    'bg-transparent',
    'px-[17px]',
    'py-2', // 8px
    'text-[var(--foreground-subtle)]',
    'font-normal', // Geist Regular
    'text-[13px]',
    'leading-normal',
    'tracking-[-0.08px]', // -0.0762px rounded
    // Hover state (invented - not in Figma)
    'hover:bg-white/[0.04]',
    'hover:text-[var(--foreground-muted)]',
  ].join(' ')

  // Count badge base styles
  const countBaseClasses = [
    'flex',
    'items-center',
    'justify-center',
    'size-[18px]', // 18x18px
    'rounded-full', // 999px
    'shrink-0',
  ].join(' ')

  // Active count badge: black/10 bg, neutral-700 text, 12px
  const activeCountClasses = [
    'bg-white/[0.08]',
    'text-white/85',
    'text-xs', // 12px
    'font-normal',
    'leading-normal',
  ].join(' ')

  // Inactive count badge: white/10 bg, #939393 text, 10px
  const inactiveCountClasses = [
    'bg-white/[0.05]',
    'text-[var(--foreground-subtle)]',
    'text-[10px]',
    'font-normal',
    'leading-normal',
  ].join(' ')

  const tabClasses = `${baseClasses} ${isActive ? activeClasses : inactiveClasses}`
  const countClasses = `${countBaseClasses} ${isActive ? activeCountClasses : inactiveCountClasses}`

  return (
    <button
      type="button"
      onClick={onClick}
      className={tabClasses}
      aria-selected={isActive}
      role="tab"
    >
      {tab.icon && <tab.icon className="size-3.5" strokeWidth={2} />}
      <span>{tab.label}</span>
      {tab.count !== undefined && (
        <span className={countClasses}>
          {tab.count}
        </span>
      )}
    </button>
  )
}

/**
 * TabBar component for filtering data
 * Renders a row of tab buttons with optional count badges
 */
export function TabBar({
  tabs,
  activeTab,
  onTabChange,
  className = '',
}: TabBarProps) {
  // Container styles from Figma
  const containerClasses = [
    'flex',
    'items-start',
    'gap-2', // 8px gap between tabs
  ].join(' ')

  return (
    <div
      className={`${containerClasses} ${className}`}
      role="tablist"
      aria-label="Filter tabs"
    >
      {tabs.map((tab) => (
        <TabButton
          key={tab.id}
          tab={tab}
          isActive={tab.id === activeTab}
          onClick={() => onTabChange(tab.id)}
        />
      ))}
    </div>
  )
}

export default TabBar
