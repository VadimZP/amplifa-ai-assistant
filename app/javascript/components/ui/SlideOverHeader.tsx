import { X } from 'lucide-react'
import { Badge } from './Badge'

/**
 * SlideOverHeader - Gradient header component for slide-over panels
 * Based on Figma node 201:3255 (header section of 201:3253)
 *
 * Design specs:
 * - Padding: pt-16px, pr-16px, pb-24px, pl-24px (asymmetric)
 * - Background: #212121 base with gradient image overlay
 * - Border: 1px solid rgba(255,255,255,0.1)
 * - Shadow: shadow-xs
 * - Flex column layout with close button top-right
 * - Badge and title below close button
 * - Title: 24px Geist SemiBold, white, line-height 32px
 */

export interface SlideOverHeaderProps {
  /** Title text displayed at the bottom of the header */
  title: string
  /** Status badge configuration */
  badge?: {
    label: string
    variant: 'draft' | 'approved' | 'default'
  }
  /** Gradient variant for the background overlay */
  gradient?: 'orange' | 'green' | 'blue' | 'purple'
  /** Close button handler */
  onClose: () => void
  /** Additional className for customization */
  className?: string
  /** Optional avatar/profile photo URL */
  avatarUrl?: string | null
}

/**
 * Get the gradient image path based on variant
 */
function getGradientImage(gradient?: SlideOverHeaderProps['gradient']): string | null {
  if (!gradient) return null

  // Cache-busting version - increment to force browser to reload images
  const version = 'v2'

  const gradients: Record<NonNullable<SlideOverHeaderProps['gradient']>, string> = {
    orange: `/card-gradient-orange.jpg?${version}`,
    green: `/card-gradient-green.jpg?${version}`,
    blue: `/card-gradient-blue.jpg?${version}`,
    purple: `/card-gradient-purple.jpg?${version}`,
  }

  return gradients[gradient]
}

export function SlideOverHeader({
  title,
  badge,
  gradient = 'orange',
  onClose,
  className = '',
  avatarUrl,
}: SlideOverHeaderProps) {
  const gradientImage = getGradientImage(gradient)

  return (
    <div
      className={`
        relative w-full shrink-0
        border-b border-white/[0.06]
        overflow-clip
        ${className}
      `}
    >
      <div aria-hidden="true" className="absolute inset-0 pointer-events-none">
        <div className="absolute inset-0 bg-[linear-gradient(180deg,#232932_0%,#1c2128_62%,#171b21_100%)]" />
        <div className="absolute inset-0 bg-[radial-gradient(circle_at_top_left,rgba(53,202,222,0.18),transparent_34%)]" />
        {gradientImage && (
          <img
            alt=""
            className="absolute inset-0 h-full w-full object-cover object-center opacity-[0.18] mix-blend-screen"
            src={gradientImage}
          />
        )}
        <div className="absolute inset-0 bg-[linear-gradient(180deg,transparent,rgba(10,12,16,0.25))]" />
      </div>

      <div className="relative flex flex-col items-end gap-5 px-7 pb-7 pt-5">
        <button
          type="button"
          className="
            flex shrink-0 size-10 items-center justify-center rounded-full
            border border-white/[0.08]
            bg-white/[0.05]
            flex items-center justify-center
            text-[var(--foreground-muted)] hover:text-white
            hover:bg-white/[0.1]
            transition-colors duration-150
            focus:outline-none focus-visible:ring-2 focus-visible:ring-[var(--ring)] focus-visible:rounded-full
          "
          onClick={onClose}
          aria-label="Close panel"
        >
          <X className="size-5" />
        </button>

        <div className="flex w-full flex-col items-start gap-4">
          {badge && (
            <Badge variant={badge.variant}>
              {badge.label}
            </Badge>
          )}

          <div className="flex w-full items-center gap-4">
            {avatarUrl && (
              <img
                src={avatarUrl}
                alt=""
                className="size-16 shrink-0 rounded-full border-2 border-white/20 object-cover shadow-[0_12px_30px_rgba(0,0,0,0.2)]"
              />
            )}
            <h2 className="text-[28px] font-semibold leading-[1.15] tracking-[-0.03em] text-white">
              {title}
            </h2>
          </div>
        </div>
      </div>
    </div>
  )
}

export default SlideOverHeader
