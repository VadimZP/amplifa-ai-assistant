import * as React from 'react'
import { ChevronRight } from 'lucide-react'

/**
 * ListItem - Clickable list item with text and optional chevron icon.
 *
 * Based on Figma node 201:3270.
 *
 * Design specs:
 * - Layout: flex, items-center, justify-between, full width
 * - Text: Geist Medium, 14px (#ffffff), line-height 20px
 * - Chevron: 24px, color #737373 (neutral-500)
 * - Hover: subtle background highlight (bg-white/5)
 * - Focus: visible focus ring for accessibility
 * - Active: subtle scale for press feedback
 */

// ============================================================================
// ListItem
// ============================================================================

export interface ListItemProps {
  /** Item text/label content */
  children: React.ReactNode
  /** Click handler - if provided, item becomes a button */
  onClick?: () => void
  /** Show chevron icon (default: true when onClick provided) */
  showChevron?: boolean
  /** Additional CSS classes */
  className?: string
}

export function ListItem({
  children,
  onClick,
  showChevron,
  className = '',
}: ListItemProps) {
  const isClickable = !!onClick

  // Default showChevron to true when clickable, false otherwise
  const shouldShowChevron = showChevron !== undefined ? showChevron : isClickable

  const content = (
    <>
      <span className="text-sm font-medium text-white leading-5">
        {children}
      </span>
      {shouldShowChevron && (
        <ChevronRight className="h-6 w-6 text-[#737373] shrink-0" />
      )}
    </>
  )

  // Base classes for layout
  const baseClasses = 'flex items-center justify-between w-full'

  // Interactive classes for clickable state
  const interactiveClasses = isClickable
    ? [
        'cursor-pointer',
        'py-1 -mx-1 px-1',
        'rounded-md',
        'hover:bg-white/5',
        'transition-colors duration-150',
        'focus:outline-none',
        'focus-visible:ring-2 focus-visible:ring-white/50',
        'active:scale-[0.99]',
      ].join(' ')
    : ''

  if (isClickable) {
    return (
      <button
        type="button"
        onClick={onClick}
        className={`${baseClasses} ${interactiveClasses} ${className}`.trim()}
      >
        {content}
      </button>
    )
  }

  return (
    <div className={`${baseClasses} ${className}`.trim()}>
      {content}
    </div>
  )
}

export default ListItem
