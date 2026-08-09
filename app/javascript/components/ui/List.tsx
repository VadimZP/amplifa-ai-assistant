import * as React from 'react'

/**
 * List component for displaying expandable sections
 * Used in SlideOver panels for playbook details (personas, use cases, references, etc.)
 *
 * Based on Figma design node 201:3253 (SlideOver list sections)
 *
 * Design specs:
 * - Container: flex column, gap 24px between sections
 * - Full width within parent container
 */

// ============================================================================
// List
// ============================================================================

export interface ListProps {
  /** Additional CSS classes */
  className?: string
  /** List content (ListSection components) */
  children: React.ReactNode
}

/**
 * List container component for organizing ListSection components
 *
 * Provides a flex column layout with consistent spacing between sections.
 *
 * @example
 * ```tsx
 * <List>
 *   <ListSection title="Personas">
 *     <ListItem onClick={() => {}}>Production Manager</ListItem>
 *     <ListItem onClick={() => {}}>Maintenance Manager</ListItem>
 *   </ListSection>
 *   <ListSection title="Use Cases" showDivider>
 *     <ListItem onClick={() => {}}>E-Mobility Production</ListItem>
 *   </ListSection>
 * </List>
 * ```
 */
export function List({ className = '', children }: ListProps) {
  const baseClasses = [
    'flex',
    'flex-col',
    'gap-6', // 24px between sections
    'items-start',
    'w-full',
  ].join(' ')

  const allClasses = [baseClasses, className].filter(Boolean).join(' ')

  return <div className={allClasses}>{children}</div>
}

export default List
