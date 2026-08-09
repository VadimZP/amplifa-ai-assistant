import { useState, useMemo, useCallback, useRef } from 'react'
import type { Placeholder } from '../lib/placeholders'
import { getCaretCoordinates } from '../lib/getCaretCoordinates'
import type { CaretPosition } from '../lib/getCaretCoordinates'

interface UsePlaceholderPickerReturn {
  isOpen: boolean
  searchQuery: string
  filteredPlaceholders: Placeholder[]
  highlightedIndex: number
  caretPosition: CaretPosition | null
  triggerPosition: number
  handleKeyDown: (
    e: React.KeyboardEvent<HTMLInputElement | HTMLTextAreaElement>,
    inputRef: React.RefObject<HTMLInputElement | HTMLTextAreaElement | null>,
    currentValue: string,
    setValue: (v: string) => void
  ) => void
  handleChange: (
    inputRef: React.RefObject<HTMLInputElement | HTMLTextAreaElement | null>,
    newValue: string,
    cursorPosition: number
  ) => void
  handleScroll: (inputRef: React.RefObject<HTMLInputElement | HTMLTextAreaElement | null>) => void
  selectPlaceholder: (
    placeholder: Placeholder,
    inputRef: React.RefObject<HTMLInputElement | HTMLTextAreaElement | null>,
    currentValue: string,
    setValue: (v: string) => void
  ) => void
  close: (
    inputRef: React.RefObject<HTMLInputElement | HTMLTextAreaElement | null>,
    currentValue: string,
    setValue: (v: string) => void
  ) => void
}

