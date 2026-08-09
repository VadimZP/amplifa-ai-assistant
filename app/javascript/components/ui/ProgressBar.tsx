import * as React from 'react'

/**
 * ProgressBar component for multi-step wizard flows
 * Based on Figma node 195:5835
 *
 * Specs:
 * - Segment height: 8px
 * - Segment gap: 16px
 * - Segment border radius: 2px
 * - Active: white bg with glow shadow (0px 13px 27.9px #ffffff)
 * - Inactive: #525252 (improved visibility)
 * - Labels: 12px Geist Regular, -0.36px letter-spacing
 * - Active label: white
 * - Inactive label: var(--foreground-subtle) for improved readability
 */

export interface ProgressStep {
  /** Step label text */
  label: string
  /** Whether this step is completed */
  completed: boolean
  /** Whether this is the current active step */
  current: boolean
}

export interface ProgressBarProps extends React.HTMLAttributes<HTMLDivElement> {
  /** Array of steps to display */
  steps: ProgressStep[]
  /** Whether to show labels below the progress bar */
  showLabels?: boolean
}

export function ProgressBar({
  className = '',
  steps,
  showLabels = true,
  ...props
}: ProgressBarProps) {
  return (
    <div className={`flex flex-col ${className}`} {...props}>
      {/* Progress segments */}
      <div className="flex gap-4">
        {steps.map((step, index) => {
          const isActive = step.completed || step.current

          return (
            <div
              key={index}
              className="flex-1 flex flex-col"
            >
              {/* Segment bar */}
              <div
                className={`
                  h-2 rounded-[2px] transition-all duration-300
                  ${isActive
                    ? 'bg-white shadow-[0px_13px_27.9px_0px_rgba(255,255,255,0.5)]'
                    : 'bg-[#525252]'
                  }
                `}
                role="progressbar"
                aria-valuenow={step.completed ? 100 : step.current ? 50 : 0}
                aria-valuemin={0}
                aria-valuemax={100}
                aria-label={step.label}
              />
            </div>
          )
        })}
      </div>

      {/* Labels */}
      {showLabels && (
        <div
          className="flex gap-4 pt-3 border-t border-[#252525] mt-0"
        >
          {steps.map((step, index) => {
            const isActive = step.completed || step.current

            return (
              <div
                key={index}
                className="flex-1 text-center"
              >
                <span
                  className={`
                    text-xs font-normal capitalize
                    tracking-[-0.36px] leading-[1.1]
                    ${isActive ? 'text-white' : 'text-[var(--foreground-subtle)]'}
                  `}
                >
                  {step.label}
                </span>
              </div>
            )
          })}
        </div>
      )}
    </div>
  )
}

/**
 * Simple progress bar variant without steps - just a fill percentage
 */
export interface SimpleProgressBarProps extends React.HTMLAttributes<HTMLDivElement> {
  /** Progress value from 0 to 100 */
  value: number
  /** Maximum value (default 100) */
  max?: number
  /** Show percentage label */
  showLabel?: boolean
  /** Custom color for the fill bar. Defaults to white. */
  color?: 'white' | 'green' | 'yellow' | 'red'
}

export function SimpleProgressBar({
  className = '',
  value,
  max = 100,
  showLabel = false,
  color,
  ...props
}: SimpleProgressBarProps) {
  const percentage = Math.min(Math.max((value / max) * 100, 0), 100)

  const colorClasses: Record<string, string> = {
    white: 'bg-white shadow-[0px_13px_27.9px_0px_rgba(255,255,255,0.5)]',
    green: 'bg-emerald-500 shadow-[0px_13px_27.9px_0px_rgba(16,185,129,0.4)]',
    yellow: 'bg-yellow-500 shadow-[0px_13px_27.9px_0px_rgba(234,179,8,0.4)]',
    red: 'bg-red-500 shadow-[0px_13px_27.9px_0px_rgba(239,68,68,0.4)]',
  }

  return (
    <div className={`flex flex-col gap-1 ${className}`} {...props}>
      <div
        className="h-2 bg-[#525252] rounded-[2px] overflow-hidden"
        role="progressbar"
        aria-valuenow={value}
        aria-valuemin={0}
        aria-valuemax={max}
      >
        <div
          className={`h-full rounded-[2px] transition-all duration-300 ${colorClasses[color || 'white']}`}
          style={{ width: `${percentage}%` }}
        />
      </div>
      {showLabel && (
        <span className="text-xs text-[var(--foreground-muted)] text-right">
          {Math.round(percentage)}%
        </span>
      )}
    </div>
  )
}

export default ProgressBar
