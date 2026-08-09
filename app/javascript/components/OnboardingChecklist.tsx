import { Link } from '@inertiajs/react'
import { useState } from 'react'
import { CheckCircle, Circle, ChevronDown, ChevronUp } from 'lucide-react'
import { t } from '../lib/i18n'

/**
 * WHY: Define the structure for onboarding step data passed from backend
 * This matches the OnboardingSteps module structure in app/models/concerns/onboarding_steps.rb
 */
interface OnboardingStep {
  key: string
  title: string
  description: string
  action_url: string | null
  action_label: string
  completed: boolean
}

interface OnboardingChecklistProps {
  steps: OnboardingStep[]
  completionPercentage: number
  isComplete: boolean
}

/**
 * OnboardingChecklist Component
 *
 * WHY: This component displays a dynamic onboarding checklist for customer users
 * on their dashboard, guiding them through initial setup steps like completing
 * their company profile and selecting a language preference.
 *
 * The checklist shows:
 * - Overall progress (X of Y steps completed, percentage)
 * - List of all steps with completion status
 * - Action buttons for pending steps
 * - Collapsible functionality to save space once user is familiar
 *
 * WHY: Following the Week 2 spec requirements for onboarding UX:
 * - Visual priority on dashboard when onboarding incomplete
 * - Clear progress tracking with percentage
 * - Action buttons that navigate to relevant pages
 * - Grayed out completed steps
 * - Success message when all steps complete
 */
export default function OnboardingChecklist({
  steps,
  completionPercentage,
  isComplete
}: OnboardingChecklistProps) {
  // WHY: Allow users to collapse the checklist to save space after they've seen it
  // State persists in component but resets on page reload (intentional - keep it visible)
  const [isCollapsed, setIsCollapsed] = useState(false)

  // WHY: Calculate completed/total for display
  const completedCount = steps.filter(step => step.completed).length
  const totalCount = steps.length

  /**
   * WHY: If onboarding is complete, show a success state instead of the checklist
   * This gives positive feedback and sense of accomplishment
   */
  if (isComplete) {
    return (
      <div className="bg-[var(--success-muted)] border-2 border-[var(--success)]/30 rounded-xl shadow-[var(--shadow-sm)]">
        <div className="px-6 py-5">
          <div className="flex items-center">
            {/* WHY: Success checkmark icon from lucide-react */}
            <CheckCircle className="h-8 w-8 text-[var(--success)] mr-3" />
            <div className="flex-1">
              <h3 className="text-lg font-semibold text-[var(--foreground)]">
                {t('onboarding.complete_title')}
              </h3>
              <p className="text-sm text-[var(--foreground-muted)] mt-1">
                {t('onboarding.complete_description')}
              </p>
            </div>
          </div>
        </div>
      </div>
    )
  }

  return (
    <div className="bg-[var(--card)] border border-[var(--accent)]/30 rounded-xl shadow-[var(--shadow-sm)]">
      {/* Header Section */}
      <div className="px-6 py-4 border-b border-[var(--border)]">
        <div className="flex items-center justify-between">
          <div className="flex-1">
            <h3 className="text-lg font-semibold text-[var(--foreground)]">
              {t('onboarding.title')}
            </h3>
            <p className="text-sm text-[var(--foreground-muted)] mt-1">
              {t('onboarding.subtitle')}
            </p>
          </div>

          {/* WHY: Collapse/expand button to allow users to minimize after viewing */}
          <button
            onClick={() => setIsCollapsed(!isCollapsed)}
            className="ml-4 p-2 text-[var(--foreground-muted)] hover:text-[var(--foreground)] hover:bg-[var(--secondary)] rounded-md transition-colors"
            aria-label={isCollapsed ? t('onboarding.expand_checklist') : t('onboarding.collapse_checklist')}
          >
            {isCollapsed ? (
              <ChevronDown className="h-5 w-5" />
            ) : (
              <ChevronUp className="h-5 w-5" />
            )}
          </button>
        </div>

        {/* WHY: Progress bar provides visual feedback on completion status */}
        <div className="mt-4">
          <div className="flex items-center justify-between text-sm text-[var(--foreground-muted)] mb-2">
            <span>{completedCount}{t('onboarding.progress_of')}{totalCount}{t('onboarding.progress_suffix')}</span>
            <span className="font-semibold text-[var(--accent)]">{completionPercentage}%</span>
          </div>
          <div className="w-full bg-[var(--secondary)] rounded-full h-2">
            <div
              className="bg-[var(--accent)] h-2 rounded-full transition-all duration-500 ease-out"
              style={{ width: `${completionPercentage}%` }}
            />
          </div>
        </div>
      </div>

      {/* Steps List */}
      {!isCollapsed && (
        <div className="px-6 py-4 space-y-4">
          {steps.map((step) => (
            <div
              key={step.key}
              className={`flex items-start space-x-4 p-4 rounded-lg border transition-all ${
                step.completed
                  ? 'bg-[var(--secondary)] border-[var(--border)]'
                  : 'bg-[var(--accent)]/5 border-[var(--accent)]/30'
              }`}
            >
              {/* WHY: Visual status indicator - checkmark for completed, circle for pending */}
              <div className="flex-shrink-0 mt-1">
                {step.completed ? (
                  <CheckCircle className="h-6 w-6 text-[var(--success)]" />
                ) : (
                  <Circle className="h-6 w-6 text-[var(--foreground-subtle)]" />
                )}
              </div>

              {/* Step Content */}
              <div className="flex-1 min-w-0">
                <h4 className={`text-sm font-semibold ${
                  step.completed ? 'text-[var(--foreground-muted)]' : 'text-[var(--foreground)]'
                }`}>
                  {step.title}
                </h4>
                <p className={`text-sm mt-1 ${
                  step.completed ? 'text-[var(--foreground-subtle)]' : 'text-[var(--foreground-muted)]'
                }`}>
                  {step.description}
                </p>
              </div>

              {/* WHY: Action button only shown for pending steps, navigates to relevant page */}
              {!step.completed && step.action_url && (
                <div className="flex-shrink-0">
                  <Link
                    href={step.action_url}
                    className="inline-flex items-center px-3 py-2 border border-transparent text-sm font-medium rounded-lg text-[var(--primary-foreground)] bg-[var(--primary)] hover:bg-[var(--primary-hover)] focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-offset-[var(--background)] focus:ring-[var(--ring)] transition-colors"
                  >
                    {step.action_label}
                  </Link>
                </div>
              )}

              {/* WHY: For language step (no action_url), show instructions in button area */}
              {!step.completed && !step.action_url && (
                <div className="flex-shrink-0">
                  <div className="text-xs text-[var(--foreground-subtle)] italic max-w-[120px] text-right">
                    {t('onboarding.use_language_selector')}
                  </div>
                </div>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
