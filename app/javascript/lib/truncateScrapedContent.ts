const MAX_VISIBLE_LINES = 20
const MAX_VISIBLE_CHARACTERS = 1000

type TruncationOptions = {
  maxLines?: number
  maxChars?: number
}

type TruncatedScrapedContent = {
  visibleContent: string
  hiddenCharacters: number
  isTruncated: boolean
}

export const truncateScrapedContent = (content: string, options?: TruncationOptions): TruncatedScrapedContent => {
  const maxLines = options?.maxLines ?? MAX_VISIBLE_LINES
  const maxChars = options?.maxChars ?? MAX_VISIBLE_CHARACTERS
  const normalized = content.trim()
  if (!normalized) {
    return {
      visibleContent: '',
      hiddenCharacters: 0,
      isTruncated: false,
    }
  }

  const lines = normalized.split(/\r?\n/)
  const lineCapped = lines.slice(0, maxLines).join('\n')
  const lineAndCharCapped = lineCapped.length > maxChars
    ? lineCapped.slice(0, maxChars).trimEnd()
    : lineCapped

  const hiddenCharacters = Math.max(normalized.length - lineAndCharCapped.length, 0)

  return {
    visibleContent: lineAndCharCapped,
    hiddenCharacters,
    isTruncated: hiddenCharacters > 0,
  }
}
