import { Info } from 'lucide-react'
import { getPlaceholderGroupsForPromptCategory } from '../lib/placeholders'

interface PromptPlaceholderHelpProps {
  category?: string | null
  slug?: string | null
}

export function PromptPlaceholderHelp({ category, slug }: PromptPlaceholderHelpProps) {
  const groups = getPlaceholderGroupsForPromptCategory(category, slug)
  const emptyMessage = category
    ? 'No insertable placeholders are defined for this prompt.'
    : 'Select a category to see available placeholders.'

  return (
    <div className="relative group">
      <Info className="h-4 w-4 text-[var(--foreground-muted)] cursor-help hover:text-[var(--foreground)] transition-colors" />
      <div className="absolute left-0 top-full mt-1 z-50 w-[26rem] max-w-[calc(100vw-2rem)] rounded-lg border border-[var(--border)] bg-[var(--card)] p-3 text-xs shadow-lg opacity-0 invisible transition-all group-hover:opacity-100 group-hover:visible">
        <p className="mb-2 font-medium text-[var(--foreground)]">Common Placeholders</p>
        {groups.length > 0 ? (
          <div className="space-y-2 text-[var(--foreground-muted)]">
            {groups.map((group) => (
              <div key={group.label}>
                <span className="font-medium text-[var(--foreground)]">{group.label}:</span>
                <div className="mt-1 flex flex-wrap gap-1.5">
                  {group.placeholders.map((placeholder) => (
                    <code key={placeholder.value} className="text-[10px]">
                      {placeholder.value}
                    </code>
                  ))}
                </div>
              </div>
            ))}
          </div>
        ) : (
          <p className="text-[var(--foreground-muted)]">{emptyMessage}</p>
        )}
      </div>
    </div>
  )
}
