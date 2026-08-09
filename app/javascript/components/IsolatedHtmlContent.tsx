import { useEffect, useRef } from 'react'

interface IsolatedHtmlContentProps {
  html: string
  className?: string
}

const BASE_STYLES = `
  :host {
    display: block;
    color: inherit;
    font: inherit;
    line-height: inherit;
    max-width: 100%;
    word-break: break-word;
  }

  *, *::before, *::after {
    box-sizing: border-box;
    max-width: 100%;
  }

  p {
    margin: 0 0 0.5rem;
  }

  p:last-child {
    margin-bottom: 0;
  }

  img {
    height: auto;
  }

  a {
    color: inherit;
    text-decoration: underline;
  }

  pre,
  code {
    white-space: pre-wrap;
    word-break: break-word;
  }
`

function normalizeHtml(rawHtml: string): string {
  if (typeof window === 'undefined') return rawHtml

  const doc = new DOMParser().parseFromString(rawHtml, 'text/html')
  doc.querySelectorAll('script').forEach((scriptNode) => scriptNode.remove())

  return doc.body?.innerHTML?.trim() || rawHtml
}

export default function IsolatedHtmlContent({ html, className }: IsolatedHtmlContentProps) {
  const hostRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    const host = hostRef.current
    if (!host) return

    const shadowRoot = host.shadowRoot || host.attachShadow({ mode: 'open' })
    shadowRoot.innerHTML = `<style>${BASE_STYLES}</style>${normalizeHtml(html)}`
  }, [html])

  return <div ref={hostRef} className={className} />
}
