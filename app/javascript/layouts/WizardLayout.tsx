import { Head } from '@inertiajs/react'
import { ReactNode } from 'react'
import { CircleHelp } from 'lucide-react'
import { DotPattern } from '../components/ui/DotPattern'
import { ProgressBar, ProgressStep } from '../components/ui/ProgressBar'
import { Button } from '../components/ui/Button'

/**
 * WizardLayout - Two-panel wizard layout for onboarding flows
 * Based on Figma node 195:5024
 *
 * Structure:
 * - Left panel: Logo, welcome text, progress bar, dot pattern decoration
 * - Right panel: Main content area with footer action buttons
 *
 * Design specs:
 * - Container: Black bg (#0a0a0a), 12px padding, 8px border-radius
 * - Left panel: 50% width, 40px padding
 * - Right panel: 50% width, #101012 bg, 14px border-radius, 40px padding
 */

export interface WizardLayoutProps {
  /** Page title for browser tab */
  pageTitle?: string
  /** Title displayed in left panel */
  title: string
  /** Subtitle/description in left panel */
  subtitle?: string
  /** Wizard steps for progress bar */
  steps: ProgressStep[]
  /** Main content (right panel) */
  children: ReactNode
  /** Back button handler (optional) */
  onBack?: () => void
  /** Next/primary action handler */
  onNext?: () => void
  /** Custom label for next button */
  nextLabel?: string
  /** Custom label for back button */
  backLabel?: string
  /** Disable next button */
  nextDisabled?: boolean
  /** Show back button (default: true if onBack provided) */
  showBackButton?: boolean
  /** Show help button in header (default: true) */
  showHelpButton?: boolean
  /** Loading state for next button */
  nextLoading?: boolean
  /** Hide footer buttons entirely */
  hideFooter?: boolean
}

export default function WizardLayout({
  pageTitle,
  title,
  subtitle,
  steps,
  children,
  onBack,
  onNext,
  nextLabel = 'Next',
  backLabel = 'Back',
  nextDisabled = false,
  showBackButton,
  showHelpButton = true,
  nextLoading = false,
  hideFooter = false,
}: WizardLayoutProps) {
  // Show back button if handler provided and not explicitly hidden
  const shouldShowBack = showBackButton ?? !!onBack

  return (
    <div className="min-h-screen bg-black p-3">
      {pageTitle && <Head title={pageTitle} />}

      {/* Main container with rounded corners */}
      <div className="flex min-h-[calc(100vh-24px)] rounded-lg overflow-hidden">
        {/* Left Panel - Hidden on mobile */}
        <div className="hidden lg:flex lg:flex-1 flex-col gap-8 p-10 relative bg-[var(--background)]">
          {/* Dot pattern decoration - top left */}
          <DotPattern position="top-left" className="w-[376px] h-[376px] opacity-50" />

          {/* Header: Logo and Help button */}
          <div className="flex items-center justify-between relative z-10">
            {/* Logo - fixed aspect ratio to prevent stretching */}
            <img
              src="/amplifa-logo-white.svg"
              alt="Amplifa"
              className="h-6 w-[95px] object-contain shrink-0"
            />

            {/* Need Help button - Figma node 195:6829 */}
            {showHelpButton && (
              <button
                type="button"
                className="
                  flex items-center gap-2 h-8 px-3 py-2
                  bg-[var(--input)]
                  border border-[#e5e5e5]
                  rounded-lg
                  text-xs font-medium leading-4 text-[var(--foreground)]
                  shadow-[0px_1px_2px_0px_rgba(0,0,0,0.05)]
                  hover:bg-[var(--input-focus)]
                  active:scale-[0.98]
                  transition-all duration-150
                "
                onClick={() => window.open('mailto:support@amplifa.com', '_blank')}
              >
                <CircleHelp className="h-4 w-4" />
                <span>Need Help?</span>
              </button>
            )}
          </div>

          {/* Welcome text - vertically centered */}
          <div className="flex-1 flex flex-col justify-center relative z-10">
            <div className="flex flex-col gap-2">
              <h1 className="text-[32px] font-semibold text-white leading-tight">
                {title}
              </h1>
              {subtitle && (
                <p className="text-sm text-[var(--foreground-subtle)] leading-normal">
                  {subtitle}
                </p>
              )}
            </div>
          </div>

          {/* Progress bar - at bottom */}
          <div className="relative z-10 w-full">
            <ProgressBar steps={steps} showLabels={true} />
          </div>
        </div>

        {/* Right Panel - Main content area */}
        <div
          className="
            flex-1 lg:flex-1
            flex flex-col
            bg-[#101012]
            rounded-[14px]
            p-6 sm:p-10
            shadow-[0px_1px_3px_0px_rgba(0,0,0,0.1),0px_1px_2px_-1px_rgba(0,0,0,0.1)]
            overflow-clip
          "
        >
          {/* Mobile header - only shown on small screens */}
          <div className="lg:hidden mb-6">
            <img
              src="/amplifa-logo-white.svg"
              alt="Amplifa"
              className="h-6 w-[95px] object-contain mb-4"
            />
            <h1 className="text-xl font-semibold text-white mb-1">{title}</h1>
            {subtitle && (
              <p className="text-sm text-[var(--foreground-subtle)]">{subtitle}</p>
            )}
          </div>

          {/* Mobile progress bar */}
          <div className="lg:hidden mb-6">
            <ProgressBar steps={steps} showLabels={false} />
          </div>

          {/* Content area - scrollable, takes remaining space */}
          <div className="flex-1 overflow-y-auto">
            {children}
          </div>

          {/* Footer with action buttons */}
          {!hideFooter && onNext && (
            <div className="flex gap-3 mt-12 h-[42px]">
              {shouldShowBack && onBack && (
                <Button
                  variant="secondary"
                  size="lg"
                  onClick={onBack}
                  className="flex-1 h-[42px]"
                >
                  {backLabel}
                </Button>
              )}
              <Button
                variant="primary"
                size="lg"
                onClick={onNext}
                disabled={nextDisabled}
                loading={nextLoading}
                className="flex-1 h-[42px]"
              >
                {nextLabel}
              </Button>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
