import * as React from 'react'
import { useEffect, useCallback, useRef, useState } from 'react'
import { X } from 'lucide-react'
import { Button } from './Button'

/**
 * SlideOver component - Right-side slide-over panel for detail views
 * Based on Figma node 201:3253
 *
 * Design specs:
 * - Panel width: 433px (default 'md')
 * - Background: #101012
 * - Border: 1px solid rgba(255,255,255,0.1)
 * - Border radius: 14px
 * - Shadow: shadow-sm
 * - Backdrop: rgba(0,0,0,0.5)
 * - Animations: slide in from right, fade backdrop
 */

export interface SlideOverProps {
  /** Whether the panel is open */
  open: boolean
  /** Close handler */
  onClose: () => void
  /** Panel title (displayed in header if provided) */
  title?: React.ReactNode
  /** Main content */
  children: React.ReactNode
  /** Footer content (typically buttons) */
  footer?: React.ReactNode
  /** Width of the panel */
  width?: 'sm' | 'md' | 'lg' | number
  /** Show backdrop overlay (default: true) */
  showBackdrop?: boolean
  /** Close on backdrop click (default: true) */
  closeOnBackdropClick?: boolean
  /** Close on escape key (default: true) */
  closeOnEscape?: boolean
  /** Show the header close button (default: true) */
  showCloseButton?: boolean
  /** Additional className for the panel */
  className?: string
  /** Optional className override for the title element */
  titleClassName?: string
  /** Optional className appended to the header row */
  headerClassName?: string
}

const widthClasses = {
  sm: 'w-[360px]',
  md: 'w-[433px]',
  lg: 'w-[540px]',
}

export function SlideOver({
  open,
  onClose,
  title,
  children,
  footer,
  width = 'md',
  showBackdrop = true,
  closeOnBackdropClick = true,
  closeOnEscape = true,
  showCloseButton = true,
  className = '',
  titleClassName,
  headerClassName = '',
}: SlideOverProps) {
  const panelRef = useRef<HTMLDivElement>(null)
  const previousActiveElement = useRef<Element | null>(null)
  const initialFocusSet = useRef(false)

  // State for managing mount/unmount with animation
  const [isMounted, setIsMounted] = useState(false)
  const [isVisible, setIsVisible] = useState(false)

  // Handle mount/unmount with animation timing
  useEffect(() => {
    if (open) {
      // Mount first, then trigger animation
      setIsMounted(true)
      // Small delay to ensure DOM is ready before animating
      const showTimer = requestAnimationFrame(() => {
        requestAnimationFrame(() => {
          setIsVisible(true)
        })
      })
      return () => cancelAnimationFrame(showTimer)
    } else {
      // Trigger close animation first
      setIsVisible(false)
      initialFocusSet.current = false
      // Wait for animation to complete before unmounting
      const hideTimer = setTimeout(() => {
        setIsMounted(false)
      }, 300) // Match duration-300
      return () => clearTimeout(hideTimer)
    }
  }, [open])

  // Handle escape key
  const handleKeyDown = useCallback(
    (event: KeyboardEvent) => {
      if (closeOnEscape && event.key === 'Escape') {
        onClose()
      }
    },
    [closeOnEscape, onClose]
  )

  // Focus trap - keep focus within the panel
  const handleFocusTrap = useCallback((event: KeyboardEvent) => {
    if (event.key !== 'Tab' || !panelRef.current) return

    const focusableElements = panelRef.current.querySelectorAll<HTMLElement>(
      'button:not([disabled]), [href], input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])'
    )
    const firstElement = focusableElements[0]
    const lastElement = focusableElements[focusableElements.length - 1]

    if (!firstElement) return

    if (event.shiftKey) {
      // Shift + Tab: if on first element, move to last
      if (document.activeElement === firstElement) {
        event.preventDefault()
        lastElement?.focus()
      }
    } else {
      // Tab: if on last element, move to first
      if (document.activeElement === lastElement) {
        event.preventDefault()
        firstElement?.focus()
      }
    }
  }, [])

  // Add/remove listeners and manage focus
  useEffect(() => {
    if (open && isVisible) {
      // Store the currently focused element to restore later (only on initial open)
      if (!initialFocusSet.current) {
        previousActiveElement.current = document.activeElement
      }

      document.addEventListener('keydown', handleKeyDown)
      document.addEventListener('keydown', handleFocusTrap)
      // Prevent body scroll when open
      document.body.style.overflow = 'hidden'

      // Focus the panel or first focusable element after animation starts (only once)
      if (!initialFocusSet.current) {
        initialFocusSet.current = true
        setTimeout(() => {
          if (panelRef.current) {
            const firstFocusable = panelRef.current.querySelector<HTMLElement>(
              'button:not([disabled]), [href], input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])'
            )
            if (firstFocusable) {
              firstFocusable.focus()
            } else {
              panelRef.current.focus()
            }
          }
        }, 100)
      }
    }

    return () => {
      document.removeEventListener('keydown', handleKeyDown)
      document.removeEventListener('keydown', handleFocusTrap)
      document.body.style.overflow = ''

      // Restore focus to the previously focused element
      if (!open && previousActiveElement.current instanceof HTMLElement) {
        previousActiveElement.current.focus()
      }
    }
  }, [open, isVisible, handleKeyDown, handleFocusTrap])

  // Handle backdrop click
  const handleBackdropClick = (event: React.MouseEvent) => {
    if (closeOnBackdropClick && event.target === event.currentTarget) {
      onClose()
    }
  }

  // Get width style
  const widthStyle = typeof width === 'number' ? { width: `${width}px` } : undefined
  const widthClass = typeof width === 'string' ? widthClasses[width] : ''

  if (!isMounted) return null

  return (
    <div
      className="fixed inset-0 z-50"
      role="dialog"
      aria-modal="true"
      aria-labelledby={title ? 'slideover-title' : undefined}
    >
      {/* Backdrop overlay */}
      {showBackdrop && (
        <div
          className={`
            fixed inset-0 bg-[rgba(6,8,11,0.72)] backdrop-blur-sm
            transition-opacity duration-300 ease-out
            ${isVisible ? 'opacity-100' : 'opacity-0'}
          `}
          aria-hidden="true"
          onClick={handleBackdropClick}
        />
      )}

      {/* Panel container */}
      <div
        className="fixed inset-y-0 right-0 flex items-center justify-end p-3 lg:p-5"
      >
        {/* Panel */}
        <div
          ref={panelRef}
          tabIndex={-1}
          className={`
            relative flex flex-col
            h-[calc(100vh-24px)] max-h-[calc(100vh-24px)]
            bg-[var(--background-secondary)]
            border border-white/[0.08]
            rounded-[30px]
            shadow-[0_28px_60px_rgba(0,0,0,0.36)]
            overflow-clip
            transform transition-transform duration-300 ease-out
            ${isVisible ? 'translate-x-0' : 'translate-x-full'}
            focus:outline-none
            ${widthClass}
            ${className}
          `}
          style={widthStyle}
        >
          {/* Default header with close button (only shown if no custom header in children) */}
          {title && (
            <div
              className={`flex items-center justify-between border-b border-white/[0.06] bg-[var(--background-secondary)]/92 backdrop-blur-sm ${headerClassName || 'px-7 py-6'}`}
            >
              <h2
                id="slideover-title"
                className={titleClassName ?? 'text-[24px] font-semibold tracking-[-0.02em] text-white'}
              >
                {title}
              </h2>
              {showCloseButton && (
                <button
                  type="button"
                  className="
                    flex size-10 items-center justify-center rounded-full
                    border border-white/[0.08]
                    bg-white/[0.04]
                    text-[var(--foreground-muted)] hover:text-white
                    hover:bg-white/[0.08]
                    transition-colors duration-150
                    focus:outline-none focus-visible:ring-2 focus-visible:ring-[var(--ring)]
                  "
                  onClick={onClose}
                  aria-label="Close panel"
                >
                  <X className="h-5 w-5" />
                </button>
              )}
            </div>
          )}

          {/* Content area - scrollable */}
          <div className="flex-1 overflow-y-auto custom-scrollbar">
            {children}
          </div>

          {/* Footer */}
          {footer && (
            <div
              className="
                border-t border-white/[0.06]
                bg-[var(--background-secondary)]/94
                px-7 py-5
                backdrop-blur-sm
              "
            >
              {footer}
            </div>
          )}
        </div>
      </div>
    </div>
  )
}

