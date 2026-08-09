interface DotPatternProps {
  className?: string
  /** Position preset: 'top-left' | 'top-right' | 'top-center' | 'custom' */
  position?: 'top-left' | 'top-right' | 'top-center' | 'custom'
}

export function DotPattern({ className = '', position = 'top-left' }: DotPatternProps) {
  const positionClasses = {
    'top-left': 'top-0 left-0',
    'top-right': 'top-0 right-0',
    'top-center': 'top-0 left-1/2 -translate-x-1/2',
    'custom': ''
  }

  return (
    <div
      className={`pointer-events-none absolute overflow-hidden ${positionClasses[position]} ${className}`}
      aria-hidden="true"
    >
      <svg
        width="581"
        height="569"
        viewBox="0 0 581 569"
        fill="none"
        xmlns="http://www.w3.org/2000/svg"
        className="text-white"
      >
        <defs>
          <pattern
            id="dot-pattern"
            x="0"
            y="0"
            width="24"
            height="24"
            patternUnits="userSpaceOnUse"
          >
            <circle cx="2" cy="2" r="1.5" fill="currentColor" fillOpacity="0.3" />
          </pattern>
          {/* Radial gradient mask for fade effect at edges - per Figma design */}
          <radialGradient id="dot-fade" cx="50%" cy="0%" r="70%" fx="50%" fy="0%">
            <stop offset="0%" stopColor="white" stopOpacity="1" />
            <stop offset="70%" stopColor="white" stopOpacity="0.5" />
            <stop offset="100%" stopColor="white" stopOpacity="0" />
          </radialGradient>
          <mask id="dot-mask">
            <rect width="581" height="569" fill="url(#dot-fade)" />
          </mask>
        </defs>
        <rect width="581" height="569" fill="url(#dot-pattern)" mask="url(#dot-mask)" />
      </svg>
    </div>
  )
}

export default DotPattern
