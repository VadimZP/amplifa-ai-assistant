export type CaretPosition = {
  top: number
  left: number
  height: number
}

const styleProperties = [
  'direction',
  'box-sizing',
  'width',
  'height',
  'overflow-x',
  'overflow-y',
  'border-top-width',
  'border-right-width',
  'border-bottom-width',
  'border-left-width',
  'padding-top',
  'padding-right',
  'padding-bottom',
  'padding-left',
  'font-style',
  'font-variant',
  'font-weight',
  'font-stretch',
  'font-size',
  'font-size-adjust',
  'line-height',
  'font-family',
  'text-align',
  'text-transform',
  'text-indent',
  'text-decoration',
  'letter-spacing',
  'word-break',
  'overflow-wrap',
  'word-spacing',
  'tab-size',
  'text-rendering',
  'text-overflow',
  'text-shadow',
  'text-size-adjust'
]

export function getCaretCoordinates(
  element: HTMLInputElement | HTMLTextAreaElement,
  position: number
): CaretPosition {
  const computed = window.getComputedStyle(element)
  const rect = element.getBoundingClientRect()
  const mirror = document.createElement('div')
  const paddingLeft = parseFloat(computed.getPropertyValue('padding-left')) || 0
  const paddingRight = parseFloat(computed.getPropertyValue('padding-right')) || 0
  const paddingTop = parseFloat(computed.getPropertyValue('padding-top')) || 0
  const paddingBottom = parseFloat(computed.getPropertyValue('padding-bottom')) || 0
  const borderLeft = parseFloat(computed.getPropertyValue('border-left-width')) || 0
  const borderTop = parseFloat(computed.getPropertyValue('border-top-width')) || 0
  const contentWidth = Math.max(0, element.clientWidth - paddingLeft - paddingRight)
  const contentHeight = Math.max(0, element.clientHeight - paddingTop - paddingBottom)

  for (const prop of styleProperties) {
    mirror.style.setProperty(prop, computed.getPropertyValue(prop))
  }

  mirror.style.position = 'absolute'
  mirror.style.left = '-9999px'
  mirror.style.top = '0px'
  mirror.style.visibility = 'hidden'
  mirror.style.pointerEvents = 'none'
  mirror.style.zIndex = '-1'
  mirror.style.whiteSpace = element instanceof HTMLInputElement ? 'pre' : 'pre-wrap'
  mirror.style.wordWrap = element instanceof HTMLInputElement ? 'normal' : 'break-word'
  mirror.style.boxSizing = 'content-box'
  mirror.style.padding = '0'
  mirror.style.border = '0'
  mirror.style.margin = '0'
  mirror.style.width = `${contentWidth}px`
  if (!(element instanceof HTMLInputElement)) {
    mirror.style.height = `${contentHeight}px`
  }
  mirror.style.overflow = 'hidden'

  const before = element.value.slice(0, position)
  const after = element.value.slice(position) || '.'
  const marker = after[0] || '.'

  mirror.textContent = before
  const span = document.createElement('span')
  span.textContent = marker
  mirror.appendChild(span)

  document.body.appendChild(mirror)

  const spanRect = span.getBoundingClientRect()
  const mirrorRect = mirror.getBoundingClientRect()
  const offsetTop = spanRect.top - mirrorRect.top
  const offsetLeft = spanRect.left - mirrorRect.left
  const height = spanRect.height

  document.body.removeChild(mirror)

  return {
    top: rect.top + borderTop + paddingTop + offsetTop - element.scrollTop,
    left: rect.left + borderLeft + paddingLeft + offsetLeft - element.scrollLeft,
    height
  }
}
