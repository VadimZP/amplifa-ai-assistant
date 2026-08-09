import * as React from 'react'

/**
 * Table components for displaying tabular data
 * Based on Figma designs from node 257:11149 (Agent page table)
 *
 * Design specs:
 * - Container: bg-neutral-900 (#171717), border 1px solid rgba(255,255,255,0.1), rounded-xl (14px)
 * - Header cells: h-10 (40px), px-6, font-medium 14px, text-white
 * - Body cells: h-[52px], px-6 py-2, font-regular 14px, text-neutral-400 (secondary) or white (primary)
 * - Dividers: 1px solid rgba(255,255,255,0.1) between rows
 */

// ============================================================================
// Table (wrapper)
// ============================================================================

export interface TableProps extends React.HTMLAttributes<HTMLTableElement> {
  /** Additional CSS classes */
  className?: string
  /** Additional wrapper CSS classes */
  containerClassName?: string
  /** Whether the wrapper should handle horizontal scrolling */
  scrollable?: boolean
  /** Table content (TableHeader, TableBody) */
  children: React.ReactNode
}

/**
 * Table wrapper component with dark theme styling
 * Provides rounded container with border
 */
export function Table({
  className = '',
  containerClassName = '',
  scrollable = true,
  children,
  ...props
}: TableProps) {
  const baseClasses = [
    'w-full',
    'min-w-max', // Allow table to exceed container width for horizontal scroll
  ].join(' ')

  const allClasses = [baseClasses, className].filter(Boolean).join(' ')
  const containerClasses = [
    scrollable ? 'overflow-x-auto' : 'overflow-visible',
    'rounded-[24px]',
    'bg-[var(--card)]',
    'border',
    'border-[var(--border)]',
    'shadow-[var(--shadow-sm)]',
    containerClassName,
  ]
    .filter(Boolean)
    .join(' ')

  return (
    <div className={containerClasses}>
      <table className={allClasses} style={{ borderCollapse: 'separate', borderSpacing: 0 }} {...props}>
        {children}
      </table>
    </div>
  )
}

// ============================================================================
// TableHeader
// ============================================================================

export interface TableHeaderProps extends React.HTMLAttributes<HTMLTableSectionElement> {
  /** Additional CSS classes */
  className?: string
  /** Header content (TableRow with TableHead cells) */
  children: React.ReactNode
}

/**
 * Table header section
 * Contains header rows with TableHead cells
 */
export function TableHeader({ className = '', children, ...props }: TableHeaderProps) {
  const allClasses = [className].filter(Boolean).join(' ')

  return (
    <thead className={allClasses || undefined} {...props}>
      {children}
    </thead>
  )
}

// ============================================================================
// TableBody
// ============================================================================

export interface TableBodyProps extends React.HTMLAttributes<HTMLTableSectionElement> {
  /** Additional CSS classes */
  className?: string
  /** Body content (TableRow with TableCell) */
  children: React.ReactNode
}

/**
 * Table body section
 * Contains data rows with TableCell cells
 */
export function TableBody({ className = '', children, ...props }: TableBodyProps) {
  const allClasses = [className].filter(Boolean).join(' ')

  return (
    <tbody className={allClasses || undefined} {...props}>
      {children}
    </tbody>
  )
}

// ============================================================================
// TableRow
// ============================================================================

export interface TableRowProps extends React.HTMLAttributes<HTMLTableRowElement> {
  /** Additional CSS classes */
  className?: string
  /** Row content (TableHead or TableCell) */
  children: React.ReactNode
  /** Click handler for interactive rows */
  onClick?: React.MouseEventHandler<HTMLTableRowElement>
}

/**
 * Table row component
 * Supports optional hover states for interactive rows
 */
export function TableRow({ className = '', children, onClick, ...props }: TableRowProps) {
  const baseClasses = [
    'group', // Enable group-hover for sticky cells
    'transition-colors',
    'duration-150',
  ].join(' ')

  // Add hover state if row is clickable
  const interactiveClasses = onClick
    ? 'cursor-pointer hover:bg-white/[0.03]'
    : ''

  const allClasses = [baseClasses, interactiveClasses, className]
    .filter(Boolean)
    .join(' ')

  return (
    <tr className={allClasses} onClick={onClick} {...props}>
      {children}
    </tr>
  )
}

