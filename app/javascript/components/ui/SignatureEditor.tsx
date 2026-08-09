/**
 * SignatureEditor Component
 * Dual-mode editor for email signatures with Rich Text (WYSIWYG) and HTML modes.
 */
import { useState, useEffect, useCallback, useRef } from 'react'
import { useEditor, EditorContent } from '@tiptap/react'
import StarterKit from '@tiptap/starter-kit'
import Link from '@tiptap/extension-link'
import Image from '@tiptap/extension-image'
import { Table } from '@tiptap/extension-table'
import TableRow from '@tiptap/extension-table-row'
import TableCell from '@tiptap/extension-table-cell'
import TableHeader from '@tiptap/extension-table-header'
import { TextStyle } from '@tiptap/extension-text-style'
import { Color } from '@tiptap/extension-color'
import { AlertTriangle, Info } from 'lucide-react'
import { t } from '../../lib/i18n'

type EditorMode = 'richtext' | 'html'

interface SignatureEditorProps {
  value: string
  onChange: (value: string) => void
  placeholder?: string
}

function validateHtml(html: string): string[] {
  const warnings: string[] = []
  
  if (!html.trim()) {
    return warnings
  }

  const openTags: string[] = []
  const tagRegex = /<\/?([a-zA-Z][a-zA-Z0-9]*)\b[^>]*\/?>/g
  const selfClosingTags = ['br', 'hr', 'img', 'input', 'meta', 'link', 'area', 'base', 'col', 'embed', 'param', 'source', 'track', 'wbr']
  
  let match
  while ((match = tagRegex.exec(html)) !== null) {
    const fullTag = match[0]
    const tagName = match[1].toLowerCase()
    
    if (selfClosingTags.includes(tagName) || fullTag.endsWith('/>')) {
      continue
    }
    
    if (fullTag.startsWith('</')) {
      const lastOpen = openTags.pop()
      if (lastOpen !== tagName) {
        warnings.push(t('admin.senders.signature_editor.warning_unclosed_tag', { tag: lastOpen || tagName }))
      }
    } else {
      openTags.push(tagName)
    }
  }
  
  if (openTags.length > 0) {
    warnings.push(t('admin.senders.signature_editor.warning_unclosed_tags', { tags: openTags.join(', ') }))
  }

  if (/<script\b/i.test(html)) {
    warnings.push(t('admin.senders.signature_editor.warning_script_tags'))
  }

  return warnings
}

function hasComplexHtml(html: string): boolean {
  if (!html) return false
  const hasTable = /<table\b/i.test(html)
  const hasStyledDiv = /<div\s+[^>]*style\s*=/i.test(html)
  const hasStyledSpan = /<span\s+[^>]*style\s*=/i.test(html)
  const hasTbody = /<tbody\b/i.test(html)
  return hasTable || hasStyledDiv || hasStyledSpan || hasTbody
}

const CustomTableCell = TableCell.extend({
  addAttributes() {
    return {
      ...this.parent?.(),
      style: {
        default: null,
        parseHTML: (element: HTMLElement) => element.getAttribute('style'),
        renderHTML: (attributes: Record<string, string | null>) => {
          if (!attributes.style) return {}
          return { style: attributes.style }
        },
      },
      width: {
        default: null,
        parseHTML: (element: HTMLElement) => element.getAttribute('width'),
        renderHTML: (attributes: Record<string, string | null>) => {
          if (!attributes.width) return {}
          return { width: attributes.width }
        },
      },
      height: {
        default: null,
        parseHTML: (element: HTMLElement) => element.getAttribute('height'),
        renderHTML: (attributes: Record<string, string | null>) => {
          if (!attributes.height) return {}
          return { height: attributes.height }
        },
      },
      valign: {
        default: null,
        parseHTML: (element: HTMLElement) => element.getAttribute('valign'),
        renderHTML: (attributes: Record<string, string | null>) => {
          if (!attributes.valign) return {}
          return { valign: attributes.valign }
        },
      },
      align: {
        default: null,
        parseHTML: (element: HTMLElement) => element.getAttribute('align'),
        renderHTML: (attributes: Record<string, string | null>) => {
          if (!attributes.align) return {}
          return { align: attributes.align }
        },
      },
    }
  },
})

const CustomTableHeader = TableHeader.extend({
  addAttributes() {
    return {
      ...this.parent?.(),
      style: {
        default: null,
        parseHTML: (element: HTMLElement) => element.getAttribute('style'),
        renderHTML: (attributes: Record<string, string | null>) => {
          if (!attributes.style) return {}
          return { style: attributes.style }
        },
      },
    }
  },
})

