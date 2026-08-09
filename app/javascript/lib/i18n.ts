/**
 * Frontend i18n helper using i18n-js
 *
 * WHY: Provides translation support for React components using Rails i18n translations
 * exported to JSON. This ensures consistent translations between backend and frontend.
 *
 * WHY i18n-js: Integrates seamlessly with Rails i18n, supports same key structure,
 * includes pluralization and interpolation features.
 *
 * WHY locale from HTML lang: The Rails layout sets document.documentElement.lang based
 * on the current user's locale, so we use that as the source of truth.
 *
 * WHY single initialization: This module is imported once in the app entry point to
 * initialize i18n globally. Components can then import the `t` function directly.
 */

import { I18n } from 'i18n-js';
type TranslationDictionary = Record<string, unknown>

export const SUPPORTED_LOCALES = ['en', 'de', 'es', 'pt-BR', 'fr', 'pl', 'cs', 'it'] as const
const DEFAULT_LOCALE = 'en'

type SupportedLocale = (typeof SUPPORTED_LOCALES)[number]
type LocaleModule = {
  default: Record<string, TranslationDictionary>
}

const localeLoaders = import.meta.glob<LocaleModule>('../locales/*.json')
const loadedLocales = new Set<SupportedLocale>()
const pendingLocaleLoads = new Map<SupportedLocale, Promise<void>>()

// WHY: Create and configure I18n instance once when module loads
const i18n = new I18n({});

export const normalizeLocale = (locale: string | null | undefined): SupportedLocale => {
  if (!locale) return DEFAULT_LOCALE

  const normalizedLocale = locale.trim().toLowerCase()
  const matchedLocale = SUPPORTED_LOCALES.find((supportedLocale) => supportedLocale.toLowerCase() === normalizedLocale)

  return matchedLocale || DEFAULT_LOCALE
}

const loadLocale = async (locale: string | null | undefined): Promise<SupportedLocale> => {
  const normalizedLocale = normalizeLocale(locale)

  if (loadedLocales.has(normalizedLocale)) {
    return normalizedLocale
  }

  const existingLoad = pendingLocaleLoads.get(normalizedLocale)
  if (existingLoad) {
    await existingLoad
    return normalizedLocale
  }

  const localeLoad = (async () => {
    const modulePath = `../locales/${normalizedLocale}.json`
    const moduleLoader = localeLoaders[modulePath]

    if (!moduleLoader) {
      if (normalizedLocale !== DEFAULT_LOCALE) {
        await loadLocale(DEFAULT_LOCALE)
        return
      }

      throw new Error(`Missing locale bundle: ${modulePath}`)
    }

    const loadedModule = await moduleLoader()
    const translations = loadedModule.default?.[normalizedLocale] || {}

    i18n.store({ [normalizedLocale]: translations })
    loadedLocales.add(normalizedLocale)
  })()

  pendingLocaleLoads.set(normalizedLocale, localeLoad)

  try {
    await localeLoad
  } finally {
    pendingLocaleLoads.delete(normalizedLocale)
  }

  return normalizedLocale
}

export const initializeI18n = async (): Promise<void> => {
  const currentLocale = normalizeLocale(document.documentElement.lang)

  await loadLocale(DEFAULT_LOCALE)

  if (currentLocale !== DEFAULT_LOCALE) {
    await loadLocale(currentLocale)
  }

  i18n.locale = currentLocale
}

export const setLocale = async (locale: string): Promise<void> => {
  const nextLocale = await loadLocale(locale)

  if (nextLocale !== DEFAULT_LOCALE) {
    await loadLocale(DEFAULT_LOCALE)
  }

  i18n.locale = nextLocale
}

i18n.locale = normalizeLocale(document.documentElement.lang);

// WHY: Set default locale for fallback when translation key is missing
i18n.defaultLocale = 'en';

// WHY: Enable fallback to default locale when translation is missing in current locale
i18n.enableFallback = true;

// WHY: Export the translate function directly for convenient use in components
export const t = i18n.t.bind(i18n);

// WHY: Export locale for components that need to know current language
export const locale = i18n.locale;

// WHY: Export full i18n instance for advanced use cases
export default i18n;

/**
 * Usage in components:
 *
 * import { t } from '@/lib/i18n';
 *
 * function MyComponent() {
 *   return (
 *     <h1>{t('navigation.dashboard')}</h1>
 *     <p>{t('welcome.message', { name: 'User' })}</p>
 *   );
 * }
 */