export function usePlaceholderPicker(placeholders: Placeholder[]): UsePlaceholderPickerReturn {
  const [isOpen, setIsOpen] = useState(false)
  const [searchQuery, setSearchQuery] = useState('')
  const [highlightedIndex, setHighlightedIndex] = useState(0)
  const [caretPosition, setCaretPosition] = useState<CaretPosition | null>(null)
  const [triggerPosition, setTriggerPosition] = useState(0)
  const slashPositionRef = useRef<number>(-1)
  const rafRef = useRef<number | null>(null)

  const filteredPlaceholders = useMemo(() => {
    if (!searchQuery) return placeholders
    const query = searchQuery.toLowerCase()
    return placeholders.filter(p => p.name.toLowerCase().includes(query))
  }, [placeholders, searchQuery])

  const resetState = useCallback(() => {
    setIsOpen(false)
    setSearchQuery('')
    setHighlightedIndex(0)
    setCaretPosition(null)
    setTriggerPosition(0)
    slashPositionRef.current = -1
    if (rafRef.current !== null) {
      cancelAnimationFrame(rafRef.current)
      rafRef.current = null
    }
  }, [])

  const scheduleCaretUpdate = useCallback((
    inputRef: React.RefObject<HTMLInputElement | HTMLTextAreaElement | null>
  ) => {
    if (!inputRef.current) return
    if (rafRef.current !== null) {
      cancelAnimationFrame(rafRef.current)
    }
    rafRef.current = requestAnimationFrame(() => {
      if (!inputRef.current) return
      const position = inputRef.current.selectionStart ?? 0
      setCaretPosition(getCaretCoordinates(inputRef.current, position))
    })
  }, [])

  const close = useCallback((
    inputRef: React.RefObject<HTMLInputElement | HTMLTextAreaElement | null>,
    currentValue: string,
    setValue: (v: string) => void
  ) => {
    if (slashPositionRef.current >= 0) {
      const before = currentValue.slice(0, slashPositionRef.current)
      const afterSlashAndQuery = currentValue.slice(slashPositionRef.current + 1 + searchQuery.length)
      const newValue = before + afterSlashAndQuery
      setValue(newValue)

      requestAnimationFrame(() => {
        if (inputRef.current) {
          inputRef.current.selectionStart = slashPositionRef.current
          inputRef.current.selectionEnd = slashPositionRef.current
        }
      })
    }
    resetState()
  }, [searchQuery, resetState])

  const selectPlaceholder = useCallback((
    placeholder: Placeholder,
    inputRef: React.RefObject<HTMLInputElement | HTMLTextAreaElement | null>,
    currentValue: string,
    setValue: (v: string) => void
  ) => {
    if (slashPositionRef.current < 0) return

    const before = currentValue.slice(0, slashPositionRef.current)
    const afterSlashAndQuery = currentValue.slice(slashPositionRef.current + 1 + searchQuery.length)
    const newValue = before + placeholder.value + afterSlashAndQuery
    const newCursorPos = slashPositionRef.current + placeholder.value.length

    setValue(newValue)

    requestAnimationFrame(() => {
      if (inputRef.current) {
        inputRef.current.selectionStart = newCursorPos
        inputRef.current.selectionEnd = newCursorPos
        inputRef.current.focus()
      }
    })

    resetState()
  }, [searchQuery, resetState])

  const handleKeyDown = useCallback((
    e: React.KeyboardEvent<HTMLInputElement | HTMLTextAreaElement>,
    inputRef: React.RefObject<HTMLInputElement | HTMLTextAreaElement | null>,
    currentValue: string,
    setValue: (v: string) => void
  ) => {
    if (!isOpen) return

    switch (e.key) {
      case 'ArrowDown':
        e.preventDefault()
        setHighlightedIndex(prev => 
          prev >= filteredPlaceholders.length - 1 ? 0 : prev + 1
        )
        break

      case 'ArrowUp':
        e.preventDefault()
        setHighlightedIndex(prev => 
          prev <= 0 ? filteredPlaceholders.length - 1 : prev - 1
        )
        break

      case 'Enter':
        e.preventDefault()
        if (filteredPlaceholders.length > 0) {
          selectPlaceholder(filteredPlaceholders[highlightedIndex], inputRef, currentValue, setValue)
        }
        break

      case 'Escape':
        e.preventDefault()
        close(inputRef, currentValue, setValue)
        break

      case 'Tab':
        e.preventDefault()
        if (filteredPlaceholders.length > 0) {
          selectPlaceholder(filteredPlaceholders[highlightedIndex], inputRef, currentValue, setValue)
        }
        break
    }
  }, [isOpen, filteredPlaceholders, highlightedIndex, selectPlaceholder, close])

  const handleChange = useCallback((
    inputRef: React.RefObject<HTMLInputElement | HTMLTextAreaElement | null>,
    newValue: string,
    cursorPosition: number
  ) => {
    if (!isOpen) {
      const charBeforeCursor = newValue[cursorPosition - 1]
      if (charBeforeCursor === '/') {
        setIsOpen(true)
        setSearchQuery('')
        setHighlightedIndex(0)
        slashPositionRef.current = cursorPosition - 1
        setTriggerPosition(cursorPosition - 1)
        scheduleCaretUpdate(inputRef)
        return
      }
    } else {
      if (slashPositionRef.current >= 0) {
        const textAfterSlash = newValue.slice(slashPositionRef.current + 1, cursorPosition)
        
        if (textAfterSlash.includes(' ') || cursorPosition <= slashPositionRef.current) {
          resetState()
          return
        }
        
        setSearchQuery(textAfterSlash)
        setHighlightedIndex(0)
        scheduleCaretUpdate(inputRef)
      }
    }
  }, [isOpen, resetState, scheduleCaretUpdate])

  const handleScroll = useCallback((
    inputRef: React.RefObject<HTMLInputElement | HTMLTextAreaElement | null>
  ) => {
    if (!isOpen) return
    scheduleCaretUpdate(inputRef)
  }, [isOpen, scheduleCaretUpdate])

  return {
    isOpen,
    searchQuery,
    filteredPlaceholders,
    highlightedIndex,
    caretPosition,
    triggerPosition,
    handleKeyDown,
    handleChange,
    handleScroll,
    selectPlaceholder,
    close
  }
}