const CustomTable = Table.extend({
  addAttributes() {
    return {
      ...this.parent?.(),
      style: {
        default: null,
        parseHTML: (element: HTMLElement) => element.getAttribute('style'),
        renderHTML: (attributes: Record<string, string | null>) => {
          if (!attributes.style) return {}
          return { style: attributes.style }
        },
      },
      border: {
        default: null,
        parseHTML: (element: HTMLElement) => element.getAttribute('border'),
        renderHTML: (attributes: Record<string, string | null>) => {
          if (!attributes.border) return {}
          return { border: attributes.border }
        },
      },
      cellpadding: {
        default: null,
        parseHTML: (element: HTMLElement) => element.getAttribute('cellpadding'),
        renderHTML: (attributes: Record<string, string | null>) => {
          if (!attributes.cellpadding) return {}
          return { cellpadding: attributes.cellpadding }
        },
      },
      cellspacing: {
        default: null,
        parseHTML: (element: HTMLElement) => element.getAttribute('cellspacing'),
        renderHTML: (attributes: Record<string, string | null>) => {
          if (!attributes.cellspacing) return {}
          return { cellspacing: attributes.cellspacing }
        },
      },
      width: {
        default: null,
        parseHTML: (element: HTMLElement) => element.getAttribute('width'),
        renderHTML: (attributes: Record<string, string | null>) => {
          if (!attributes.width) return {}
          return { width: attributes.width }
        },
      },
    }
  },
})

const CustomLink = Link.extend({
  addAttributes() {
    return {
      ...this.parent?.(),
      style: {
        default: null,
        parseHTML: (element: HTMLElement) => element.getAttribute('style'),
        renderHTML: (attributes: Record<string, string | null>) => {
          if (!attributes.style) return {}
          return { style: attributes.style }
        },
      },
    }
  },
})