// ============================================================================
// TableHead (header cell)
// ============================================================================

export interface TableHeadProps extends React.ThHTMLAttributes<HTMLTableCellElement> {
  /** Additional CSS classes */
  className?: string
  /** Header cell content */
  children: React.ReactNode
  /** Make this column sticky on the right edge (for action columns) */
  sticky?: boolean
}

/**
 * Table header cell
 * Styled with medium font weight and white text
 *
 * Specs from Figma:
 * - Height: 40px
 * - Padding: px-6 (24px horizontal)
 * - Border-bottom: 1px solid var(--border)
 * - Font: Geist Medium, 14px, white
 * - Line-height: 20px
 */
export function TableHead({ className = '', children, sticky = false, ...props }: TableHeadProps) {
  const baseClasses = [
    'h-11',
    'px-6',
    'text-left',
    'text-sm',
    'font-medium',
    'text-[var(--foreground-muted)]',
    'leading-5',
    'border-b',
    'border-[var(--border)]',
    'whitespace-nowrap',
  ].join(' ')

  // Sticky classes for action columns - z-10 ensures it appears above non-sticky headers when scrolling
  const stickyClasses = sticky
    ? 'sticky right-0 z-10 bg-[var(--card)] shadow-[-8px_0_12px_-4px_rgba(0,0,0,0.3)]'
    : ''

  const allClasses = [baseClasses, stickyClasses, className].filter(Boolean).join(' ')

  return (
    <th className={allClasses} {...props}>
      {children}
    </th>
  )
}

// ============================================================================
// TableCell (body cell)
// ============================================================================

export interface TableCellProps extends React.TdHTMLAttributes<HTMLTableCellElement> {
  /** Additional CSS classes */
  className?: string
  /** Cell content */
  children: React.ReactNode
  /**
   * Text color variant
   * - 'primary': White text (for Name columns or important data)
   * - 'secondary': Neutral-400 text (for dates, descriptions, etc.)
   */
  variant?: 'primary' | 'secondary'
  /** Make this column sticky on the right edge (for action columns) */
  sticky?: boolean
}

/**
 * Get variant-specific classes for cell text color
 */
function getCellVariantClasses(variant: TableCellProps['variant']): string {
  switch (variant) {
    case 'primary':
      return 'text-[var(--foreground)]'
    case 'secondary':
      return 'text-[var(--foreground-muted)]'
    default:
      return 'text-[var(--foreground-muted)]'
  }
}

/**
 * Table body cell
 * Supports primary (white) and secondary (neutral-300) text variants
 *
 * Specs from Figma:
 * - Height: 52px
 * - Padding: px-6 py-2 (24px horizontal, 8px vertical)
 * - Border-bottom: 1px solid var(--border)
 * - Font: Geist Regular, 14px
 * - Line-height: 20px
 * - Overflow: ellipsis, nowrap
 */
export function TableCell({
  className = '',
  children,
  variant = 'secondary',
  sticky = false,
  ...props
}: TableCellProps) {
  const baseClasses = [
    'h-[60px]',
    'px-6',
    'py-2',
    'text-sm',
    'font-normal',
    'leading-5',
    'border-b',
    'border-[var(--border)]',
    'whitespace-nowrap',
    'overflow-hidden',
    'text-ellipsis',
    'align-middle',
  ].join(' ')

  const variantClasses = getCellVariantClasses(variant)

  // Sticky classes for action columns - z-10 ensures it appears above other cells when scrolling
  const stickyClasses = sticky
    ? 'sticky right-0 z-10 bg-[var(--card)] group-hover:bg-[var(--card)] shadow-[-8px_0_12px_-4px_rgba(0,0,0,0.3)]'
    : ''

  const allClasses = [baseClasses, variantClasses, stickyClasses, className]
    .filter(Boolean)
    .join(' ')

  return (
    <td className={allClasses} {...props}>
      {children}
    </td>
  )
}

export default Table
