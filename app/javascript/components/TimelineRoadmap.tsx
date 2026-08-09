import { CheckCircle, Settings, TrendingUp, Rocket, Lock } from 'lucide-react'
import { t } from '../lib/i18n'

/**
 * WHY: i18n is used to support multiple languages (EN/DE) for international users.
 * All user-facing text is translated via i18n.t() calls to provide a localized experience.
 */

/**
 * WHY: Define the structure for timeline stage data
 * This matches the spec in thoughts/specs/20251105_mvp_week2_spec.md
 */
interface TimelineStage {
  key: string
  title: string
  description: string
  icon: 'onboarding' | 'setup' | 'warming' | 'launch'
  status: 'completed' | 'current' | 'future'
  duration?: string
}

interface TimelineRoadmapProps {
  stages: TimelineStage[]
  currentStageKey: string
}

/**
 * TimelineRoadmap Component
 *
 * WHY: This component provides transparency to customers about their journey
 * from onboarding to launch. It shows the 4-stage path: Onboarding → Setup →
 * Warming → Launch, with clear visual indicators of which stage they're in.
 *
 * WHY: Following the Week 2 spec requirements:
 * - Horizontal timeline with 4 stages (responsive to vertical on mobile)
 * - Each stage has: icon, title, description, status
 * - Completed stages: green with checkmark
 * - Current stage: blue with "You are here" badge and pulsing animation
 * - Future stages: gray with lock icon
 * - Connecting lines between stages
 *
 * WHY: For Week 2, only the Onboarding stage is functional. Other stages are
 * placeholders showing "Coming Soon" to set expectations for future features.
 */
