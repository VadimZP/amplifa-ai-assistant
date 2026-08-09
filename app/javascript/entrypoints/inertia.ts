import { createInertiaApp, router } from '@inertiajs/react'
import { createElement, ReactNode, Fragment } from 'react'
import { createRoot } from 'react-dom/client'
import './application.css'

import { initializeI18n } from '../lib/i18n'

import { Toaster } from '../components/ui/Toaster'

// Temporary type definition, until @inertiajs/react provides one
type ResolvedComponent = {
  default: ReactNode
  layout?: (page: ReactNode) => ReactNode
}

let csrfToken =
  document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.getAttribute('content') || undefined

const updateCsrfToken = (token?: string) => {
  if (!token || token === csrfToken) return

  csrfToken = token
  const metaTag = document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')
  if (metaTag) {
    metaTag.setAttribute('content', token)
  }
}

// Configure Inertia to send CSRF token
router.on('before', (event) => {
  if (csrfToken && event.detail.visit.method !== 'get') {
    event.detail.visit.headers = {
      ...event.detail.visit.headers,
      'X-CSRF-Token': csrfToken,
    }
  }
})

router.on('success', (event) => {
  const props = event.detail.page?.props as Record<string, unknown> | undefined
  const token =
    props && typeof props['csrf_token'] === 'string' ? (props['csrf_token'] as string) : undefined
  updateCsrfToken(token)
})

await initializeI18n()

createInertiaApp({
  // Set default page title
  // see https://inertia-rails.dev/guide/title-and-meta
  //
  // title: title => title ? `${title} - App` : 'App',

  // Disable progress bar
  //
  // see https://inertia-rails.dev/guide/progress-indicators
  // progress: false,

  resolve: async (name) => {
    // Use lazy loading instead of eager: true to enable code-splitting.
    // Each page becomes a separate chunk, loaded on-demand when navigating.
    // This dramatically reduces initial bundle size.
    const pages = import.meta.glob<ResolvedComponent>('../pages/**/*.{tsx,jsx}')
    const pagePath = `../pages/${name}.tsx`
    const pagePathJsx = `../pages/${name}.jsx`
    
    const resolver = pages[pagePath] || pages[pagePathJsx]
    if (!resolver) {
      console.error(`Missing Inertia page component: '${name}.tsx' or '${name}.jsx'`)
      throw new Error(`Missing Inertia page component: ${name}`)
    }
    
    const page = await resolver()

    // To use a default layout, import the Layout component
    // and use the following line.
    // see https://inertia-rails.dev/guide/pages#default-layouts
    //
    // page.default.layout ||= (page) => createElement(Layout, null, page)

    return page
  },

  setup({ el, App, props }) {
    if (el) {
      createRoot(el).render(
        createElement(Fragment, null,
          createElement(App, props),
          createElement(Toaster)
        )
      )
    } else {
      console.error(
        'Missing root element.\n\n' +
          'If you see this error, it probably means you load Inertia.js on non-Inertia pages.\n' +
          'Consider moving <%= vite_typescript_tag "inertia" %> to the Inertia-specific layout instead.',
      )
    }
  },
})
