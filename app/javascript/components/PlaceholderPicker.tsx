import { useRef, useEffect, useLayoutEffect, useState } from 'react'
import type { Placeholder } from '../lib/placeholders'
import { clampToViewport } from '../lib/clampToViewport'
import type { CaretPosition } from '../lib/getCaretCoordinates'

interface PlaceholderPickerProps {
  isOpen: boolean
  filteredPlaceholders: Placeholder[]
  highlightedIndex: number
  caretPosition?: CaretPosition | null
  onSelect: (placeholder: Placeholder) => void
  onClose: () => void
  anchorRef: React.RefObject<HTMLInputElement | HTMLTextAreaElement | null>
}

export function PlaceholderPicker({
  isOpen,
  filteredPlaceholders,
  highlightedIndex,
  caretPosition,
  onSelect,
  onClose,
  anchorRef
}: PlaceholderPickerProps) {
  const dropdownRef = useRef<HTMLDivElement>(null)
  const listRef = useRef<HTMLDivElement>(null)
  const [dropdownSize, setDropdownSize] = useState({ width: 0, height: 0 })
  const gap = 8

  useEffect(() => {
    if (isOpen && listRef.current) {
      const highlighted = listRef.current.querySelector('[data-highlighted="true"]')
      if (highlighted) {
        highlighted.scrollIntoView({ block: 'nearest' })
      }
    }
  }, [highlightedIndex, isOpen])

  useLayoutEffect(() => {
    if (isOpen && dropdownRef.current) {
      const rect = dropdownRef.current.getBoundingClientRect()
      setDropdownSize({ width: rect.width, height: rect.height })
    }
  }, [isOpen, filteredPlaceholders.length])

  if (!isOpen) return null

  const getDropdownPosition = () => {
    if (!anchorRef.current) return { top: 0, left: 0 }
    const viewport = { width: window.innerWidth, height: window.innerHeight }
    const size = dropdownSize
    const padding = 8
    const estimatedHeight = size.height || 256

    if (caretPosition) {
      const belowTop = caretPosition.top + caretPosition.height + gap
      const aboveTop = caretPosition.top - estimatedHeight - gap
      const spaceBelow = viewport.height - padding - belowTop
      const spaceAbove = caretPosition.top - padding - gap
      const shouldFlip = spaceBelow < estimatedHeight && spaceAbove > 0
      const base = {
        top: shouldFlip ? aboveTop : belowTop,
        left: caretPosition.left
      }
      const clampFlipTop = Math.min(
        aboveTop,
        caretPosition.top - padding - estimatedHeight
      )
      const clamped = clampToViewport(base, size, viewport, { padding, flipTop: clampFlipTop })
      if (shouldFlip) {
        clamped.top = Math.min(clamped.top, caretPosition.top - gap - estimatedHeight - 1)
      }
      return clamped
    }

    const rect = anchorRef.current.getBoundingClientRect()
    const base = { top: rect.bottom + gap, left: rect.left }
    const flipTop = rect.top - size.height - gap
    return clampToViewport(base, size, viewport, { padding, flipTop })
  }

  const position = getDropdownPosition()

  return (
    <>
      <div
        className="fixed inset-0 z-[100]"
        onClick={onClose}
        aria-hidden="true"
      />
      
      <div
        ref={dropdownRef}
        className="fixed z-[101] w-64 max-h-64 overflow-hidden rounded-lg shadow-lg bg-[var(--card)] border border-[var(--border)]"
        style={{
          top: position.top,
          left: position.left,
          maxHeight: caretPosition
            ? Math.min(
                256,
                Math.max(
                  0,
                  position.top < caretPosition.top
                    ? caretPosition.top - gap - position.top
                    : window.innerHeight - position.top - gap
                )
              )
            : undefined
        }}
      >
        {filteredPlaceholders.length === 0 ? (
          <div className="px-3 py-2 text-sm text-[var(--foreground-muted)]">
            No matching placeholders
          </div>
        ) : (
          <div ref={listRef} className="overflow-y-auto overflow-x-hidden max-h-64 py-1">
            {filteredPlaceholders.map((placeholder, index) => (
              <button
                key={placeholder.name}
                type="button"
                data-highlighted={index === highlightedIndex}
                onClick={() => onSelect(placeholder)}
                className={`w-full text-left px-3 py-1.5 text-sm font-mono transition-colors ${
                  index === highlightedIndex
                    ? 'bg-[var(--accent)]/10 text-[var(--accent)]'
                    : 'text-[var(--foreground)] hover:bg-[var(--secondary)]'
                }`}
              >
                {placeholder.value}
              </button>
            ))}
          </div>
        )}
      </div>
    </>
  )
}
