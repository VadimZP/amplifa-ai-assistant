import * as React from 'react'

/**
 * Input component with label, description, and error state support
 * Based on Figma node 201:7366
 *
 * Specs:
 * - Height: 36px
 * - Background: rgba(255,255,255,0.05)
 * - Border: 1px solid rgba(255,255,255,0.15)
 * - Border Radius: 8px
 * - Padding: 12px horizontal, 4px vertical
 * - Font: 14px Geist Regular
 * - Placeholder: #a3a3a3
 * - Label: 14px medium, #fafafa, 12px gap below
 */

export interface InputProps extends Omit<React.InputHTMLAttributes<HTMLInputElement>, 'size'> {
  /** Label text above the input */
  label?: string
  /** Helper text below the label or input */
  description?: string
  /** Error message(s) - shows first if array */
  error?: string | string[]
  /** Icon element to display */
  icon?: React.ReactNode
  /** Position of the icon */
  iconPosition?: 'left' | 'right'
  /** Size variant */
  size?: 'sm' | 'md' | 'lg'
  /** Container className for wrapper div */
  containerClassName?: string
}

export const Input = React.forwardRef<HTMLInputElement, InputProps>(
  (
    {
      className = '',
      containerClassName = '',
      label,
      description,
      error,
      icon,
      iconPosition = 'right',
      size = 'md',
      type = 'text',
      id,
      ...props
    },
    ref
  ) => {
    // Always call useId first to avoid conditional hook violations
    const generatedId = React.useId()
    const inputId = id || generatedId

    // Get first error if array
    const errorMessage = Array.isArray(error) ? error[0] : error
    const hasError = Boolean(errorMessage)

    // Size-specific classes
    const sizeClasses = {
      sm: 'h-8 text-xs px-2.5',
      md: 'h-10 text-sm px-3.5',
      lg: 'h-11 text-base px-4',
    }

    // Base input classes
    // Focus styles are handled by global CSS in application.css for consistency
    const inputBaseClasses = [
      'w-full',
      'rounded-xl',
      'border',
      'bg-[var(--input)]',
      'text-[var(--foreground)]',
      'placeholder:text-[var(--foreground-muted)]',
      'shadow-[inset_0_1px_0_rgba(255,255,255,0.03)]',
      'transition-all',
      'duration-150',
      // Disabled state
      'disabled:opacity-50',
      'disabled:cursor-not-allowed',
    ].join(' ')

    // Border color based on error state
    const borderClass = hasError
      ? 'border-[var(--error)]'
      : 'border-[var(--input-border)]'

    // Icon padding adjustment
    const iconPaddingClass = icon
      ? iconPosition === 'left'
        ? 'pl-10'
        : 'pr-10'
      : ''

    const allInputClasses = [
      inputBaseClasses,
      sizeClasses[size],
      borderClass,
      iconPaddingClass,
      className,
    ]
      .filter(Boolean)
      .join(' ')

    return (
      <div className={`flex flex-col gap-3 ${containerClassName}`}>
        {/* Label */}
        {label && (
          <label
            htmlFor={inputId}
            className="text-sm font-medium text-[var(--foreground)] leading-5"
          >
            {label}
          </label>
        )}

        {/* Description below label */}
        {description && !hasError && (
          <p className="text-xs text-[var(--foreground-muted)] -mt-1.5">
            {description}
          </p>
        )}

        {/* Input wrapper for icon positioning */}
        <div className="relative">
          {/* Left icon */}
          {icon && iconPosition === 'left' && (
            <div className="absolute left-3 top-1/2 -translate-y-1/2 text-[var(--foreground-muted)] pointer-events-none">
              <span className="h-4 w-4 block">{icon}</span>
            </div>
          )}

          {/* Input field */}
          <input
            ref={ref}
            type={type}
            id={inputId}
            className={allInputClasses}
            aria-invalid={hasError}
            aria-describedby={hasError ? `${inputId}-error` : undefined}
            {...props}
          />

          {/* Right icon */}
          {icon && iconPosition === 'right' && (
            <div className="absolute right-3 top-1/2 -translate-y-1/2 text-[var(--foreground-muted)]">
              <span className="h-4 w-4 block">{icon}</span>
            </div>
          )}
        </div>

        {/* Error message */}
        {hasError && (
          <p
            id={`${inputId}-error`}
            className="text-xs text-[var(--error)] -mt-1"
            role="alert"
          >
            {errorMessage}
          </p>
        )}
      </div>
    )
  }
)

Input.displayName = 'Input'

export default Input
