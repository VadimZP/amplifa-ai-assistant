import { useCallback, useEffect, useRef, useState } from 'react'
import { createPortal } from 'react-dom'
import { autoUpdate, computePosition, flip, offset, shift } from '@floating-ui/dom'
import { Sparkles } from 'lucide-react'
import { t } from '../../lib/i18n'

const SELECTION_MAX_LENGTH = 200
const MESSAGE_CONTENT_SELECTOR = '[data-assistant-message-content]'

interface AskAssistantSelectionToolbarProps {
  containerRef: React.RefObject<HTMLElement | null>
  onSelect: (text: string) => void
}

function trimSelection(text: string, max = SELECTION_MAX_LENGTH): string {
  const trimmed = text.trim()
  return trimmed.length > max ? `${trimmed.slice(0, max)}...` : trimmed
}

function getSelectionWithinContainer(container: HTMLElement): { text: string; range: Range } | null {
  const selection = window.getSelection()
  if (!selection || selection.isCollapsed || selection.rangeCount === 0) return null

  const range = selection.getRangeAt(0)
  const text = selection.toString()
  if (!text.trim()) return null

  const anchorNode = range.commonAncestorContainer
  const anchorElement = anchorNode instanceof Element ? anchorNode : anchorNode.parentElement
  if (!anchorElement?.closest(MESSAGE_CONTENT_SELECTOR)) return null
  if (!container.contains(anchorElement)) return null

  return { text, range }
}

export function AskAssistantSelectionToolbar({ containerRef, onSelect }: AskAssistantSelectionToolbarProps) {
  const toolbarRef = useRef<HTMLDivElement>(null)
  const [visible, setVisible] = useState(false)
  const [position, setPosition] = useState({ top: 0, left: 0 })
  const selectionRef = useRef<{ text: string; range: Range } | null>(null)

  const hide = useCallback(() => {
    setVisible(false)
    selectionRef.current = null
  }, [])

  const updateFromSelection = useCallback(() => {
    const container = containerRef.current
    if (!container) {
      hide()
      return
    }

    const match = getSelectionWithinContainer(container)
    if (!match) {
      hide()
      return
    }

    selectionRef.current = match
    setVisible(true)
  }, [containerRef, hide])

  useEffect(() => {
    const container = containerRef.current
    if (!container) return undefined

    const handleMouseUp = () => {
      // Defer so the browser finalizes the selection before we read it.
      requestAnimationFrame(updateFromSelection)
    }

    const handleSelectionChange = () => {
      updateFromSelection()
    }

    const handleScroll = () => {
      hide()
    }

    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') hide()
    }

    const handlePointerDown = (event: MouseEvent) => {
      const target = event.target
      if (!(target instanceof Node)) return
      if (toolbarRef.current?.contains(target)) return
      if (!container.contains(target)) hide()
    }

    container.addEventListener('mouseup', handleMouseUp)
    container.addEventListener('scroll', handleScroll, true)
    document.addEventListener('selectionchange', handleSelectionChange)
    document.addEventListener('keydown', handleKeyDown)
    document.addEventListener('mousedown', handlePointerDown)

    return () => {
      container.removeEventListener('mouseup', handleMouseUp)
      container.removeEventListener('scroll', handleScroll, true)
      document.removeEventListener('selectionchange', handleSelectionChange)
      document.removeEventListener('keydown', handleKeyDown)
      document.removeEventListener('mousedown', handlePointerDown)
    }
  }, [containerRef, hide, updateFromSelection])

  useEffect(() => {
    if (!visible || !selectionRef.current || !toolbarRef.current) return undefined

    const range = selectionRef.current.range
    const virtualElement = {
      getBoundingClientRect: () => range.getBoundingClientRect(),
    }

    return autoUpdate(virtualElement, toolbarRef.current, () => {
      if (!toolbarRef.current) return

      computePosition(virtualElement, toolbarRef.current, {
        placement: 'top',
        middleware: [offset(8), flip(), shift({ padding: 8 })],
      }).then(({ x, y }) => {
        setPosition({ top: y, left: x })
      })
    })
  }, [visible])

  const handleAsk = () => {
    const text = selectionRef.current?.text
    if (!text) return

    onSelect(trimSelection(text))
    window.getSelection()?.removeAllRanges()
    hide()
  }

  if (!visible) return null

  return createPortal(
    <div
      ref={toolbarRef}
      className="fixed z-50"
      style={{ top: position.top, left: position.left }}
    >
      <button
        type="button"
        onClick={handleAsk}
        className="inline-flex cursor-pointer items-center gap-1.5 rounded-full border border-[var(--border)] bg-[var(--background-elevated)] px-3 py-1.5 text-sm font-medium text-[var(--foreground)] shadow-[var(--shadow-md)] focus:outline-none focus-visible:shadow-[0_0_0_2px_var(--ring-offset),0_0_0_4px_var(--ring)]"
      >
        {t('assistant.selection.ask')}
        <Sparkles className="size-3.5 text-[var(--accent)]" aria-hidden />
      </button>
    </div>,
    document.body
  )
}

export default AskAssistantSelectionToolbar
