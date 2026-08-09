import { type CSSProperties, useEffect, useRef, useState } from 'react'

interface ExpandableTextProps {
  text: string
  collapsedLines?: number
  className?: string
  buttonClassName?: string
  seeMoreLabel: string
  seeLessLabel: string
}

export function ExpandableText({
  text,
  collapsedLines = 10,
  className = '',
  buttonClassName = '',
  seeMoreLabel,
  seeLessLabel
}: ExpandableTextProps) {
  const contentRef = useRef<HTMLParagraphElement | null>(null)
  const [isExpanded, setIsExpanded] = useState(false)
  const [isCollapsible, setIsCollapsible] = useState(false)
  const [collapsedHeight, setCollapsedHeight] = useState<number | null>(null)
  const [expandedHeight, setExpandedHeight] = useState<number | null>(null)

  useEffect(() => {
    const element = contentRef.current
    if (!element) return undefined

    const measure = () => {
      const computedStyle = window.getComputedStyle(element)
      const fontSize = Number.parseFloat(computedStyle.fontSize)
      const lineHeight = Number.parseFloat(computedStyle.lineHeight) || fontSize * 1.5
      const nextCollapsedHeight = lineHeight * collapsedLines
      const nextExpandedHeight = element.scrollHeight

      setCollapsedHeight(nextCollapsedHeight)
      setExpandedHeight(nextExpandedHeight)
      setIsCollapsible(nextExpandedHeight > nextCollapsedHeight + 1)
    }

    measure()

    const resizeObserver = new ResizeObserver(measure)
    resizeObserver.observe(element)
    window.addEventListener('resize', measure)

    return () => {
      resizeObserver.disconnect()
      window.removeEventListener('resize', measure)
    }
  }, [collapsedLines, text])

  const maxHeight = isCollapsible
    ? `${isExpanded ? expandedHeight ?? 0 : collapsedHeight ?? 0}px`
    : undefined
  const isCollapsed = isCollapsible && !isExpanded
  const contentStyle: CSSProperties = {
    maxHeight,
    WebkitMaskImage: isCollapsed ? 'linear-gradient(to bottom, #000 calc(100% - 3.5rem), transparent)' : undefined,
    maskImage: isCollapsed ? 'linear-gradient(to bottom, #000 calc(100% - 3.5rem), transparent)' : undefined
  }

  const toggleButtonClassName = `inline-flex items-center rounded-full border border-white/[0.12] bg-white/[0.05] px-3 py-1 text-xs font-semibold text-[var(--accent)] transition-colors hover:bg-white/[0.08] hover:text-[var(--accent-hover)] ${buttonClassName}`

  return (
    <div>
      <div className="relative">
        <div
          ref={contentRef}
          className={`transition-[max-height] duration-300 ease-out ${isCollapsible ? 'overflow-hidden' : ''} ${className}`}
          style={contentStyle}
        >
          {text}
          {isCollapsible && isExpanded && (
            <button
              type="button"
              onClick={() => setIsExpanded(false)}
              className={`ml-2 align-baseline ${toggleButtonClassName}`}
            >
              {seeLessLabel}
            </button>
          )}
        </div>
      </div>
      {isCollapsible && !isExpanded && (
        <button
          type="button"
          onClick={() => setIsExpanded(true)}
          className={`mt-3 ${toggleButtonClassName}`}
        >
          {seeMoreLabel}
        </button>
      )}
    </div>
  )
}