/**
 * SlideOverCloseButton - Standalone close button for custom headers
 */
export interface SlideOverCloseButtonProps {
  onClick: () => void
  className?: string
}

export function SlideOverCloseButton({
  onClick,
  className = '',
}: SlideOverCloseButtonProps) {
  return (
    <button
      type="button"
      className={`
        flex size-10 items-center justify-center rounded-full
        border border-white/[0.08]
        bg-white/[0.04]
        text-[var(--foreground-muted)] hover:text-white
        hover:bg-white/[0.08]
        transition-colors duration-150
        focus:outline-none focus-visible:ring-2 focus-visible:ring-[var(--ring)]
        ${className}
      `}
      onClick={onClick}
      aria-label="Close panel"
    >
      <X className="h-5 w-5" />
    </button>
  )
}

/**
 * SlideOverFooterButtons - Standard footer button layout for slide-overs
 * Based on Figma node 201:3319
 */
export interface SlideOverFooterButtonsProps {
  /** Primary action button label */
  primaryLabel: string
  /** Primary action handler */
  onPrimary: () => void
  /** Primary button disabled state */
  primaryDisabled?: boolean
  /** Primary button loading state */
  primaryLoading?: boolean
  /** Secondary action button label (optional) */
  secondaryLabel?: string
  /** Secondary action handler (optional) */
  onSecondary?: () => void
  /** Secondary button disabled state */
  secondaryDisabled?: boolean
}

export function SlideOverFooterButtons({
  primaryLabel,
  onPrimary,
  primaryDisabled = false,
  primaryLoading = false,
  secondaryLabel,
  onSecondary,
  secondaryDisabled = false,
}: SlideOverFooterButtonsProps) {
  return (
    <div className="flex gap-6">
      {secondaryLabel && onSecondary && (
        <Button
          variant="secondary"
          className="h-10 flex-1"
          onClick={onSecondary}
          disabled={secondaryDisabled}
        >
          {secondaryLabel}
        </Button>
      )}
      <Button
        type="button"
        className="h-10 flex-1"
        onClick={onPrimary}
        disabled={primaryDisabled}
        loading={primaryLoading}
      >
        {primaryLabel}
      </Button>
    </div>
  )
}

export default SlideOver
