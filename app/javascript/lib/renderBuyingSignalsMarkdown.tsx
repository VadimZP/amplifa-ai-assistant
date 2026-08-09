import React from 'react'

type BuyingSignalsBlock =
  | { type: 'paragraph'; lines: string[] }
  | { type: 'ul' | 'ol'; items: string[] }
  | { type: 'table'; headers: string[]; rows: string[][] }

interface RenderMarkdownOptions {
  /** When false, markdown links and bare URLs render as plain text — nothing clickable, nothing fetched. */
  allowLinks?: boolean
}

export function renderBuyingSignalsMarkdown(markdown: string, options: RenderMarkdownOptions = {}) {
  const allowLinks = options.allowLinks ?? true
  const blocks = parseBuyingSignalsBlocks(markdown)

  return (
    <div className="space-y-3 text-sm text-[var(--foreground)]">
      {blocks.map((block, blockIndex) => {
        if (block.type === 'paragraph') {
          return (
            <p key={`paragraph-${blockIndex}`} className="leading-6 whitespace-pre-wrap break-words">
              {renderBuyingSignalsInlineLines(block.lines, `paragraph-${blockIndex}`, allowLinks)}
            </p>
          )
        }

        if (block.type === 'table') {
          return renderBuyingSignalsTable(block, blockIndex, allowLinks)
        }

        const ListTag = block.type

        return (
          <ListTag
            key={`${block.type}-${blockIndex}`}
            className={`space-y-2 pl-5 leading-6 text-[var(--foreground)] ${block.type === 'ul' ? 'list-disc' : 'list-decimal'}`}
          >
            {block.items.map((item, itemIndex) => (
              <li key={`${block.type}-${blockIndex}-item-${itemIndex}`}>
                {renderBuyingSignalsInline(item, `${block.type}-${blockIndex}-item-${itemIndex}`, allowLinks)}
              </li>
            ))}
          </ListTag>
        )
      })}
    </div>
  )
}

