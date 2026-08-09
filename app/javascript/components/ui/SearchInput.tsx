import * as React from 'react'
import { Search } from 'lucide-react'

/**
 * SearchInput component with search icon for filtering table data
 * Based on Figma node 257:11648 (Search input above Agent table)
 *
 * Design Specs:
 * - Background: white (#ffffff)
 * - Border: 1px solid #e5e5e5
 * - Border radius: 8px
 * - Height: 36px
 * - Width: 351px (default, can be overridden)
 * - Padding: px-3 py-1 (12px horizontal, 4px vertical)
 * - Gap: 8px between icon and text
 * - Box shadow: 0px 1px 2px rgba(0,0,0,0.05)
 * - Search icon: 16px, color #737373 (neutral-500)
 * - Font: Geist Regular, 14px
 * - Placeholder color: #737373 (muted-foreground)
 */

export interface SearchInputProps
  extends Omit<React.InputHTMLAttributes<HTMLInputElement>, 'type'> {
  /** Placeholder text */
  placeholder?: string
  /** Current search value */
  value?: string
  /** Change handler */
  onChange?: (e: React.ChangeEvent<HTMLInputElement>) => void
  /** Custom className for the container */
  className?: string
  /** Custom className for the input element */
  inputClassName?: string
}

export const SearchInput = React.forwardRef<HTMLInputElement, SearchInputProps>(
  (
    {
      placeholder = 'Search leads by name or company',
      value,
      onChange,
      className = '',
      inputClassName = '',
      ...props
    },
    ref
  ) => {
    return (
      <div
        className={[
          'flex items-center gap-2',
          'h-10 w-[351px] max-w-full',
          'px-3.5 py-1.5',
          'bg-[var(--input)]',
          'border border-[var(--input-border)]',
          'rounded-xl',
          'shadow-[inset_0_1px_0_rgba(255,255,255,0.03)]',
          'focus-within:border-[var(--ring)]',
          'focus-within:ring-4',
          'focus-within:ring-[rgba(53,202,222,0.12)]',
          'transition-all duration-150',
          className,
        ].join(' ')}
      >
        {/* Search Icon */}
        <Search
          className="shrink-0 text-[var(--foreground-subtle)]"
          size={16}
          strokeWidth={2}
          aria-hidden="true"
        />

        {/* Input */}
        <input
          ref={ref}
          type="text"
          value={value}
          onChange={onChange}
          placeholder={placeholder}
          className={[
            // Reset and base styles
            'flex-1 min-w-0',
            'bg-transparent',
            'border-none outline-none',
            // Typography matching Figma
            'text-sm leading-5',
            '!text-[var(--foreground)]',
            '!placeholder:text-[var(--foreground-subtle)]',
            // Remove focus ring (handled by container)
            'focus:outline-none focus:ring-0',
            inputClassName,
          ].join(' ')}
          {...props}
        />
      </div>
    )
  }
)

SearchInput.displayName = 'SearchInput'

export default SearchInput
