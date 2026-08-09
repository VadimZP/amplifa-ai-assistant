import * as React from 'react'

/**
 * Badge component for status indicators
 * Based on Figma node 195:5068
 *
 * Specs:
 * - Background: #27272a (zinc-800) for default/draft
 * - Border Radius: 8px (rounded-md)
 * - Padding: 2px 8px
 * - Font: 12px Geist SemiBold
 * - Line Height: 16px
 */

export interface BadgeProps extends React.HTMLAttributes<HTMLSpanElement> {
  /** Visual variant */
  variant?:
    | 'default'
    | 'draft'
    | 'approved'
    | 'success'
    | 'warning'
    | 'error'
    | 'bounced'   // Orange - for bounced emails
    // Role variants (Phase 5)
    | 'info'      // Blue - for customer_admin role
    | 'purple'    // Purple - for amplifa_admin role
    // Table status variants (Phase 4)
    | 'not-started'
    | 'in-sequence'
    | 'replied'
    | 'meeting-set'
    // Outline/transparent variants (Playbook detail views)
    | 'outline'   // White outline, transparent bg
    | 'cyan'      // Cyan badge for persona level
  /** Badge size */
  size?: 'default' | 'sm'
}

/**
 * Get variant-specific classes
 */
function getVariantClasses(variant: BadgeProps['variant']): string {
  switch (variant) {
    case 'default':
    case 'draft':
      return 'bg-white/[0.06] text-[var(--foreground-muted)] border-white/[0.08]'
    case 'approved':
      return 'bg-[var(--success)]/12 text-[#86efac] border-[var(--success)]/20'
    case 'success':
      return 'bg-[var(--success-muted)] text-[var(--success)] border-[var(--success)]/15'
    case 'warning':
      return 'bg-[var(--warning-muted)] text-[var(--warning)] border-[var(--warning)]/15'
    case 'error':
      return 'bg-[var(--error-muted)] text-[var(--error)] border-[var(--error)]/15'
    case 'bounced':
      return 'bg-orange-500/14 text-orange-300 border-orange-500/20'
    // Role variants (Phase 5)
    case 'info':
      return 'bg-[var(--accent)]/14 text-[var(--accent)] border-[var(--accent)]/20'
    case 'purple':
      return 'bg-purple-500/18 text-purple-300 border-purple-500/20'
    // Table status variants (Phase 4) - based on Figma Agent table
    case 'not-started':
      return 'bg-white/[0.04] text-[var(--foreground-subtle)] border-white/[0.08]'
    case 'in-sequence':
      return 'bg-[var(--accent)]/14 text-[var(--accent)] border-[var(--accent)]/20'
    case 'replied':
      return 'bg-green-500/14 text-green-300 border-green-500/18'
    case 'meeting-set':
      return 'bg-green-500/14 text-green-300 border-green-500/18'
    // Outline/transparent variants (Playbook detail views)
    case 'outline':
      return 'bg-transparent text-white border-[rgba(255,255,255,0.15)]'
    case 'cyan':
      return 'bg-cyan-500/16 text-cyan-300 border-cyan-500/20'
    default:
      return 'bg-white/[0.06] text-[var(--foreground)] border-white/[0.08]'
  }
}

/**
 * Get size-specific classes
 */
function getSizeClasses(size: BadgeProps['size']): string {
  switch (size) {
    case 'sm':
      return 'px-2.5 py-1 text-[11px] leading-none'
    case 'default':
    default:
      return 'px-2.5 py-1 text-[11px] leading-none'
  }
}

export function Badge({
  className = '',
  variant = 'default',
  size = 'default',
  children,
  ...props
}: BadgeProps) {
  const baseClasses = [
    'inline-flex',
    'items-center',
    'justify-center',
    'gap-1',
    'rounded-full',
    'font-semibold',
    'whitespace-nowrap',
    'border',
    'border-transparent',
  ].join(' ')

  const variantClasses = getVariantClasses(variant)
  const sizeClasses = getSizeClasses(size)

  return (
    <span
      className={`${baseClasses} ${sizeClasses} ${variantClasses} ${className}`}
      {...props}
    >
      {children}
    </span>
  )
}

export default Badge
