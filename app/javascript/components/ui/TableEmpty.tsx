import * as React from 'react'

/**
 * TableEmpty component for displaying empty state in tables
 * Shows a centered message with optional icon when there's no data
 *
 * Design specs:
 * - Centered text and optional icon
 * - Vertical padding: py-12 (48px)
 * - Text color: neutral-400 (#a3a3a3)
 * - Font: 14px Geist Regular
 */

export interface TableEmptyProps {
  /** Number of columns to span (required) */
  colSpan: number
  /** Empty state message (defaults to "No data available") */
  message?: string
  /** Optional icon to display above the message */
  icon?: React.ReactNode
  /** Additional CSS classes */
  className?: string
}

/**
 * Empty state component for tables
 * Renders a full-width row with centered message
 *
 * @example
 * <Table>
 *   <TableHeader>...</TableHeader>
 *   <TableBody>
 *     <TableEmpty colSpan={5} message="No leads found" />
 *   </TableBody>
 * </Table>
 */
export function TableEmpty({
  colSpan,
  message = 'No data available',
  icon,
  className = '',
}: TableEmptyProps) {
  const baseClasses = [
    'py-12',
    'text-center',
    'text-sm',
    'text-neutral-400',
  ].join(' ')

  const allClasses = [baseClasses, className].filter(Boolean).join(' ')

  return (
    <tr>
      <td colSpan={colSpan} className={allClasses}>
        <div className="flex flex-col items-center justify-center gap-3">
          {icon && (
            <div className="text-neutral-500">
              {icon}
            </div>
          )}
          <span>{message}</span>
        </div>
      </td>
    </tr>
  )
}

export default TableEmpty