export default function TimelineRoadmap({ stages }: TimelineRoadmapProps) {
  /**
   * WHY: Render icon component from lucide-react based on stage type
   */
  const renderIcon = (iconName: string, className: string) => {
    switch (iconName) {
      case 'onboarding':
        return <CheckCircle className={className} />
      case 'setup':
        return <Settings className={className} />
      case 'warming':
        return <TrendingUp className={className} />
      case 'launch':
        return <Rocket className={className} />
      default:
        return <CheckCircle className={className} />
    }
  }

  /**
   * WHY: Determine visual styling based on stage status
   * Completed = green, Current = blue + pulse, Future = gray
   */
  const getStageStyles = (status: string) => {
    switch (status) {
      case 'completed':
        return {
          container: 'border-[var(--success)]/30 bg-[var(--success-muted)]',
          icon: 'text-[var(--success)] bg-[var(--success)]/20',
          title: 'text-[var(--foreground)]',
          description: 'text-[var(--foreground-muted)]',
          indicator: <CheckCircle className="absolute -top-1 -right-1 h-5 w-5 text-[var(--success)] bg-[var(--card)] rounded-full" />
        }
      case 'current':
        return {
          container: 'border-[var(--accent)] bg-[var(--accent)]/10 ring-2 ring-[var(--accent)]/30',
          icon: 'text-[var(--accent)] bg-[var(--accent)]/20 animate-pulse',
          title: 'text-[var(--foreground)] font-semibold',
          description: 'text-[var(--foreground-muted)]',
          indicator: (
            <div className="absolute -top-3 left-1/2 transform -translate-x-1/2 bg-[var(--accent)] text-white text-xs font-semibold px-2 py-1 rounded-full whitespace-nowrap">
              {t('timeline.you_are_here')}
            </div>
          )
        }
      case 'future':
        return {
          container: 'border-[var(--border)] bg-[var(--secondary)]',
          icon: 'text-[var(--foreground-subtle)] bg-[var(--secondary-hover)]',
          title: 'text-[var(--foreground-subtle)]',
          description: 'text-[var(--foreground-subtle)]',
          indicator: <Lock className="absolute -top-1 -right-1 h-5 w-5 text-[var(--foreground-subtle)] bg-[var(--card)] rounded-full" />
        }
      default:
        return {
          container: 'border-[var(--border)] bg-[var(--secondary)]',
          icon: 'text-[var(--foreground-subtle)] bg-[var(--secondary-hover)]',
          title: 'text-[var(--foreground-subtle)]',
          description: 'text-[var(--foreground-subtle)]',
          indicator: null
        }
    }
  }

  return (
    <div className="bg-[var(--card)] rounded-xl shadow-[var(--shadow-sm)] border border-[var(--border)]">
      {/* Header */}
      <div className="px-6 py-4 border-b border-[var(--border)]">
        <h3 className="text-lg font-semibold text-[var(--foreground)]">
          {t('timeline.title')}
        </h3>
        <p className="text-sm text-[var(--foreground-muted)] mt-1">
          {t('timeline.subtitle')}
        </p>
      </div>

      {/* Timeline - Desktop (Horizontal) */}
      <div className="hidden md:block px-6 py-8">
        <div className="relative">
          {/* WHY: Connecting line between stages - shows flow from left to right */}
          <div className="absolute top-8 left-0 right-0 h-0.5 bg-[var(--border)]" style={{ left: '48px', right: '48px' }} />

          <div className="relative grid grid-cols-4 gap-4">
            {stages.map((stage, index) => {
              const styles = getStageStyles(stage.status)

              return (
                <div key={stage.key} className="flex flex-col items-center">
                  {/* Stage Card */}
                  <div
                    className={`relative w-full p-4 rounded-lg border-2 transition-all ${styles.container}`}
                  >
                    {/* WHY: Status indicator at top (checkmark/lock/current badge) */}
                    {styles.indicator}

                    {/* WHY: Icon in circle - visual identifier for each stage */}
                    <div className={`w-16 h-16 mx-auto rounded-full flex items-center justify-center ${styles.icon}`}>
                      {renderIcon(stage.icon, 'h-8 w-8')}
                    </div>

                    {/* Stage Title */}
                    <h4 className={`text-center text-sm font-medium mt-3 ${styles.title}`}>
                      {stage.title}
                    </h4>

                    {/* Stage Description */}
                    <p className={`text-center text-xs mt-2 ${styles.description}`}>
                      {stage.description}
                    </p>

                    {/* WHY: Duration label for stages with time estimates (e.g., "~3 weeks" for warming) */}
                    {stage.duration && (
                      <div className="text-center text-xs text-[var(--foreground-subtle)] mt-2 font-medium">
                        {stage.duration}
                      </div>
                    )}

                    {/* WHY: "Coming Soon" label for future stages not yet implemented */}
                    {stage.status === 'future' && (
                      <div className="text-center text-xs text-[var(--foreground-subtle)] mt-2 italic">
                        {t('timeline.coming_soon')}
                      </div>
                    )}
                  </div>

                  {/* WHY: Stage number below card for additional context */}
                  <div className="mt-2 text-xs text-[var(--foreground-subtle)] font-medium">
                    {t('timeline.stage_label')} {index + 1}
                  </div>
                </div>
              )
            })}
          </div>
        </div>
      </div>

      {/* Timeline - Mobile (Vertical) */}
      <div className="md:hidden px-6 py-6">
        <div className="relative space-y-6">
          {stages.map((stage, index) => {
            const styles = getStageStyles(stage.status)
            const isLast = index === stages.length - 1

            return (
              <div key={stage.key} className="relative">
                {/* WHY: Vertical connecting line between stages */}
                {!isLast && (
                  <div className="absolute left-8 top-16 bottom-0 w-0.5 bg-[var(--border)] -mb-6" />
                )}

                <div className="flex space-x-4">
                  {/* WHY: Stage number indicator on left side */}
                  <div className="flex-shrink-0 flex flex-col items-center">
                    <div className="w-16 h-16 rounded-full bg-[var(--secondary)] border-2 border-[var(--border)] flex items-center justify-center text-sm font-semibold text-[var(--foreground-muted)]">
                      {index + 1}
                    </div>
                  </div>

                  {/* Stage Card */}
                  <div className={`flex-1 relative p-4 rounded-lg border-2 ${styles.container}`}>
                    {/* WHY: Current stage badge positioned at top-right on mobile */}
                    {stage.status === 'current' && (
                      <div className="absolute -top-2 -right-2 bg-[var(--accent)] text-white text-xs font-semibold px-2 py-1 rounded-full">
                        {t('timeline.you_are_here')}
                      </div>
                    )}

                    {/* Icon and Title in Row */}
                    <div className="flex items-center space-x-3">
                      <div className={`w-12 h-12 rounded-full flex items-center justify-center flex-shrink-0 ${styles.icon}`}>
                        {renderIcon(stage.icon, 'h-6 w-6')}
                      </div>
                      <h4 className={`text-sm font-medium ${styles.title}`}>
                        {stage.title}
                      </h4>
                    </div>

                    {/* Description */}
                    <p className={`text-xs mt-2 ${styles.description}`}>
                      {stage.description}
                    </p>

                    {/* Duration */}
                    {stage.duration && (
                      <div className="text-xs text-[var(--foreground-subtle)] mt-2 font-medium">
                        {t('onboarding.duration_label')} {stage.duration}
                      </div>
                    )}

                    {/* Coming Soon */}
                    {stage.status === 'future' && (
                      <div className="text-xs text-[var(--foreground-subtle)] mt-2 italic">
                        {t('timeline.coming_soon')}
                      </div>
                    )}

                    {/* Status Icon */}
                    {stage.status === 'completed' && (
                      <CheckCircle className="absolute top-4 right-4 h-5 w-5 text-[var(--success)]" />
                    )}
                    {stage.status === 'future' && (
                      <Lock className="absolute top-4 right-4 h-5 w-5 text-[var(--foreground-subtle)]" />
                    )}
                  </div>
                </div>
              </div>
            )
          })}
        </div>
      </div>
    </div>
  )
}
