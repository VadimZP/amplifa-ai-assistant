import { useState, useRef, useEffect } from 'react'
import { X, ChevronRight, ChevronLeft, Plus, CircleAlert, CircleCheck } from 'lucide-react'
import { SlideOver, SlideOverFooterButtons } from './SlideOver'
import { Badge } from './Badge'

/**
 * PlaybookDetailSlideOver - Shows playbook details in a slideover panel
 * Based on Figma node 201:3250 (Environmental Solutions - open)
 *
 * Design specs:
 * - Header: Gradient background with playbook name and badge
 * - Sections: Personas, Use Cases, References, Proof Points
 * - Each section has list items with chevron icons
 * - Footer with "Suggest Change" and "Approve" buttons
 * - Nested views for Persona detail (node 201:3652) and UseCase detail
 * - Smooth slide animations between views
 */

// Types for playbook detail data
export interface PlaybookPersona {
  id: number
  name: string
  description?: string
  level?: string
  jobTitles?: string[]
  painPoints?: string[]
  goals?: string[]
}

export interface PlaybookUseCase {
  id: number
  name: string
  description?: string
  benefits?: string[]
  challenges?: string[]
  successMetrics?: string[]
}

export interface PlaybookReference {
  id: number
  name: string
}

export interface PlaybookProofPoint {
  id: number
  name: string
}

// Navigation state for nested views
type SlideOverView =
  | { type: 'playbook' }
  | { type: 'persona'; persona: PlaybookPersona }
  | { type: 'useCase'; useCase: PlaybookUseCase }

export interface PlaybookDetail {
  id: number
  name: string
  status: 'draft' | 'approved' | 'changes_requested'
  gradient?: 'orange' | 'green' | 'blue' | 'purple'
  personas?: PlaybookPersona[]
  useCases?: PlaybookUseCase[]
  references?: PlaybookReference[]
  proofPoints?: PlaybookProofPoint[]
}

export interface PlaybookDetailSlideOverProps {
  /** Whether the slideover is open */
  open: boolean
  /** Close handler */
  onClose: () => void
  /** The playbook to display */
  playbook: PlaybookDetail | null
  /** Handler for approving the playbook */
  onApprove?: (playbookId: number) => void
  /** Handler for suggesting changes */
  onSuggestChange?: (playbookId: number) => void
  /** Handler for clicking a persona item */
  onPersonaClick?: (persona: PlaybookPersona) => void
  /** Handler for clicking a use case item */
  onUseCaseClick?: (useCase: PlaybookUseCase) => void
  /** Handler for clicking a reference item */
  onReferenceClick?: (reference: PlaybookReference) => void
  /** Handler for clicking a proof point item */
  onProofPointClick?: (proofPoint: PlaybookProofPoint) => void
  /** Handler for adding a new reference */
  onAddReference?: () => void
  /** Loading state for approve button */
  approveLoading?: boolean
}

/**
 * Get gradient image based on variant
 */
function getGradientImage(gradient?: 'orange' | 'green' | 'blue' | 'purple'): string {
  switch (gradient) {
    case 'orange':
      return '/playbook-gradient-orange.png'
    case 'green':
      return '/playbook-gradient-green.png'
    case 'blue':
      return '/playbook-gradient-blue.png'
    case 'purple':
      return '/playbook-gradient-purple.png'
    default:
      return '/playbook-gradient-blue.png'
  }
}

/**
 * Section component for grouping list items
 */
interface SectionProps {
  title: string
  children: React.ReactNode
}

function Section({ title, children }: SectionProps) {
  return (
    <div className="flex flex-col gap-3">
      <p className="text-sm text-[#a3a3a3] font-normal">
        {title}
      </p>
      {children}
    </div>
  )
}

/**
 * List item component with chevron
 */
interface ListItemProps {
  label: string
  onClick?: () => void
}

function ListItem({ label, onClick }: ListItemProps) {
  return (
    <button
      type="button"
      className="
        flex items-center justify-between w-full py-0
        text-sm font-medium text-white
        hover:text-white/80
        transition-colors duration-150
        focus:outline-none focus-visible:ring-1 focus-visible:ring-white/50 focus-visible:rounded
      "
      onClick={onClick}
      disabled={!onClick}
    >
      <span>{label}</span>
      <ChevronRight className="h-6 w-6 text-[#737373] shrink-0" />
    </button>
  )
}

/**
 * Divider component
 */
function Divider() {
  return (
    <div className="h-px w-full bg-[rgba(255,255,255,0.1)]" />
  )
}

/**
 * Add button component
 */
interface AddButtonProps {
  onClick?: () => void
}

