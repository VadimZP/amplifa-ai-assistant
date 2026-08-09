import { useState, useRef, useEffect } from 'react'
import { normalizeLocale, t } from '../lib/i18n'
import { Globe, Check, Loader2 } from 'lucide-react'

// WHY: i18n is used to support multiple languages (EN/DE) for international users.
// All user-facing text is translated via i18n.t() calls to provide a localized experience.
//
// WHY: This component allows users to switch between English and German languages.
// It's a critical part of the onboarding flow - users need to complete the
// "Select Language" step to finish onboarding. Without this component, users
// are stuck and cannot complete onboarding.

interface LanguageSelectorProps {
  currentLocale?: string
  variant?: 'default' | 'sidebar' // sidebar variant for profile popup with right-aligned dropdown
}

export default function LanguageSelector({ currentLocale, variant = 'default' }: LanguageSelectorProps) {
  const [isOpen, setIsOpen] = useState(false)
  const [isLoading, setIsLoading] = useState(false)
  const [buttonRect, setButtonRect] = useState<DOMRect | null>(null)
  const buttonRef = useRef<HTMLButtonElement>(null)

  // WHY: Map locale codes to human-readable labels with flag emojis for visual recognition
  const languages: Record<string, { code: string; label: string; flag: string }> = {
    en: { code: 'EN', label: t('languages.en'), flag: '🇬🇧' },
    de: { code: 'DE', label: t('languages.de'), flag: '🇩🇪' },
    es: { code: 'ES', label: t('languages.es'), flag: '🇪🇸' },
    'pt-BR': { code: 'PT', label: t('languages.pt-BR'), flag: '🇧🇷' },
    fr: { code: 'FR', label: t('languages.fr'), flag: '🇫🇷' },
    pl: { code: 'PL', label: t('languages.pl'), flag: '🇵🇱' },
    cs: { code: 'CS', label: t('languages.cs'), flag: '🇨🇿' },
    it: { code: 'IT', label: t('languages.it'), flag: '🇮🇹' }
  }

  const activeLocale = normalizeLocale(currentLocale || document.documentElement.lang)
  const currentLanguage = languages[activeLocale]

  // WHY: Update button rect when opening for positioning
  useEffect(() => {
    if (isOpen && buttonRef.current) {
      setButtonRect(buttonRef.current.getBoundingClientRect())
    }
  }, [isOpen])

  // WHY: Handle language selection by posting to /locale endpoint, then reload the page
  // to apply the new locale throughout the entire app (including server-rendered content)
  const handleLanguageChange = async (locale: string) => {
    if (locale === activeLocale) {
      // WHY: Don't do anything if user selects the current language
      setIsOpen(false)
      return
    }

    setIsLoading(true)
    setIsOpen(false)

    try {
      // WHY: Use fetch instead of Inertia.post because we want to handle the JSON response
      // and then manually reload the page to apply the new locale
      const response = await fetch('/locale', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || ''
        },
        body: JSON.stringify({ locale })
      })

      if (response.ok) {
        // WHY: Reload the page to apply the new locale throughout the entire app.
        // This ensures all server-rendered content, navigation, and UI elements
        // are translated to the new language.
        window.location.reload()
      } else {
        console.error('Failed to update locale')
        setIsLoading(false)
      }
    } catch (error) {
      console.error('Error updating locale:', error)
      setIsLoading(false)
    }
  }

  // WHY: Close dropdown when clicking outside
  const handleClickOutside = () => {
    if (isOpen) {
      setIsOpen(false)
    }
  }

  // Sidebar variant: styled to match logout item, dropdown appears to the right
  if (variant === 'sidebar') {
    return (
      <div className="relative">
        <button
          ref={buttonRef}
          type="button"
          onClick={() => setIsOpen(!isOpen)}
          disabled={isLoading}
          className="w-full flex items-center gap-3 px-2 py-2 text-sm text-gray-400 hover:text-white hover:bg-white/5 rounded-lg transition-colors duration-150 disabled:opacity-50 disabled:cursor-not-allowed"
          aria-label={t('navigation.select_language')}
          aria-expanded={isOpen}
          aria-haspopup="true"
        >
          <Globe className="size-4" aria-hidden="true" />
          <span>{currentLanguage.code}</span>
          {isLoading && (
            <Loader2 className="animate-spin size-4 ml-auto" />
          )}
        </button>

        {/* Dropdown - fixed positioned to the RIGHT of the button, bottom-aligned */}
        {isOpen && buttonRect && (
          <>
            {/* Invisible overlay to capture clicks outside the dropdown */}
            <div
              className="fixed inset-0 z-[200]"
              onClick={handleClickOutside}
              aria-hidden="true"
            />

            {/* Dropdown positioned to the right of the button, bottom-aligned */}
            <div
              className="fixed z-[201] w-48 rounded-lg shadow-lg bg-[#171717] border border-white/10"
              style={{
                left: buttonRect.right + 8,
                bottom: window.innerHeight - buttonRect.bottom
              }}
              role="menu"
              aria-orientation="vertical"
            >
              <div className="py-1">
                {Object.entries(languages).map(([locale, lang]) => {
                  const isCurrentLocale = locale === activeLocale

                  return (
                    <button
                      key={locale}
                      type="button"
                      onClick={() => handleLanguageChange(locale)}
                      className={`w-full text-left px-4 py-2 text-sm flex items-center justify-between hover:bg-white/5 transition-colors ${
                        isCurrentLocale ? 'bg-white/5' : ''
                      }`}
                      role="menuitem"
                    >
                      <span className="flex items-center gap-3">
                        <span className="text-lg">{lang.flag}</span>
                        <span className={isCurrentLocale ? 'font-medium text-white' : 'text-gray-400'}>
                          {lang.label}
                        </span>
                      </span>
                      {isCurrentLocale && (
                        <Check className="size-4 text-[var(--accent)]" aria-hidden="true" />
                      )}
                    </button>
                  )
                })}
              </div>
            </div>
          </>
        )}
      </div>
    )
  }

  // Default variant
  return (
    <div className="relative">
      {/* WHY: Trigger button shows globe icon + current language code */}
      <button
        type="button"
        onClick={() => setIsOpen(!isOpen)}
        disabled={isLoading}
        className="inline-flex items-center space-x-2 px-3 py-2 text-sm text-[var(--foreground-muted)] hover:text-[var(--foreground)] hover:bg-[var(--secondary)] rounded-lg transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
        aria-label={t('navigation.select_language')}
        aria-expanded={isOpen}
        aria-haspopup="true"
      >
        <Globe className="h-5 w-5" aria-hidden="true" />
        <span className="font-medium">{currentLanguage.code}</span>
        {/* WHY: Show loading spinner when switching languages */}
        {isLoading && (
          <Loader2 className="animate-spin h-4 w-4" />
        )}
      </button>

      {/* WHY: Dropdown menu with language options */}
      {isOpen && (
        <>
          {/* WHY: Invisible overlay to capture clicks outside the dropdown */}
          <div
            className="fixed inset-0 z-10"
            onClick={handleClickOutside}
            aria-hidden="true"
          />

          {/* WHY: Dropdown positioned below the trigger button */}
          <div
            className="absolute right-0 z-20 mt-2 w-48 rounded-lg shadow-lg bg-[var(--card)] border border-[var(--border)]"
            role="menu"
            aria-orientation="vertical"
          >
            <div className="py-1">
              {/* WHY: Map through available languages and render as clickable options */}
              {Object.entries(languages).map(([locale, lang]) => {
                 const isCurrentLocale = locale === activeLocale

                return (
                  <button
                    key={locale}
                    type="button"
                    onClick={() => handleLanguageChange(locale)}
                    className={`w-full text-left px-4 py-2 text-sm flex items-center justify-between hover:bg-[var(--secondary)] transition-colors ${
                      isCurrentLocale ? 'bg-[var(--secondary)]/50' : ''
                    }`}
                    role="menuitem"
                  >
                    <span className="flex items-center space-x-3">
                      {/* WHY: Show flag emoji for visual recognition */}
                      <span className="text-xl">{lang.flag}</span>
                      <span className={isCurrentLocale ? 'font-medium text-[var(--foreground)]' : 'text-[var(--foreground-muted)]'}>
                        {lang.label}
                      </span>
                    </span>
                    {/* WHY: Show checkmark for currently selected language */}
                    {isCurrentLocale && (
                      <Check className="h-5 w-5 text-[var(--accent)]" aria-hidden="true" />
                    )}
                  </button>
                )
              })}
            </div>
          </div>
        </>
      )}
    </div>
  )
}
