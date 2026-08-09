import * as React from 'react'
import { Slot, Slottable } from '@radix-ui/react-slot'
import { Loader2 } from 'lucide-react'

/**
 * Button component with multiple variants and sizes
 * Based on Figma designs from nodes 195:6829, 201:7381, 195:5243
 */

export interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  /** Visual style variant */
  variant?: 'primary' | 'secondary' | 'ghost' | 'destructive'
  /** Size of the button */
  size?: 'sm' | 'md' | 'lg'
  /** Show loading spinner and disable interaction */
  loading?: boolean
  /** Icon element to display */
  icon?: React.ReactNode
  /** Position of the icon */
  iconPosition?: 'left' | 'right'
  /** Make button full width */
  fullWidth?: boolean
  /** Render as child component (for use with Inertia Link) */
  asChild?: boolean
}

/**
 * Get variant-specific classes
 * Primary: Light gray bg (#e5e5e5) with dark text - main CTAs
 * Secondary: Transparent with border - "Back" actions
 * Ghost: Transparent with subtle border - utility actions
 * Destructive: Red bg - delete actions
 */
function getVariantClasses(variant: ButtonProps['variant']): string {
  switch (variant) {
    case 'primary':
      return [
        'bg-[var(--primary)]',
        'text-[var(--primary-foreground)]',
        'hover:bg-[var(--primary-hover)]',
        'shadow-[0_10px_26px_rgba(53,202,222,0.18)]',
        'active:scale-[0.98]',
      ].join(' ')
    case 'secondary':
      return [
        'bg-[var(--secondary)]',
        'border',
        'border-[var(--border)]',
        'text-[var(--foreground)]',
        'shadow-[inset_0_1px_0_rgba(255,255,255,0.03)]',
        'hover:bg-[var(--secondary-hover)]',
        'active:scale-[0.98]',
      ].join(' ')
    case 'ghost':
      return [
        'bg-transparent',
        'border',
        'border-transparent',
        'text-[var(--foreground)]',
        'hover:border-[var(--border)]',
        'hover:bg-white/[0.04]',
        'active:scale-[0.98]',
      ].join(' ')
    case 'destructive':
      return [
        'bg-[var(--error)]',
        'text-white',
        'hover:bg-[#dc2626]',
        'active:scale-[0.98]',
      ].join(' ')
    default:
      return ''
  }
}

/**
 * Get size-specific classes
 * sm: 32px height, 12px text - compact UI
 * md: 36px height, 14px text - standard (default)
 * lg: 44px height, 16px text - prominent CTAs
 */
function getSizeClasses(size: ButtonProps['size']): string {
  switch (size) {
    case 'sm':
      return 'h-8 px-3 text-xs gap-1.5'
    case 'md':
      return 'h-9 px-4 text-sm gap-2'
    case 'lg':
      return 'h-11 px-6 text-base gap-2'
    default:
      return ''
  }
}

export function Button({
  className = '',
  variant = 'primary',
  size = 'md',
  loading = false,
  icon,
  iconPosition = 'left',
  fullWidth = false,
  asChild = false,
  disabled,
  children,
  ...props
}: ButtonProps) {
  const Comp = asChild ? Slot : 'button'

  const isDisabled = disabled || loading

  // Base classes that apply to all buttons
  const baseClasses = [
    'inline-flex',
    'items-center',
    'justify-center',
    'rounded-xl',
    'font-medium',
    'transition-all',
    'duration-150',
    'whitespace-nowrap',
    // Focus state - using box-shadow directly for Tailwind v4 compatibility
    'focus:outline-none',
    'focus-visible:shadow-[0_0_0_2px_var(--ring-offset),0_0_0_4px_var(--ring)]',
    // Disabled state
    'disabled:opacity-50',
    'disabled:cursor-not-allowed',
    'disabled:pointer-events-none',
  ].join(' ')

  const variantClasses = getVariantClasses(variant)
  const sizeClasses = getSizeClasses(size)
  const widthClass = fullWidth ? 'w-full' : ''

  const allClasses = [baseClasses, variantClasses, sizeClasses, widthClass, className]
    .filter(Boolean)
    .join(' ')

  // Render icon with proper sizing based on button size
  const iconSize = size === 'sm' ? 'h-3.5 w-3.5' : size === 'lg' ? 'h-5 w-5' : 'h-4 w-4'

  const renderIcon = () => {
    if (loading) {
      return <Loader2 className={`${iconSize} shrink-0 animate-spin`} />
    }
    if (icon) {
      // WHY the wrapper centers and never shrinks: it is a fixed `iconSize` box, but a bare Lucide icon
      // renders at its own 24px default, which then overflowed the box from its top-left corner instead
      // of sitting in the middle. Centering here fixes alignment for every call site without resizing
      // icons that already pass their own explicit size class.
      return <span className={`${iconSize} inline-flex shrink-0 items-center justify-center`}>{icon}</span>
    }
    return null
  }

  const iconElement = renderIcon()
  const showIconLeft = iconElement && iconPosition === 'left'
  const showIconRight = iconElement && iconPosition === 'right' && !loading

  return (
    <Comp
      className={allClasses}
      disabled={isDisabled}
      {...props}
    >
      {showIconLeft && iconElement}
      {asChild ? <Slottable>{children}</Slottable> : children}
      {showIconRight && iconElement}
    </Comp>
  )
}

export default Button
