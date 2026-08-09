import * as React from 'react'
import { Button } from './Button'

/**
 * FooterActions component - Reusable footer with action buttons
 * Supports two variants:
 * - wizard: 12px gap, 42px buttons (for WizardLayout)
 * - slideOver: 24px gap, 36px buttons (for SlideOver panels)
 *
 * Based on Figma nodes:
 * - Wizard: 195:5243
 * - SlideOver: 201:3319
 */

export interface FooterActionsProps {
  /** Variant determines styling (gap, button height) */
  variant?: 'wizard' | 'slideOver'
  /** Primary action */
  primaryAction?: {
    label: string
    onClick: () => void
    disabled?: boolean
    loading?: boolean
  }
  /** Secondary action */
  secondaryAction?: {
    label: string
    onClick: () => void
    disabled?: boolean
  }
  /** Use sticky positioning with backdrop blur (only applies to slideOver variant) */
  sticky?: boolean
  /** Full width container (default: true) */
  fullWidth?: boolean
  /** Additional className for the container */
  className?: string
  /** Children to render instead of using action props */
  children?: React.ReactNode
}

/**
 * Get variant-specific container classes
 */
function getContainerClasses(
  variant: FooterActionsProps['variant'],
  sticky: boolean
): string {
  const baseClasses = 'flex w-full'

  if (variant === 'slideOver') {
    // SlideOver: 24px gap, with optional sticky styling
    const stickyClasses = sticky
      ? 'p-6 border-t border-[rgba(255,255,255,0.1)] backdrop-blur-[2px] bg-[rgba(16,16,18,0.9)]'
      : ''
    return `${baseClasses} gap-6 ${stickyClasses}`
  }

  // Wizard: 12px gap
  return `${baseClasses} gap-3`
}

/**
 * Get variant-specific button height class
 */
function getButtonHeightClass(variant: FooterActionsProps['variant']): string {
  return variant === 'slideOver' ? 'h-9' : 'h-[42px]'
}

export function FooterActions({
  variant = 'wizard',
  primaryAction,
  secondaryAction,
  sticky = false,
  fullWidth = true,
  className = '',
  children,
}: FooterActionsProps) {
  const containerClasses = getContainerClasses(variant, sticky)
  const buttonHeight = getButtonHeightClass(variant)
  const widthClass = fullWidth ? 'w-full' : ''

  // If children provided, render them instead of action props
  if (children) {
    return (
      <div className={`${containerClasses} ${widthClass} ${className}`}>
        {children}
      </div>
    )
  }

  // Render action buttons
  return (
    <div className={`${containerClasses} ${widthClass} ${className}`}>
      {secondaryAction && (
        <Button
          variant="secondary"
          onClick={secondaryAction.onClick}
          disabled={secondaryAction.disabled}
          className={`flex-1 ${buttonHeight}`}
        >
          {secondaryAction.label}
        </Button>
      )}
      {primaryAction && (
        <Button
          variant="primary"
          onClick={primaryAction.onClick}
          disabled={primaryAction.disabled}
          loading={primaryAction.loading}
          className={`flex-1 ${buttonHeight}`}
        >
          {primaryAction.label}
        </Button>
      )}
    </div>
  )
}

export default FooterActions
