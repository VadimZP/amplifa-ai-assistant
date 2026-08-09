/**
 * Normalizes whitespace in scraped content for better display.
 * - Collapses 3+ consecutive newlines into 2 (preserves paragraph breaks)
 * - Trims leading/trailing whitespace from each line
 * - Removes lines that are only whitespace
 * - Preserves meaningful line breaks (single \n between paragraphs)
 */
export const formatScrapedContent = (content: string): string => {
  if (!content) return ''
  
  return content
    .split(/\r?\n/)
    .map(line => line.trim())
    .join('\n')
    .replace(/\n{3,}/g, '\n\n')
    .trim()
}
