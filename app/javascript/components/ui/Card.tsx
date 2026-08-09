import * as React from 'react'

/**
 * Card component with sub-components for structured content
 * Based on Figma nodes 201:7357 (form card) and 195:5065 (playbook card)
 */

export interface CardProps extends React.HTMLAttributes<HTMLDivElement> {
  /** Card variant - 'default' for forms, 'playbook' for dashboard cards */
  variant?: 'default' | 'playbook'
  /** Optional gradient overlay for playbook cards */
  gradient?: 'orange' | 'green' | 'blue' | 'purple'
}

/**
 * Get gradient image path for playbook cards
 * Uses downloaded Figma gradient images for pixel-perfect matching
 */
function getGradientImage(gradient?: CardProps['gradient']): string | null {
  if (!gradient) return null

  // Cache-busting version - increment to force browser to reload images
  const version = 'v2'

  const gradients: Record<NonNullable<CardProps['gradient']>, string> = {
    orange: `/card-gradient-orange.jpg?${version}`,
    green: `/card-gradient-green.jpg?${version}`,
    blue: `/card-gradient-blue.jpg?${version}`,
    purple: `/card-gradient-purple.jpg?${version}`,
  }

  return gradients[gradient]
}

/**
 * Main Card container
 *
 * Form Card (default): #171717 bg, 14px radius, 24px padding
 * Playbook Card: #212121 bg, 10px radius, custom padding with gradient overlay
 */
export function Card({
  className = '',
  variant = 'default',
  gradient,
  children,
  ...props
}: CardProps) {
  const isPlaybook = variant === 'playbook'

  // Base classes for all cards
  const baseClasses = [
    'relative',
    'overflow-hidden',
    'border',
    'border-[var(--border)]',
    'shadow-[var(--shadow-sm)]',
    'before:pointer-events-none',
    'before:absolute',
    'before:inset-0',
    'before:bg-[linear-gradient(180deg,rgba(255,255,255,0.035),transparent_32%)]',
    'before:content-[""]',
  ].join(' ')

  // Variant-specific classes
  const variantClasses = isPlaybook
    ? [
        'bg-[#20252d]',
        'rounded-[22px]',
        'pt-5', // 20px
        'pb-8', // 32px
        'px-6', // 24px
        'flex',
        'flex-col',
        'justify-between',
      ].join(' ')
    : [
        'bg-[var(--card)]',
        'rounded-[24px]',
        'py-7',
        'flex',
        'flex-col',
        'gap-6', // 24px gap between sections
      ].join(' ')

  const gradientImage = getGradientImage(gradient)

  return (
    <div
      className={`${baseClasses} ${variantClasses} ${className}`}
      {...props}
    >
      {/* Gradient overlay for playbook cards - using Figma gradient images */}
      {isPlaybook && gradientImage && (
        <div className="absolute inset-0 pointer-events-none" aria-hidden="true">
          <img
            alt=""
            src={gradientImage}
            className="absolute inset-0 w-full h-full object-cover object-center"
          />
        </div>
      )}
      {/* Content container with relative positioning to appear above gradient */}
      <div className={isPlaybook ? 'relative flex h-full flex-col justify-between' : 'relative contents'}>
        {children}
      </div>
    </div>
  )
}

/**
 * Card header with title and optional description
 *
 * Title: 16px semibold, white
 * Description: 14px normal, muted gray (#a3a3a3)
 * Gap: 6px between title and description
 * Padding: 0 24px horizontal
 */
export interface CardHeaderProps extends React.HTMLAttributes<HTMLDivElement> {
  /** Optional description below title */
  description?: React.ReactNode
}

export function CardHeader({
  className = '',
  description,
  children,
  ...props
}: CardHeaderProps) {
  return (
    <div
      className={`px-7 shrink-0 ${className}`}
      {...props}
    >
      <div className="flex flex-col gap-2">
        {/* Title */}
        <div className="text-[17px] font-semibold text-[var(--foreground)] leading-tight tracking-[-0.01em]">
          {children}
        </div>
        {/* Description */}
        {description && (
          <div className="text-sm text-[var(--foreground-muted)] leading-6">
            {description}
          </div>
        )}
      </div>
    </div>
  )
}

/**
 * Card content area
 *
 * Padding: 0 24px horizontal
 * Flexible content area
 */
export type CardContentProps = React.HTMLAttributes<HTMLDivElement>

export function CardContent({
  className = '',
  children,
  ...props
}: CardContentProps) {
  return (
    <div
      className={`px-7 flex-1 ${className}`}
      {...props}
    >
      {children}
    </div>
  )
}

/**
 * Card footer with top border separator
 *
 * Border: 1px solid var(--border) on top
 * Padding: 24px top
 * Used for action buttons or footer content
 */
export interface CardFooterProps extends React.HTMLAttributes<HTMLDivElement> {
  /** Whether to show top border separator */
  bordered?: boolean
}

export function CardFooter({
  className = '',
  bordered = true,
  children,
  ...props
}: CardFooterProps) {
  return (
    <div
      className={`px-7 pt-6 shrink-0 ${bordered ? 'border-t border-[var(--border)]' : ''} ${className}`}
      {...props}
    >
      {children}
    </div>
  )
}

/**
 * Playbook card title - larger text at bottom of card
 *
 * Font: 24px medium, white
 * Line height: 32px
 */
export type CardTitleProps = React.HTMLAttributes<HTMLHeadingElement>

export function CardTitle({
  className = '',
  children,
  ...props
}: CardTitleProps) {
  return (
    <h3
      className={`text-[28px] font-semibold text-white leading-[1.15] tracking-[-0.03em] ${className}`}
      {...props}
    >
      {children}
    </h3>
  )
}

export default Card