function renderBuyingSignalsTable(
  block: Extract<BuyingSignalsBlock, { type: 'table' }>,
  blockIndex: number,
  allowLinks: boolean
) {
  const columnCount = block.headers.length

  return (
    <div
      key={`table-${blockIndex}`}
      className="overflow-x-auto rounded-lg border border-[var(--border)] bg-[var(--card)]"
    >
      <table className="w-full min-w-max text-sm">
        <thead>
          <tr className="border-b border-[var(--border)]">
            {block.headers.map((header, headerIndex) => (
              <th
                key={`table-${blockIndex}-head-${headerIndex}`}
                className="px-3 py-2 text-left font-medium text-[var(--foreground-muted)] whitespace-nowrap"
              >
                {renderBuyingSignalsInline(header, `table-${blockIndex}-head-${headerIndex}`, allowLinks)}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {block.rows.map((row, rowIndex) => (
            <tr
              key={`table-${blockIndex}-row-${rowIndex}`}
              className="border-b border-[var(--border)] last:border-b-0"
            >
              {Array.from({ length: columnCount }, (_, cellIndex) => (
                <td
                  key={`table-${blockIndex}-row-${rowIndex}-cell-${cellIndex}`}
                  className="px-3 py-2 align-middle text-[var(--foreground)] whitespace-nowrap"
                >
                  {renderBuyingSignalsInline(
                    row[cellIndex] ?? '',
                    `table-${blockIndex}-row-${rowIndex}-cell-${cellIndex}`,
                    allowLinks
                  )}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

function renderBuyingSignalsInlineLines(lines: string[], keyPrefix: string, allowLinks: boolean) {
  return lines.flatMap((line, lineIndex) => {
    const nodes: React.ReactNode[] = [
      <React.Fragment key={`${keyPrefix}-line-${lineIndex}`}>
        {renderBuyingSignalsInline(line, `${keyPrefix}-line-${lineIndex}`, allowLinks)}
      </React.Fragment>
    ]

    if (lineIndex < lines.length - 1) {
      nodes.push(<br key={`${keyPrefix}-break-${lineIndex}`} />)
    }

    return nodes
  })
}

function renderBuyingSignalsInline(value: string, keyPrefix: string, allowLinks: boolean, allowBold = true) {
  const nodes: React.ReactNode[] = []
  let lastIndex = 0

  for (const match of value.matchAll(BUYING_SIGNALS_INLINE_PATTERN)) {
    const matchedValue = match[0]
    const matchIndex = match.index ?? 0

    if (matchIndex > lastIndex) {
      nodes.push(value.slice(lastIndex, matchIndex))
    }

    const markdownLinkText = match[1]
    const markdownLinkUrl = match[2]
    const boldText = match[3]
    const plainUrl = match[4]

    if (markdownLinkText && markdownLinkUrl) {
      const normalizedUrl = allowLinks ? normalizeBuyingSignalsLinkUrl(markdownLinkUrl) : null

      if (!allowLinks) {
        // The link's visible text still reads naturally in the sentence; the target is dropped.
        nodes.push(markdownLinkText)
      } else if (normalizedUrl) {
        nodes.push(
          <a
            key={`${keyPrefix}-link-${matchIndex}`}
            href={normalizedUrl}
            target="_blank"
            rel="noopener noreferrer"
            className="break-all underline underline-offset-2 text-[var(--foreground)] hover:text-[var(--foreground)]/80"
          >
            {markdownLinkText}
          </a>
        )
      } else {
        nodes.push(matchedValue)
      }
    } else if (allowBold && boldText) {
      nodes.push(
        <strong key={`${keyPrefix}-strong-${matchIndex}`} className="font-semibold text-[var(--foreground)]">
          {renderBuyingSignalsInline(boldText, `${keyPrefix}-strong-${matchIndex}`, allowLinks, false)}
        </strong>
      )
    } else if (plainUrl) {
      const { url, trailingPunctuation } = splitBuyingSignalsTrailingPunctuation(plainUrl)
      const normalizedUrl = allowLinks ? normalizeBuyingSignalsLinkUrl(url) : null

      if (!allowLinks) {
        nodes.push(matchedValue)
      } else if (normalizedUrl) {
        nodes.push(
          <a
            key={`${keyPrefix}-link-${matchIndex}`}
            href={normalizedUrl}
            target="_blank"
            rel="noopener noreferrer"
            className="break-all underline underline-offset-2 text-[var(--foreground)] hover:text-[var(--foreground)]/80"
          >
            {url}
          </a>
        )

        if (trailingPunctuation) {
          nodes.push(trailingPunctuation)
        }
      } else {
        nodes.push(matchedValue)
      }
    }

    lastIndex = matchIndex + matchedValue.length
  }

  if (lastIndex < value.length) {
    nodes.push(value.slice(lastIndex))
  }

  return nodes.length > 0 ? nodes : value
}

function parseBuyingSignalsBlocks(markdown: string): BuyingSignalsBlock[] {
  const normalizedMarkdown = markdown
    .replace(/\r\n?/g, '\n')
    .replace(/\u2028|\u2029/g, '\n')
    .trim()

  if (!normalizedMarkdown) return []

  const blocks: BuyingSignalsBlock[] = []
  let paragraphLines: string[] = []
  let listItems: string[] = []
  let listType: 'ul' | 'ol' | null = null
  let tableLines: string[] = []

  const flushParagraph = () => {
    if (paragraphLines.length === 0) return
    blocks.push({ type: 'paragraph', lines: paragraphLines })
    paragraphLines = []
  }

  const flushList = () => {
    if (!listType || listItems.length === 0) return
    blocks.push({ type: listType, items: listItems })
    listItems = []
    listType = null
  }

  const flushTable = () => {
    if (tableLines.length === 0) return

    const tableBlock = parseTableBlock(tableLines)
    if (tableBlock) {
      blocks.push(tableBlock)
    } else {
      paragraphLines.push(...tableLines)
    }

    tableLines = []
  }

  for (const line of normalizedMarkdown.split('\n')) {
    const trimmedLine = line.trim()

    if (!trimmedLine) {
      flushParagraph()
      flushList()
      flushTable()
      continue
    }

    if (isTableRow(trimmedLine)) {
      flushParagraph()
      flushList()
      tableLines.push(trimmedLine)
      continue
    }

    flushTable()

    const unorderedMatch = trimmedLine.match(/^[-*+]\s+(.*)$/)
    const orderedMatch = trimmedLine.match(/^\d+[.)]\s+(.*)$/)

    if (unorderedMatch || orderedMatch) {
      flushParagraph()

      const nextListType = unorderedMatch ? 'ul' : 'ol'
      const itemText = (unorderedMatch ?? orderedMatch)?.[1]?.trim() ?? ''

      if (listType && listType !== nextListType) {
        flushList()
      }

      listType = nextListType
      listItems.push(itemText)
      continue
    }

    flushList()
    paragraphLines.push(trimmedLine)
  }

  flushParagraph()
  flushList()
  flushTable()

  return blocks
}

function parseTableBlock(lines: string[]): Extract<BuyingSignalsBlock, { type: 'table' }> | null {
  if (lines.length < 2) return null
  if (!isTableRow(lines[0]) || !isTableSeparator(lines[1])) return null

  const headers = parseTableCells(lines[0])
  if (headers.length === 0) return null

  const rows = lines
    .slice(2)
    .filter(isTableRow)
    .map(parseTableCells)
    .map(row => normalizeTableRow(row, headers.length))

  return { type: 'table', headers, rows }
}

function parseTableCells(line: string): string[] {
  let trimmed = line.trim()

  if (trimmed.startsWith('|')) trimmed = trimmed.slice(1)
  if (trimmed.endsWith('|')) trimmed = trimmed.slice(0, -1)

  return trimmed.split('|').map(cell => cell.trim())
}

function isTableRow(line: string): boolean {
  return line.includes('|') && parseTableCells(line).length >= 2
}

function isTableSeparator(line: string): boolean {
  if (!isTableRow(line)) return false

  return parseTableCells(line).every(cell => /^:?-{3,}:?$/.test(cell))
}

function normalizeTableRow(cells: string[], columnCount: number): string[] {
  if (cells.length === columnCount) return cells
  if (cells.length > columnCount) return cells.slice(0, columnCount)

  return [...cells, ...Array.from({ length: columnCount - cells.length }, () => '')]
}

function splitBuyingSignalsTrailingPunctuation(value: string) {
  let url = value
  let trailingPunctuation = ''

  while (url && /[),.!?:;]$/.test(url)) {
    trailingPunctuation = `${url.slice(-1)}${trailingPunctuation}`
    url = url.slice(0, -1)
  }

  return { url, trailingPunctuation }
}

function normalizeBuyingSignalsLinkUrl(value: string) {
  const trimmedValue = value.trim()
  if (!trimmedValue) return null

  const normalizedValue = BUYING_SIGNALS_HAS_PROTOCOL_PATTERN.test(trimmedValue)
    ? trimmedValue
    : `https://${trimmedValue}`

  try {
    const parsedUrl = new URL(normalizedValue)
    if (!BUYING_SIGNALS_ALLOWED_LINK_PROTOCOLS.has(parsedUrl.protocol)) return null
    return parsedUrl.toString()
  } catch {
    return null
  }
}

const BUYING_SIGNALS_ALLOWED_LINK_PROTOCOLS = new Set(['http:', 'https:', 'mailto:', 'tel:'])
const BUYING_SIGNALS_HAS_PROTOCOL_PATTERN = /^[a-z][a-z\d+\-.]*:/i
const BUYING_SIGNALS_INLINE_PATTERN = /\[([^\]]+)\]\(([^)\s]+)\)|\*\*([^*]+)\*\*|((?:https?:\/\/|www\.)[^\s<]+|(?<![\w@.%+-])(?:[a-z\d](?:[a-z\d-]{0,61}[a-z\d])?\.)+[a-z]{2,}(?:\/[^\s<]*)?(?![\w@]))/gi
