import * as React from 'react'
import { Plus } from 'lucide-react'

/**
 * ListSection component for grouping list items with a title
 * Used in SlideOver panels for playbook details (personas, use cases, references, etc.)
 *
 * Based on Figma design node 201:3266 (Personas section in SlideOver)
 *
 * Design specs:
 * - Section container: flex column, gap 12px between title and items
 * - Title: Geist Regular, 14px, neutral-400 (#a3a3a3)
 * - Items container: flex column, gap 12px (compact) or 16px (spaced)
 * - Divider: 1px height, rgba(255,255,255,0.1), margin-bottom 24px
 * - Add button (node 201:3304): height 32px, bg rgba(255,255,255,0.05),
 *   border 1px solid rgba(255,255,255,0.15), rounded 8px, px-3 py-2,
 *   Plus icon 16px #fafafa, text 12px medium #fafafa, gap 8px
 */

// ============================================================================
// ListSection
// ============================================================================

export interface ListSectionProps {
  /** Section title */
  title: string
  /** Section children (list items) */
  children: React.ReactNode
  /** Show divider above section */
  showDivider?: boolean
  /** Optional add button handler */
  onAdd?: () => void
  /** Add button label (default: "Add") */
  addLabel?: string
  /** Gap between items: 'compact' (12px) or 'spaced' (16px) */
  itemGap?: 'compact' | 'spaced'
  /** Additional CSS classes */
  className?: string
}

/**
 * ListSection component for organizing list items with a title and optional add button
 *
 * @example
 * ```tsx
 * <ListSection title="Personas" onAdd={() => console.log('Add persona')}>
 *   <ListItem onClick={() => {}}>Production Manager</ListItem>
 *   <ListItem onClick={() => {}}>Maintenance Manager</ListItem>
 * </ListSection>
 *
 * <ListSection title="Use Cases" showDivider itemGap="spaced">
 *   <ListItem onClick={() => {}}>E-Mobility Production</ListItem>
 * </ListSection>
 * ```
 */
export function ListSection({
  title,
  children,
  showDivider = false,
  onAdd,
  addLabel = 'Add',
  itemGap = 'compact',
  className = '',
}: ListSectionProps) {
  // Section container styles
  const sectionClasses = [
    'flex',
    'flex-col',
    'gap-3', // 12px gap between title and items container
    'w-full',
    className,
  ]
    .filter(Boolean)
    .join(' ')

  // Divider styles - appears above the section
  const dividerClasses = [
    'h-px',
    'w-full',
    'bg-[rgba(255,255,255,0.1)]',
    'mb-6', // 24px margin-bottom before section
  ].join(' ')

  // Title row styles - contains title and optional add button
  const titleRowClasses = [
    'flex',
    'items-center',
    'justify-between',
    'w-full',
  ].join(' ')

  // Title text styles
  const titleClasses = [
    'font-normal',
    'text-sm', // 14px
    'text-neutral-400', // #a3a3a3
    'leading-normal',
  ].join(' ')

  // Items container styles
  const itemsContainerClasses = [
    'flex',
    'flex-col',
    'w-full',
    itemGap === 'compact' ? 'gap-3' : 'gap-4', // 12px or 16px
  ].join(' ')

  // Add button styles (based on Figma node 201:3304)
  const addButtonClasses = [
    'inline-flex',
    'items-center',
    'justify-center',
    'gap-2', // 8px gap between icon and text
    'h-8', // 32px height
    'px-3',
    'py-2',
    'bg-[rgba(255,255,255,0.05)]',
    'border',
    'border-[rgba(255,255,255,0.15)]',
    'rounded-lg', // 8px
    'shadow-[0px_1px_2px_rgba(0,0,0,0.05)]',
    'text-xs', // 12px
    'font-medium',
    'text-[#fafafa]',
    'transition-colors',
    'duration-150',
    'hover:bg-[rgba(255,255,255,0.1)]',
    'focus:outline-none',
    'focus-visible:shadow-[0_0_0_2px_var(--ring-offset),0_0_0_4px_var(--ring)]',
    'active:scale-[0.98]',
    'cursor-pointer',
  ].join(' ')

  return (
    <>
      {showDivider && <div className={dividerClasses} />}
      <div className={sectionClasses}>
        <div className={titleRowClasses}>
          <span className={titleClasses}>{title}</span>
          {onAdd && (
            <button
              type="button"
              className={addButtonClasses}
              onClick={onAdd}
              aria-label={`${addLabel} ${title.toLowerCase()}`}
            >
              <Plus className="h-4 w-4 shrink-0" aria-hidden="true" />
              <span>{addLabel}</span>
            </button>
          )}
        </div>
        <div className={itemsContainerClasses}>{children}</div>
      </div>
    </>
  )
}

export default ListSection
