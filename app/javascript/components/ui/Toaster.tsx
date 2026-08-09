/**
 * Toaster component using Sonner
 *
 * WHY: Provides toast notifications that don't disrupt page layout like flash messages do.
 * Positioned bottom-right to avoid blocking navigation or content.
 *
 * WHY Sonner: Modern, lightweight toast library with excellent DX.
 * Integrates well with Radix UI / shadcn patterns already used in this codebase.
 *
 * Positioning and enter/exit animation come from Sonner's own injected stylesheet, which already sets
 * `position: fixed` (z-index 999999999) on the container and animates each toast with
 * `transition: transform .4s, opacity .4s` between `opacity: 0; translateY(100%)` and the
 * `[data-mounted=true]` state. Re-declaring any of that here would only risk fighting it, so the
 * overrides below stay limited to theme colors and timing.
 */

import { Toaster as SonnerToaster } from 'sonner'

export function Toaster() {
  return (
    <SonnerToaster
      position="bottom-right"
      closeButton
      duration={3000}
      visibleToasts={3}
      toastOptions={{
        classNames: {
          // WHY no `richColors`: it made Sonner paint its own hsl() red/green backgrounds, which ignore
          // the app's tokens. Success/error tinting is done here with `--success` / `--error` instead.
          toast:
            'bg-[var(--background-elevated)] border border-[var(--border)] text-[var(--foreground)] shadow-[var(--shadow-lg)]',
          title: 'text-[var(--foreground)]',
          description: 'text-[var(--foreground-muted)]',
          success: 'border-[var(--success)]/30 bg-[var(--success-muted)] text-[var(--success)]',
          error: 'border-[var(--error)]/30 bg-[var(--error-muted)] text-[var(--error)]',
          actionButton: 'bg-[var(--accent)] text-white',
          cancelButton: 'bg-[var(--card-hover)] text-[var(--foreground)]',
          closeButton:
            'bg-[var(--background-elevated)] border-[var(--border)] text-[var(--foreground-muted)]',
        },
      }}
    />
  )
}

export { toast } from 'sonner'