export function SignatureEditor({ value, onChange, placeholder }: SignatureEditorProps) {
  const [mode, setMode] = useState<EditorMode>('richtext')
  const [htmlValue, setHtmlValue] = useState(value)
  const [htmlWarnings, setHtmlWarnings] = useState<string[]>([])
  const isUpdatingFromEditor = useRef(false)
  const isUpdatingFromTextarea = useRef(false)
  
  const isComplexHtml = hasComplexHtml(htmlValue)

  const editor = useEditor({
    extensions: [
      StarterKit.configure({
        codeBlock: false,
      }),
      CustomLink.configure({
        openOnClick: false,
        autolink: true,
        linkOnPaste: true,
      }),
      Image.configure({
        inline: true,
        allowBase64: true,
      }),
      CustomTable.configure({
        resizable: false,
        HTMLAttributes: {
          class: 'signature-table',
        },
      }),
      TableRow,
      CustomTableCell,
      CustomTableHeader,
      TextStyle,
      Color,
    ],
    content: isComplexHtml ? '' : value,
    editorProps: {
      attributes: {
        class: 'prose prose-sm max-w-none focus:outline-none min-h-[120px] px-3 py-2.5',
      },
    },
    onUpdate: ({ editor }) => {
      if (isUpdatingFromTextarea.current || isComplexHtml) return
      
      isUpdatingFromEditor.current = true
      const html = editor.getHTML()
      setHtmlValue(html)
      onChange(html)
      isUpdatingFromEditor.current = false
    },
  })

  useEffect(() => {
    if (editor && !isComplexHtml && value !== editor.getHTML() && !isUpdatingFromEditor.current) {
      editor.commands.setContent(value)
      setHtmlValue(value)
    } else if (isComplexHtml) {
      setHtmlValue(value)
    }
  }, [value, editor, isComplexHtml])

  useEffect(() => {
    if (mode === 'html') {
      const warnings = validateHtml(htmlValue)
      setHtmlWarnings(warnings)
    } else {
      setHtmlWarnings([])
    }
  }, [htmlValue, mode])

  const handleHtmlChange = useCallback((newHtml: string) => {
    setHtmlValue(newHtml)
    onChange(newHtml)
    
    const newIsComplex = hasComplexHtml(newHtml)
    if (editor && !isUpdatingFromEditor.current && !newIsComplex) {
      isUpdatingFromTextarea.current = true
      editor.commands.setContent(newHtml)
      isUpdatingFromTextarea.current = false
    }
  }, [editor, onChange])

  const handleModeChange = useCallback((newMode: EditorMode) => {
    setMode(newMode)
    
    if (newMode === 'html' && editor && !isComplexHtml) {
      const currentHtml = editor.getHTML()
      setHtmlValue(currentHtml)
    } else if (newMode === 'richtext' && editor && !isComplexHtml) {
      editor.commands.setContent(htmlValue)
    }
  }, [editor, htmlValue, isComplexHtml])

  return (
    <div className="space-y-3">
      <div className="flex items-center gap-4">
        <label className="flex items-center gap-2 cursor-pointer">
          <input
            type="radio"
            name="signature_mode"
            value="richtext"
            checked={mode === 'richtext'}
            onChange={() => handleModeChange('richtext')}
            className="w-4 h-4 text-[var(--primary)] bg-[var(--input)] border-[var(--input-border)] focus:ring-[var(--ring)] focus:ring-2"
          />
          <span className="text-sm font-medium text-[var(--foreground)]">
            {isComplexHtml ? t('admin.senders.signature_editor.mode_preview') : t('admin.senders.signature_editor.mode_richtext')}
          </span>
        </label>
        <label className="flex items-center gap-2 cursor-pointer">
          <input
            type="radio"
            name="signature_mode"
            value="html"
            checked={mode === 'html'}
            onChange={() => handleModeChange('html')}
            className="w-4 h-4 text-[var(--primary)] bg-[var(--input)] border-[var(--input-border)] focus:ring-[var(--ring)] focus:ring-2"
          />
          <span className="text-sm font-medium text-[var(--foreground)]">
            {t('admin.senders.signature_editor.mode_html')}
          </span>
        </label>
      </div>

      {mode === 'richtext' ? (
        isComplexHtml ? (
          <div className="space-y-2">
            <div 
              className="min-h-[120px] px-3 py-2.5 bg-white text-gray-900 border border-[var(--input-border)] rounded-lg text-sm [&_p]:mb-2 [&_p:last-child]:mb-0 [&_p:empty]:min-h-[1.5rem] [&_div:empty]:min-h-[1.5rem]"
              dangerouslySetInnerHTML={{ __html: htmlValue }}
            />
            <div className="flex items-start gap-2 p-3 bg-blue-500/10 border border-blue-500/30 rounded-lg">
              <Info className="h-4 w-4 text-blue-500 flex-shrink-0 mt-0.5" />
              <p className="text-sm text-blue-600 dark:text-blue-400">
                {t('admin.senders.signature_editor.complex_html_notice')}
              </p>
            </div>
          </div>
        ) : (
          <div className="bg-[var(--input)] border border-[var(--input-border)] rounded-lg overflow-hidden focus-within:ring-2 focus-within:ring-[var(--ring)] focus-within:border-transparent transition-all">
            <EditorContent 
              editor={editor} 
              className="[&_.ProseMirror]:min-h-[120px] [&_.ProseMirror]:px-3 [&_.ProseMirror]:py-2.5 [&_.ProseMirror]:text-sm [&_.ProseMirror]:text-[var(--foreground)] [&_.ProseMirror_p]:my-1 [&_.ProseMirror_a]:text-[var(--primary)] [&_.ProseMirror_a]:underline [&_.ProseMirror_img]:max-w-full [&_.ProseMirror_img]:h-auto [&_.ProseMirror:focus]:outline-none [&_.ProseMirror_strong]:text-inherit [&_.ProseMirror_b]:text-inherit [&_.ProseMirror_p.is-editor-empty:first-child::before]:content-[attr(data-placeholder)] [&_.ProseMirror_p.is-editor-empty:first-child::before]:text-[var(--foreground-muted)] [&_.ProseMirror_p.is-editor-empty:first-child::before]:float-left [&_.ProseMirror_p.is-editor-empty:first-child::before]:h-0 [&_.ProseMirror_p.is-editor-empty:first-child::before]:pointer-events-none [&_.ProseMirror_table]:border-collapse [&_.ProseMirror_table]:w-full [&_.ProseMirror_td]:border [&_.ProseMirror_td]:border-[var(--border)] [&_.ProseMirror_td]:p-2 [&_.ProseMirror_th]:border [&_.ProseMirror_th]:border-[var(--border)] [&_.ProseMirror_th]:p-2 [&_.ProseMirror_th]:bg-[var(--card-hover)]"
            />
          </div>
        )
      ) : (
        <div className="space-y-2">
          <textarea
            value={htmlValue}
            onChange={(e) => handleHtmlChange(e.target.value)}
            placeholder={placeholder}
            rows={6}
            className="block w-full px-3 py-2.5 bg-[var(--input)] border border-[var(--input-border)] rounded-lg text-[var(--foreground)] text-sm font-mono focus:outline-none focus:ring-2 focus:ring-[var(--ring)] focus:border-transparent transition-all"
          />
          
          {htmlWarnings.length > 0 && (
            <div className="p-3 bg-yellow-500/10 border border-yellow-500/30 rounded-lg">
              <div className="flex items-start gap-2">
                <AlertTriangle className="h-4 w-4 text-yellow-500 flex-shrink-0 mt-0.5" />
                <div className="space-y-1">
                  <p className="text-sm font-medium text-yellow-600 dark:text-yellow-400">
                    {t('admin.senders.signature_editor.html_warnings_title')}
                  </p>
                  <ul className="text-sm text-yellow-600/80 dark:text-yellow-400/80 list-disc list-inside">
                    {htmlWarnings.map((warning, index) => (
                      <li key={index}>{warning}</li>
                    ))}
                  </ul>
                </div>
              </div>
            </div>
          )}
        </div>
      )}

      <p className="text-sm text-[var(--foreground-muted)]">
        {mode === 'richtext' 
          ? (isComplexHtml ? t('admin.senders.signature_editor.help_preview') : t('admin.senders.signature_editor.help_richtext'))
          : t('admin.senders.signature_editor.help_html')
        }
      </p>
    </div>
  )
}

export default SignatureEditor
