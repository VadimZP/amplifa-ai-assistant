type Position = {
  top: number
  left: number
}

type Size = {
  width: number
  height: number
}

type Viewport = {
  width: number
  height: number
}

type Options = {
  padding?: number
  flipTop?: number
}

export function clampToViewport(
  position: Position,
  size: Size,
  viewport: Viewport,
  options: Options = {}
): Position {
  const padding = options.padding ?? 8
  let top = position.top
  let left = position.left

  if (top + size.height + padding > viewport.height && options.flipTop !== undefined) {
    top = options.flipTop
  }

  if (left + size.width + padding > viewport.width) {
    left = Math.max(padding, viewport.width - size.width - padding)
  }

  if (top + size.height + padding > viewport.height) {
    top = Math.max(padding, viewport.height - size.height - padding)
  }

  if (top < padding) {
    top = padding
  }

  if (left < padding) {
    left = padding
  }

  return { top, left }
}
