import * as React from 'react'
import { ChevronRight, Plus } from 'lucide-react'

/**
 * SlideOverSection - Reusable section component for slide-over content
 * Based on Figma node 201:3266, 201:3280, 201:3294, 201:3306
 *
 * Design specs:
 * - Section container: flex flex-col gap-12px w-full
 * - Title: 14px Geist Regular, text-neutral-400 (#a3a3a3)
 * - Divider: 1px solid rgba(255,255,255,0.1), 24px margin
 * - Items gap: 12px (compact) or 16px (default)
 */

export interface SlideOverSectionProps {
  /** Section title */
  title: string
  /** Section children (typically SlideOverListItem components) */
  children: React.ReactNode
  /** Show divider above section (default: false) */
  showDivider?: boolean
  /** Add button handler (optional) */
  onAdd?: () => void
  /** Add button label (default: "Add") */
  addLabel?: string
  /** Gap between items: 'compact' (12px) or 'default' (16px) */
  itemGap?: 'compact' | 'default'
  /** Additional className for customization */
  className?: string
}

export function SlideOverSection({
  title,
  children,
  showDivider = false,
  onAdd,
  addLabel = 'Add',
  itemGap = 'default',
  className = '',
}: SlideOverSectionProps) {
  const gapClass = itemGap === 'compact' ? 'gap-3' : 'gap-4'

  return (
    <>
      {/* Divider */}
      {showDivider && (
        <div className="h-0 relative w-full shrink-0">
          <div className="absolute left-0 right-0 top-[-1px] h-px bg-[rgba(255,255,255,0.1)]" />
        </div>
      )}

      {/* Section container */}
      <div className={`flex flex-col gap-3 items-start w-full shrink-0 ${className}`}>
        {/* Section title */}
        <div className="flex flex-col items-start w-full">
          <p className="text-sm font-normal text-neutral-400 leading-normal">
            {title}
          </p>
        </div>

        {/* Items container */}
        <div className={`flex flex-col ${gapClass} items-start w-full`}>
          {children}

          {/* Add button */}
          {onAdd && (
            <button
              type="button"
              onClick={onAdd}
              className="
                flex items-center justify-center gap-2
                h-8 px-3 py-2
                bg-[rgba(255,255,255,0.05)]
                border border-[rgba(255,255,255,0.15)]
                rounded-lg
                shadow-[0px_1px_2px_0px_rgba(0,0,0,0.05)]
                hover:bg-[rgba(255,255,255,0.1)]
                transition-colors duration-150
                focus:outline-none focus-visible:ring-2 focus-visible:ring-white/50
              "
            >
              <Plus className="size-4 text-[#fafafa]" />
              <span className="text-xs font-medium text-[#fafafa] leading-4">
                {addLabel}
              </span>
            </button>
          )}
        </div>
      </div>
    </>
  )
}

/**
 * SlideOverListItem - Clickable list item with chevron for slide-over sections
 * Based on Figma node 201:3270, 201:3284, etc.
 *
 * Design specs:
 * - Container: flex items-center justify-between w-full
 * - Text: 14px Geist Medium, white, leading-20px
 * - Chevron: 24px, color #737373
 * - Hover: subtle background highlight
 * - Focus: visible ring
 */

export interface SlideOverListItemProps {
  /** Item label text */
  label: string
  /** Click handler (optional) */
  onClick?: () => void
  /** Show chevron (default: true) */
  showChevron?: boolean
  /** Additional className for customization */
  className?: string
  /** Custom right-side content (replaces chevron if provided) */
  rightContent?: React.ReactNode
}

export function SlideOverListItem({
  label,
  onClick,
  showChevron = true,
  className = '',
  rightContent,
}: SlideOverListItemProps) {
  const isClickable = !!onClick

  const content = (
    <>
      <span className="text-sm font-medium text-white leading-5">
        {label}
      </span>
      {rightContent ? (
        rightContent
      ) : showChevron ? (
        <ChevronRight className="size-6 text-[#737373] shrink-0" />
      ) : null}
    </>
  )

  if (isClickable) {
    return (
      <button
        type="button"
        onClick={onClick}
        className={`
          flex items-center justify-between w-full
          py-1 -mx-1 px-1
          rounded-md
          text-left
          hover:bg-white/5
          transition-colors duration-150
          focus:outline-none focus-visible:ring-2 focus-visible:ring-white/50
          ${className}
        `}
      >
        {content}
      </button>
    )
  }

  return (
    <div
      className={`
        flex items-center justify-between w-full
        ${className}
      `}
    >
      {content}
    </div>
  )
}

/**
 * SlideOverDivider - Standalone divider for use between sections
 * Based on Figma node 201:3279, 201:3293, 201:3305
 *
 * Design specs:
 * - Height: 0px container
 * - Line: 1px solid rgba(255,255,255,0.1)
 */

export function SlideOverDivider() {
  return (
    <div className="h-0 relative w-full shrink-0">
      <div className="absolute left-0 right-0 top-[-1px] h-px bg-[rgba(255,255,255,0.1)]" />
    </div>
  )
}

export default SlideOverSection
