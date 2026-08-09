import * as React from 'react'

/**
 * Textarea component with label, description, and error state support
 * Consistent styling with Input component
 *
 * Additional specs:
 * - Min height: 96px
 * - Resize: vertical only
 */

export interface TextareaProps extends React.TextareaHTMLAttributes<HTMLTextAreaElement> {
  /** Label text above the textarea */
  label?: string
  /** Helper text below the label or textarea */
  description?: string
  /** Error message(s) - shows first if array */
  error?: string | string[]
  /** Container className for wrapper div */
  containerClassName?: string
  /** Auto-expand textarea to fit content */
  autoResize?: boolean
  /** Max visible rows when autoResize is enabled; overflow scrolls vertically */
  maxRows?: number
  /** Borderless variant for embedding inside a parent shell (e.g. assistant composer) */
  embedded?: boolean
}

export const Textarea = React.forwardRef<HTMLTextAreaElement, TextareaProps>(
  (
    {
      className = '',
      containerClassName = '',
      label,
      description,
      error,
      id,
      autoResize = false,
      maxRows,
      embedded = false,
      value,
      ...props
    },
    ref
  ) => {
    // Always call useId first to avoid conditional hook violations
    const generatedId = React.useId()
    const textareaId = id || generatedId
    const textareaRef = React.useRef<HTMLTextAreaElement>(null)

    // Get first error if array
    const errorMessage = Array.isArray(error) ? error[0] : error
    const hasError = Boolean(errorMessage)

    // Auto-resize effect
    React.useEffect(() => {
      if (!autoResize || !textareaRef.current) return

      const textarea = textareaRef.current

      const adjustHeight = () => {
        textarea.style.height = 'auto'

        const styles = getComputedStyle(textarea)
        const lineHeight = parseFloat(styles.lineHeight)
        const paddingTop = parseFloat(styles.paddingTop)
        const paddingBottom = parseFloat(styles.paddingBottom)
        const padding = paddingTop + paddingBottom

        let maxHeight = Infinity
        if (maxRows && Number.isFinite(lineHeight) && lineHeight > 0) {
          maxHeight = lineHeight * maxRows + padding
        }

        const nextHeight = Math.min(textarea.scrollHeight, maxHeight)
        textarea.style.height = `${nextHeight}px`
        textarea.style.overflowY = textarea.scrollHeight > maxHeight ? 'auto' : 'hidden'
      }

      adjustHeight()
      textarea.addEventListener('input', adjustHeight)

      return () => {
        textarea.removeEventListener('input', adjustHeight)
      }
    }, [autoResize, maxRows, value])

    // Base textarea classes
    // Focus styles are handled by global CSS in application.css for consistency
    const textareaBaseClasses = embedded
      ? [
          'composer-textarea',
          'w-full',
          'min-h-0',
          'border-0',
          'bg-transparent',
          'text-[var(--foreground)]',
          'text-sm',
          'px-0',
          'py-2.5',
          'placeholder:text-[var(--foreground-muted)]',
          'shadow-none',
          'transition-all',
          'duration-150',
          autoResize ? 'resize-none' : 'resize-y',
          'disabled:opacity-50',
          'disabled:cursor-not-allowed',
          'disabled:resize-none',
        ].join(' ')
      : [
          'w-full',
          'min-h-24', // 96px
          'rounded-xl',
          'border',
          'bg-[var(--input)]',
          'text-[var(--foreground)]',
          'text-sm',
          'px-3.5',
          'py-3',
          'placeholder:text-[var(--foreground-muted)]',
          'shadow-[inset_0_1px_0_rgba(255,255,255,0.03)]',
          'transition-all',
          'duration-150',
          autoResize ? 'resize-none' : 'resize-y',
          // Disabled state
          'disabled:opacity-50',
          'disabled:cursor-not-allowed',
          'disabled:resize-none',
        ].join(' ')

    // Border color based on error state
    const borderClass = embedded
      ? ''
      : hasError
        ? 'border-[var(--error)]'
        : 'border-[var(--input-border)]'

    const allTextareaClasses = [
      textareaBaseClasses,
      borderClass,
      className,
    ]
      .filter(Boolean)
      .join(' ')

    const autoResizeStyle = autoResize && !maxRows
      ? { maxHeight: '400px', overflowY: 'auto' as const }
      : undefined

    return (
      <div className={`flex flex-col ${embedded ? 'gap-0' : 'gap-3'} ${containerClassName}`}>
        {/* Label */}
        {label && (
          <label
            htmlFor={textareaId}
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

        {/* Textarea field */}
        <textarea
          ref={(element) => {
            textareaRef.current = element
            if (typeof ref === 'function') ref(element)
            else if (ref) ref.current = element
          }}
          id={textareaId}
          className={allTextareaClasses}
          style={autoResizeStyle}
          aria-invalid={hasError}
          aria-describedby={hasError ? `${textareaId}-error` : undefined}
          value={value}
          {...props}
        />

        {/* Error message */}
        {hasError && (
          <p
            id={`${textareaId}-error`}
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

Textarea.displayName = 'Textarea'

export default Textarea