function AddButton({ onClick }: AddButtonProps) {
  return (
    <button
      type="button"
      className="
        flex items-center gap-2 h-8 px-3 py-2
        bg-[rgba(255,255,255,0.05)]
        border border-[rgba(255,255,255,0.15)]
        rounded-lg
        text-xs font-medium text-[#fafafa]
        shadow-[0px_1px_2px_0px_rgba(0,0,0,0.05)]
        hover:bg-[rgba(255,255,255,0.1)]
        active:scale-[0.98]
        transition-all duration-150
        focus:outline-none focus-visible:ring-1 focus-visible:ring-white/50
      "
      onClick={onClick}
    >
      <Plus className="h-4 w-4" />
      <span>Add</span>
    </button>
  )
}

/**
 * Animation direction for view transitions
 */
type AnimationDirection = 'forward' | 'backward' | 'none'

/**
 * Animated view container for smooth transitions between views
 */
interface AnimatedViewProps {
  children: React.ReactNode
  direction: AnimationDirection
  viewKey: string
}

function AnimatedView({ children, direction, viewKey }: AnimatedViewProps) {
  const [displayedChildren, setDisplayedChildren] = useState(children)
  const [animationClass, setAnimationClass] = useState('')
  const prevKeyRef = useRef(viewKey)

  useEffect(() => {
    if (prevKeyRef.current !== viewKey && direction !== 'none') {
      // Start exit animation
      setAnimationClass(
        direction === 'forward'
          ? 'animate-slide-out-left'
          : 'animate-slide-out-right'
      )

      // After exit animation, swap content and start enter animation
      const exitTimer = setTimeout(() => {
        setDisplayedChildren(children)
        setAnimationClass(
          direction === 'forward'
            ? 'animate-slide-in-right'
            : 'animate-slide-in-left'
        )

        // After enter animation completes
        const enterTimer = setTimeout(() => {
          setAnimationClass('')
        }, 200)

        return () => clearTimeout(enterTimer)
      }, 200)

      prevKeyRef.current = viewKey
      return () => clearTimeout(exitTimer)
    } else {
      // No animation needed, just update content
      setDisplayedChildren(children)
      prevKeyRef.current = viewKey
    }
  }, [viewKey, children, direction])

  return (
    <div
      className={`flex flex-col ${animationClass}`}
      style={{
        // CSS animations defined inline for simplicity
        ...(animationClass === 'animate-slide-out-left' && {
          animation: 'slideOutLeft 200ms ease-out forwards',
        }),
        ...(animationClass === 'animate-slide-out-right' && {
          animation: 'slideOutRight 200ms ease-out forwards',
        }),
        ...(animationClass === 'animate-slide-in-right' && {
          animation: 'slideInRight 200ms ease-out forwards',
        }),
        ...(animationClass === 'animate-slide-in-left' && {
          animation: 'slideInLeft 200ms ease-out forwards',
        }),
      }}
    >
      <style>{`
        @keyframes slideOutLeft {
          from { transform: translateX(0); opacity: 1; }
          to { transform: translateX(-30px); opacity: 0; }
        }
        @keyframes slideOutRight {
          from { transform: translateX(0); opacity: 1; }
          to { transform: translateX(30px); opacity: 0; }
        }
        @keyframes slideInRight {
          from { transform: translateX(30px); opacity: 0; }
          to { transform: translateX(0); opacity: 1; }
        }
        @keyframes slideInLeft {
          from { transform: translateX(-30px); opacity: 0; }
          to { transform: translateX(0); opacity: 1; }
        }
      `}</style>
      {displayedChildren}
    </div>
  )
}

/**
 * Breadcrumb navigation for nested views
 */
interface BreadcrumbProps {
  label: string
  onBack: () => void
}

function Breadcrumb({ label, onBack }: BreadcrumbProps) {
  return (
    <button
      type="button"
      className="
        flex items-center gap-2
        text-sm text-[#a3a3a3]
        hover:text-white
        transition-colors duration-150
        focus:outline-none focus-visible:ring-1 focus-visible:ring-white/50 focus-visible:rounded
      "
      onClick={onBack}
    >
      <ChevronLeft className="h-4 w-4" />
      <Badge variant="outline" size="sm">{label}</Badge>
    </button>
  )
}

/**
 * Badge list component for job titles and similar lists
 */
interface BadgeListProps {
  items: string[]
}

function BadgeList({ items }: BadgeListProps) {
  return (
    <div className="flex flex-wrap gap-2">
      {items.map((item, index) => (
        <Badge key={index} variant="outline" size="sm">
          {item}
        </Badge>
      ))}
    </div>
  )
}

/**
 * List item with icon for pain points and goals
 */
interface IconListItemProps {
  icon: 'alert' | 'check'
  label: string
}

function IconListItem({ icon, label }: IconListItemProps) {
  return (
    <div className="flex items-start gap-3">
      {icon === 'alert' ? (
        <CircleAlert className="h-5 w-5 text-red-400 shrink-0 mt-0.5" />
      ) : (
        <CircleCheck className="h-5 w-5 text-green-400 shrink-0 mt-0.5" />
      )}
      <span className="text-sm text-white">{label}</span>
    </div>
  )
}

/**
 * Section with count badge in title
 */
interface SectionWithCountProps {
  title: string
  count: number
  children: React.ReactNode
}

function SectionWithCount({ title, count, children }: SectionWithCountProps) {
  return (
    <div className="flex flex-col gap-3">
      <div className="flex items-center gap-2">
        <p className="text-sm text-[#a3a3a3] font-normal">{title}</p>
        <Badge variant="outline" size="sm">{count}</Badge>
      </div>
      {children}
    </div>
  )
}

/**
 * PersonaDetailView - Shows detailed persona information
 * Based on Figma node 201:3652
 */
interface PersonaDetailViewProps {
  persona: PlaybookPersona
  gradient?: 'orange' | 'green' | 'blue' | 'purple'
  onBack: () => void
  onClose: () => void
}

function PersonaDetailView({ persona, gradient, onBack, onClose }: PersonaDetailViewProps) {
  return (
    <>
      {/* Header with gradient background */}
      <div
        className="relative flex flex-col gap-4 p-6 pt-4 pb-6 border-b border-[rgba(255,255,255,0.1)] overflow-hidden"
      >
        {/* Background layers */}
        <div aria-hidden="true" className="absolute inset-0 pointer-events-none">
          <div className="absolute inset-0 bg-[#212121]" />
          <img
            src={getGradientImage(gradient)}
            alt=""
            className="absolute inset-0 w-full h-full object-cover object-center"
          />
        </div>

        {/* Close button */}
        <div className="flex justify-end relative z-10">
          <button
            type="button"
            className="
              p-0.5 rounded-md
              text-white hover:text-white/80
              hover:bg-white/10
              transition-colors duration-150
              focus:outline-none focus-visible:ring-2 focus-visible:ring-white/50
            "
            onClick={onClose}
            aria-label="Close panel"
          >
            <X className="h-6 w-6" />
          </button>
        </div>

        {/* Breadcrumb and title */}
        <div className="flex flex-col gap-4 relative z-10">
          <Breadcrumb label="Personas" onBack={onBack} />

          <h2 className="text-2xl font-semibold text-white leading-8">
            {persona.name}
          </h2>

          {persona.description && (
            <p className="text-sm text-[#a3a3a3]">{persona.description}</p>
          )}

          {persona.level && (
            <Badge variant="cyan" size="sm">{persona.level}</Badge>
          )}
        </div>
      </div>

      {/* Content sections */}
      <div className="flex flex-col gap-6 p-6">
        {/* Job Titles */}
        {persona.jobTitles && persona.jobTitles.length > 0 && (
          <>
            <SectionWithCount title="Job Titles" count={persona.jobTitles.length}>
              <BadgeList items={persona.jobTitles} />
            </SectionWithCount>
            <Divider />
          </>
        )}

        {/* Pain Points */}
        {persona.painPoints && persona.painPoints.length > 0 && (
          <>
            <SectionWithCount title="Pain Points" count={persona.painPoints.length}>
              <div className="flex flex-col gap-3">
                {persona.painPoints.map((point, index) => (
                  <IconListItem key={index} icon="alert" label={point} />
                ))}
              </div>
            </SectionWithCount>
            <Divider />
          </>
        )}

        {/* Goals */}
        {persona.goals && persona.goals.length > 0 && (
          <SectionWithCount title="Goals" count={persona.goals.length}>
            <div className="flex flex-col gap-3">
              {persona.goals.map((goal, index) => (
                <IconListItem key={index} icon="check" label={goal} />
              ))}
            </div>
          </SectionWithCount>
        )}
      </div>
    </>
  )
}

/**
 * UseCaseDetailView - Shows detailed use case information
 */
interface UseCaseDetailViewProps {
  useCase: PlaybookUseCase
  gradient?: 'orange' | 'green' | 'blue' | 'purple'
  onBack: () => void
  onClose: () => void
}

function UseCaseDetailView({ useCase, gradient, onBack, onClose }: UseCaseDetailViewProps) {
  return (
    <>
      {/* Header with gradient background */}
      <div
        className="relative flex flex-col gap-4 p-6 pt-4 pb-6 border-b border-[rgba(255,255,255,0.1)] overflow-hidden"
      >
        {/* Background layers */}
        <div aria-hidden="true" className="absolute inset-0 pointer-events-none">
          <div className="absolute inset-0 bg-[#212121]" />
          <img
            src={getGradientImage(gradient)}
            alt=""
            className="absolute inset-0 w-full h-full object-cover object-center"
          />
        </div>

        {/* Close button */}
        <div className="flex justify-end relative z-10">
          <button
            type="button"
            className="
              p-0.5 rounded-md
              text-white hover:text-white/80
              hover:bg-white/10
              transition-colors duration-150
              focus:outline-none focus-visible:ring-2 focus-visible:ring-white/50
            "
            onClick={onClose}
            aria-label="Close panel"
          >
            <X className="h-6 w-6" />
          </button>
        </div>

        {/* Breadcrumb and title */}
        <div className="flex flex-col gap-4 relative z-10">
          <Breadcrumb label="Use Cases" onBack={onBack} />

          <h2 className="text-2xl font-semibold text-white leading-8">
            {useCase.name}
          </h2>

          {useCase.description && (
            <p className="text-sm text-[#a3a3a3]">{useCase.description}</p>
          )}
        </div>
      </div>

      {/* Content sections */}
      <div className="flex flex-col gap-6 p-6">
        {/* Benefits */}
        {useCase.benefits && useCase.benefits.length > 0 && (
          <>
            <SectionWithCount title="Benefits" count={useCase.benefits.length}>
              <div className="flex flex-col gap-3">
                {useCase.benefits.map((benefit, index) => (
                  <IconListItem key={index} icon="check" label={benefit} />
                ))}
              </div>
            </SectionWithCount>
            <Divider />
          </>
        )}

        {/* Challenges */}
        {useCase.challenges && useCase.challenges.length > 0 && (
          <>
            <SectionWithCount title="Challenges" count={useCase.challenges.length}>
              <div className="flex flex-col gap-3">
                {useCase.challenges.map((challenge, index) => (
                  <IconListItem key={index} icon="alert" label={challenge} />
                ))}
              </div>
            </SectionWithCount>
            <Divider />
          </>
        )}

        {/* Success Metrics */}
        {useCase.successMetrics && useCase.successMetrics.length > 0 && (
          <SectionWithCount title="Success Metrics" count={useCase.successMetrics.length}>
            <BadgeList items={useCase.successMetrics} />
          </SectionWithCount>
        )}
      </div>
    </>
  )
}

export function PlaybookDetailSlideOver({
  open,
  onClose,
  playbook,
  onApprove,
  onSuggestChange,
  onPersonaClick,
  onUseCaseClick,
  onReferenceClick,
  onProofPointClick,
  onAddReference,
  approveLoading = false,
}: PlaybookDetailSlideOverProps) {
  // Navigation state for nested views
  const [currentView, setCurrentView] = useState<SlideOverView>({ type: 'playbook' })
  // Animation direction state
  const [animationDirection, setAnimationDirection] = useState<AnimationDirection>('none')

  // Reset view when slideover closes or playbook changes
  const handleClose = () => {
    setAnimationDirection('none')
    setCurrentView({ type: 'playbook' })
    onClose()
  }

  const handleBack = () => {
    setAnimationDirection('backward')
    setCurrentView({ type: 'playbook' })
  }

  const handlePersonaClick = (persona: PlaybookPersona) => {
    // Navigate to persona detail view with forward animation
    setAnimationDirection('forward')
    setCurrentView({ type: 'persona', persona })
    // Also call external handler if provided
    onPersonaClick?.(persona)
  }

  const handleUseCaseClick = (useCase: PlaybookUseCase) => {
    // Navigate to use case detail view with forward animation
    setAnimationDirection('forward')
    setCurrentView({ type: 'useCase', useCase })
    // Also call external handler if provided
    onUseCaseClick?.(useCase)
  }

  if (!playbook) return null

  const badgeVariant = playbook.status === 'approved' ? 'approved' : 'draft'
  const badgeLabel = playbook.status === 'approved' ? 'Approved' : 'Draft'
  const isApproved = playbook.status === 'approved'

  // Determine view key for animation
  const viewKey = currentView.type === 'playbook'
    ? 'playbook'
    : currentView.type === 'persona'
      ? `persona-${currentView.persona.id}`
      : `useCase-${currentView.useCase.id}`

  // Determine footer based on current view
  const footer = currentView.type === 'playbook' ? (
    <SlideOverFooterButtons
      primaryLabel={isApproved ? 'Approved' : 'Approve'}
      onPrimary={() => onApprove?.(playbook.id)}
      primaryDisabled={isApproved}
      primaryLoading={approveLoading}
      secondaryLabel="Suggest Change"
      onSecondary={() => onSuggestChange?.(playbook.id)}
    />
  ) : (
    <SlideOverFooterButtons
      primaryLabel="Back"
      onPrimary={handleBack}
    />
  )

  // Render content based on current view
  const renderContent = () => {
    if (currentView.type === 'persona') {
      return (
        <PersonaDetailView
          persona={currentView.persona}
          gradient={playbook.gradient}
          onBack={handleBack}
          onClose={handleClose}
        />
      )
    }

    if (currentView.type === 'useCase') {
      return (
        <UseCaseDetailView
          useCase={currentView.useCase}
          gradient={playbook.gradient}
          onBack={handleBack}
          onClose={handleClose}
        />
      )
    }

    // Default: playbook detail view
    return (
      <>
        {/* Header with gradient background */}
        <div
          className="relative flex flex-col gap-4 p-6 pt-4 pb-6 border-b border-[rgba(255,255,255,0.1)] overflow-hidden"
        >
          {/* Background layers - below content */}
          <div aria-hidden="true" className="absolute inset-0 pointer-events-none">
            <div className="absolute inset-0 bg-[#212121]" />
            <img
              src={getGradientImage(playbook.gradient)}
              alt=""
              className="absolute inset-0 w-full h-full object-cover object-center"
            />
          </div>

          {/* Close button */}
          <div className="flex justify-end relative z-10">
            <button
              type="button"
              className="
                p-0.5 rounded-md
                text-white hover:text-white/80
                hover:bg-white/10
                transition-colors duration-150
                focus:outline-none focus-visible:ring-2 focus-visible:ring-white/50
              "
              onClick={handleClose}
              aria-label="Close panel"
            >
              <X className="h-6 w-6" />
            </button>
          </div>

          {/* Badge and title */}
          <div className="flex flex-col gap-4 relative z-10">
            <Badge variant={badgeVariant}>
              {badgeLabel}
            </Badge>

            <h2 className="text-2xl font-semibold text-white leading-8">
              {playbook.name}
            </h2>
          </div>
        </div>

        {/* Content sections */}
        <div className="flex flex-col gap-6 p-6">
          {/* Personas */}
          {playbook.personas && playbook.personas.length > 0 && (
            <>
              <Section title="Personas">
                <div className="flex flex-col gap-3">
                  {playbook.personas.map((persona) => (
                    <ListItem
                      key={persona.id}
                      label={persona.name}
                      onClick={() => handlePersonaClick(persona)}
                    />
                  ))}
                </div>
              </Section>
              <Divider />
            </>
          )}

          {/* Use Cases */}
          {playbook.useCases && playbook.useCases.length > 0 && (
            <>
              <Section title="Use Cases">
                <div className="flex flex-col gap-4">
                  {playbook.useCases.map((useCase) => (
                    <ListItem
                      key={useCase.id}
                      label={useCase.name}
                      onClick={() => handleUseCaseClick(useCase)}
                    />
                  ))}
                </div>
              </Section>
              <Divider />
            </>
          )}

          {/* References */}
          <Section title="References">
            <div className="flex flex-col gap-4">
              {playbook.references && playbook.references.length > 0 && (
                playbook.references.map((reference) => (
                  <ListItem
                    key={reference.id}
                    label={reference.name}
                    onClick={onReferenceClick ? () => onReferenceClick(reference) : undefined}
                  />
                ))
              )}
              <AddButton onClick={onAddReference} />
            </div>
          </Section>
          <Divider />

          {/* Proof Points */}
          {playbook.proofPoints && playbook.proofPoints.length > 0 && (
            <Section title="Proof Points">
              <div className="flex flex-col gap-4">
                {playbook.proofPoints.map((proofPoint) => (
                  <ListItem
                    key={proofPoint.id}
                    label={proofPoint.name}
                    onClick={onProofPointClick ? () => onProofPointClick(proofPoint) : undefined}
                  />
                ))}
              </div>
            </Section>
          )}
        </div>
      </>
    )
  }

  return (
    <SlideOver
      open={open}
      onClose={handleClose}
      width="md"
      footer={footer}
    >
      <AnimatedView direction={animationDirection} viewKey={viewKey}>
        {renderContent()}
      </AnimatedView>
    </SlideOver>
  )
}

export default PlaybookDetailSlideOver
