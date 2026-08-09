import { useEffect, useMemo, useRef, useState } from 'react'
import PlaybookLayout, { getPlaybookGradient } from '../../layouts/PlaybookLayout'
import { Badge } from '../../components/ui/Badge'
import { Button } from '../../components/ui/Button'
import { t } from '../../lib/i18n'
import {
  Archive,
  BookOpenText,
  CalendarDays,
  ChevronDown,
  Clock3,
  Download,
  ExternalLink,
  File,
  FileText,
  FileType2,
  Globe2,
  LibraryBig,
  Link,
  Loader,
  Plus,
  Search,
  Sparkles,
  Upload,
  X,
} from 'lucide-react'
import { useActionCableChannel } from '../../lib/useActionCableChannel'

const translate = (key: string, options?: Record<string, number | string>) => String(t(key, options))

interface ApprovedBy {
  id: number
  first_name: string
  last_name: string
  full_name: string
}

interface Playbook {
  id: number
  organization_id: number
  product: {
    name: string
    description: string
  }
  status: string
  approved_at: string | null
  approved_by: ApprovedBy | null
  'knowledge_base_available?'?: boolean
}

interface KnowledgeBaseFile {
  id: string
  record_id: number
  original_filename: string | null
  display_name: string | null
  file_size_bytes: number | null
  content_type: string | null
  source_type?: 'file' | 'url'
  source_url?: string | null
  source_final_url?: string | null
  source_title?: string | null
  category: string
  summary: string | null
  extracted_text?: string | null
  extraction_status: string
  extraction_error: string | null
  created_at: string
  uploaded_by: {
    id: number
    full_name: string
  } | null
  applies_to_all_playbooks: boolean
  playbooks: Array<{
    id: number
    product_name: string
  }>
}

interface OrganizationFileUpdate {
  file: KnowledgeBaseFile
}

interface Props {
  playbook: Playbook
  files: KnowledgeBaseFile[]
  canApprove?: boolean
  canRequestChanges?: boolean
  canArchive?: boolean
  flash?: {
    notice?: string
    alert?: string
  }
}

const formatFileSize = (bytes: number | null) => {
  if (!bytes || bytes <= 0) return '—'
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
}

const statusVariant = (status: string) => {
  if (status === 'completed') return 'success' as const
  if (status === 'failed') return 'error' as const
  if (['pending', 'extracting', 'summarizing'].includes(status)) return 'info' as const
  return 'default' as const
}

const statusLabel = (status: string) => {
  if (status === 'pending') return translate('playbooks.knowledge_base.statuses.extracting')
  if (status === 'extracting') return translate('playbooks.knowledge_base.statuses.extracting')
  if (status === 'summarizing') return translate('playbooks.knowledge_base.statuses.summarizing')
  if (status === 'completed') return translate('playbooks.knowledge_base.statuses.completed')
  if (status === 'failed') return translate('playbooks.knowledge_base.statuses.failed')
  return translate('playbooks.knowledge_base.statuses.unknown', { status })
}

const statusProgress = (status: string) => {
  if (status === 'pending') return 30
  if (status === 'extracting') return 55
  if (status === 'summarizing') return 82
  if (status === 'completed') return 100
  if (status === 'failed') return 100
  return 10
}

const isProcessing = (status: string) => ['pending', 'extracting', 'summarizing'].includes(status)

const upsertKnowledgeBaseFile = (files: KnowledgeBaseFile[], incomingFile: KnowledgeBaseFile) => {
  const exists = files.some((file) => file.record_id === incomingFile.record_id)
  if (exists) return files.map((file) => (file.record_id === incomingFile.record_id ? incomingFile : file))

  return [incomingFile, ...files]
}

type KnowledgeKind = 'pdf' | 'website' | 'document'
type FilterKind = 'all' | 'pdf' | 'website' | 'document'
type SortMode = 'recent' | 'oldest' | 'name'
type KnowledgeSourceType = 'file' | 'url'

const typeLabelKey: Record<KnowledgeKind, string> = {
  pdf: 'playbooks.knowledge_base.types.pdf',
  website: 'playbooks.knowledge_base.types.website',
  document: 'playbooks.knowledge_base.types.document',
}

const typePluralLabelKey: Record<FilterKind, string> = {
  all: 'playbooks.knowledge_base.filters.all',
  pdf: 'playbooks.knowledge_base.filters.pdfs',
  website: 'playbooks.knowledge_base.filters.websites',
  document: 'playbooks.knowledge_base.filters.docs',
}

const cardVisuals = [
  {
    glow: 'from-violet-500/45 via-fuchsia-500/30 to-transparent',
    icon: 'bg-violet-500 text-white shadow-[0_0_34px_rgba(139,92,246,0.28)]',
    accent: 'text-violet-200',
  },
  {
    glow: 'from-cyan-400/45 via-teal-400/28 to-transparent',
    icon: 'bg-cyan-400 text-slate-950 shadow-[0_0_34px_rgba(34,211,238,0.25)]',
    accent: 'text-cyan-200',
  },
  {
    glow: 'from-orange-500/48 via-amber-500/25 to-transparent',
    icon: 'bg-orange-400 text-slate-950 shadow-[0_0_34px_rgba(251,146,60,0.24)]',
    accent: 'text-orange-200',
  },
  {
    glow: 'from-emerald-500/42 via-green-400/25 to-transparent',
    icon: 'bg-emerald-400 text-slate-950 shadow-[0_0_34px_rgba(52,211,153,0.22)]',
    accent: 'text-emerald-200',
  },
  {
    glow: 'from-indigo-500/45 via-blue-500/25 to-transparent',
    icon: 'bg-indigo-400 text-white shadow-[0_0_34px_rgba(99,102,241,0.24)]',
    accent: 'text-indigo-200',
  },
  {
    glow: 'from-rose-500/45 via-pink-500/24 to-transparent',
    icon: 'bg-rose-400 text-slate-950 shadow-[0_0_34px_rgba(251,113,133,0.22)]',
    accent: 'text-rose-200',
  },
]

interface KnowledgeFileEntry {
  file: KnowledgeBaseFile
  kind: KnowledgeKind
  visual: (typeof cardVisuals)[number]
}

const filterOptions: Array<{ value: FilterKind; icon: typeof Archive }> = [
  { value: 'all', icon: Archive },
  { value: 'pdf', icon: FileType2 },
  { value: 'website', icon: Globe2 },
  { value: 'document', icon: FileText },
]

const typeLabel = (kind: KnowledgeKind) => translate(typeLabelKey[kind])

const typePluralLabel = (kind: FilterKind) => translate(typePluralLabelKey[kind])

const displayName = (file: KnowledgeBaseFile) => file.display_name || file.original_filename || translate('playbooks.knowledge_base.untitled')

const getFileKind = (file: KnowledgeBaseFile): KnowledgeKind => {
  if (file.source_type === 'url') return 'website'

  const name = displayName(file).toLowerCase()
  const contentType = (file.content_type || '').toLowerCase()

  if (contentType.includes('pdf') || name.endsWith('.pdf')) return 'pdf'
  if (contentType.includes('html') || name.startsWith('http://') || name.startsWith('https://') || name.includes('www.')) return 'website'
  return 'document'
}

const getTypeIcon = (kind: KnowledgeKind) => {
  if (kind === 'pdf') return FileType2
  if (kind === 'website') return Globe2
  return FileText
}

const sourceLabel = (file: KnowledgeBaseFile, kind: KnowledgeKind) => {
  const name = displayName(file)

  if (kind === 'website') {
    return file.source_url || file.source_final_url || file.original_filename || name
  }

  return file.original_filename || name
}

const getFooterIcon = (kind: KnowledgeKind) => {
  if (kind === 'website') return Globe2
  return FileText
}

const parseJsonResponse = async <T,>(response: Response): Promise<T> => {
  const body = await response.text()
  if (!body) return {} as T

  try {
    return JSON.parse(body) as T
  } catch {
    throw new Error(response.ok ? translate('playbooks.knowledge_base.errors.invalid_response') : translate('playbooks.knowledge_base.errors.request_failed', { status: response.status }))
  }
}

interface KnowledgeUploadResponse {
  file?: KnowledgeBaseFile
  error?: string
}

interface KnowledgeExtractResponse {
  extracted_text?: string | null
  error?: string
}

const MAX_UPLOAD_FILE_SIZE_BYTES = 25 * 1024 * 1024
const MAX_UPLOAD_FILE_SIZE_LABEL = '25MB'

const relativeDate = (dateString: string) => {
  const date = new Date(dateString)
  const diffMs = Date.now() - date.getTime()
  const diffMinutes = Math.max(1, Math.round(diffMs / 60000))

  if (diffMinutes < 60) return translate('playbooks.knowledge_base.relative_time.minutes_ago', { count: diffMinutes })
  const diffHours = Math.round(diffMinutes / 60)
  if (diffHours < 24) return translate('playbooks.knowledge_base.relative_time.hours_ago', { count: diffHours })
  const diffDays = Math.round(diffHours / 24)
  if (diffDays === 1) return translate('playbooks.knowledge_base.relative_time.yesterday')
  if (diffDays < 30) return translate('playbooks.knowledge_base.relative_time.days_ago', { count: diffDays })

  return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' })
}

const fileExceedsUploadLimit = (file: File) => file.size > MAX_UPLOAD_FILE_SIZE_BYTES

const summaryPreview = (file: KnowledgeBaseFile) => {
  if (file.summary) return file.summary
  if (file.extraction_status === 'failed') return file.extraction_error || translate('playbooks.knowledge_base.summary_failed')
  return translate('playbooks.knowledge_base.summary_pending')
}

const summaryTags = (file: KnowledgeBaseFile) => {
  const ignoredTagWords = new Set(['with', 'from', 'this', 'that', 'your', 'summary', 'document', 'file', 'company', 'amplifa'])
  const words = `${displayName(file)} ${file.summary || ''}`
    .toLowerCase()
    .replace(/[^a-z0-9\s-]/g, ' ')
    .split(/\s+/)
    .filter((word) => word.length > 3 && !ignoredTagWords.has(word))

  return Array.from(new Set(words)).slice(0, 3)
}

export default function KnowledgeBase({ playbook, files, canApprove, canRequestChanges, canArchive, flash }: Props) {
  const [knowledgeBaseFiles, setKnowledgeBaseFiles] = useState(files)
  const [isAddModalOpen, setIsAddModalOpen] = useState(false)
  const [sourceType, setSourceType] = useState<KnowledgeSourceType>('file')
  const [selectedFile, setSelectedFile] = useState<File | null>(null)
  const [url, setUrl] = useState('')
  const [isUploading, setIsUploading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [searchQuery, setSearchQuery] = useState('')
  const [activeFilter, setActiveFilter] = useState<FilterKind>('all')
  const [sortMode, setSortMode] = useState<SortMode>('recent')
  const [selectedFileRecordId, setSelectedFileRecordId] = useState<number | null>(null)
  const fileInputRef = useRef<HTMLInputElement>(null)

  const openAddModal = () => {
    setIsAddModalOpen(true)
    setError(null)
  }

  const closeAddModal = () => {
    if (isUploading) return

    setIsAddModalOpen(false)
    setSelectedFile(null)
    setUrl('')
    setSourceType('file')
    setError(null)
    if (fileInputRef.current) fileInputRef.current.value = ''
  }

  const selectFile = (fileList: FileList | null) => {
    const file = fileList?.[0]
    if (!file) return

    setSelectedFile(file)
    setError(fileExceedsUploadLimit(file) ? `${file.name} exceeds the ${MAX_UPLOAD_FILE_SIZE_LABEL} upload limit.` : null)
  }

  const typedFiles = useMemo<KnowledgeFileEntry[]>(
    () => knowledgeBaseFiles.map((file, index) => ({
      file,
      kind: getFileKind(file),
      visual: cardVisuals[index % cardVisuals.length],
    })),
    [knowledgeBaseFiles],
  )

  const stats = useMemo(() => ({
    total: knowledgeBaseFiles.length,
    website: typedFiles.filter((entry) => entry.kind === 'website').length,
    pdf: typedFiles.filter((entry) => entry.kind === 'pdf').length,
    document: typedFiles.filter((entry) => entry.kind === 'document').length,
  }), [knowledgeBaseFiles.length, typedFiles])
  const gradientImage = `/card-gradient-${getPlaybookGradient(playbook.id)}.jpg?v2`

  const visibleFiles = useMemo(() => {
    const normalizedQuery = searchQuery.trim().toLowerCase()

    return typedFiles
      .filter(({ file, kind }) => {
        const matchesFilter = activeFilter === 'all' || kind === activeFilter
        if (!matchesFilter) return false

        if (!normalizedQuery) return true

        const haystack = [
          displayName(file),
          file.original_filename || '',
          file.source_url || '',
          file.source_final_url || '',
          file.source_title || '',
          file.summary || '',
          file.uploaded_by?.full_name || '',
          typeLabel(kind),
        ].join(' ').toLowerCase()

        return haystack.includes(normalizedQuery)
      })
      .sort((left, right) => {
        if (sortMode === 'name') return displayName(left.file).localeCompare(displayName(right.file))

        const leftTime = new Date(left.file.created_at).getTime()
        const rightTime = new Date(right.file.created_at).getTime()
        return sortMode === 'oldest' ? leftTime - rightTime : rightTime - leftTime
      })
  }, [activeFilter, searchQuery, sortMode, typedFiles])

  const selectedEntry = useMemo(
    () => typedFiles.find((entry) => entry.file.record_id === selectedFileRecordId) || null,
    [selectedFileRecordId, typedFiles]
  )

  useEffect(() => {
    if (!selectedEntry) return

    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') setSelectedFileRecordId(null)
    }

    window.addEventListener('keydown', handleKeyDown)
    return () => window.removeEventListener('keydown', handleKeyDown)
  }, [selectedEntry])

  useActionCableChannel<OrganizationFileUpdate>(
    { channel: 'OrganizationFilesChannel', playbook_id: playbook.id },
    {
      received(data) {
        const incomingFile = data.file
        if (incomingFile.category !== 'knowledge_base') return
        if (!incomingFile.applies_to_all_playbooks && !incomingFile.playbooks.some((assignedPlaybook) => assignedPlaybook.id === playbook.id)) return

        setKnowledgeBaseFiles((current) => upsertKnowledgeBaseFile(current, incomingFile))
      },
    }
  )

  const uploadKnowledge = async () => {
    const fileToUpload = selectedFile
    const urlToUpload = url.trim()
    if (sourceType === 'file' && !fileToUpload) return
    if (fileToUpload && fileExceedsUploadLimit(fileToUpload)) {
      setError(`${fileToUpload.name} exceeds the ${MAX_UPLOAD_FILE_SIZE_LABEL} upload limit.`)
      return
    }
    if (sourceType === 'url' && !urlToUpload) return

    const formData = new FormData()
    formData.append('source_type', sourceType)
    if (sourceType === 'file') {
      if (!fileToUpload) return
      formData.append('file', fileToUpload)
    } else {
      formData.append('url', urlToUpload)
    }

    setIsUploading(true)
    setError(null)

    try {
      const response = await fetch(`/playbooks/${playbook.id}/knowledge_base_files`, {
        method: 'POST',
        body: formData,
        headers: {
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || '',
        },
      })

      const payload = await parseJsonResponse<KnowledgeUploadResponse>(response)
      if (!response.ok) throw new Error(payload.error || translate('playbooks.knowledge_base.errors.upload_failed'))
      if (!payload.file) throw new Error(translate('playbooks.knowledge_base.errors.upload_failed'))
      const uploadedFile = payload.file

      setKnowledgeBaseFiles((current) => upsertKnowledgeBaseFile(current, uploadedFile))
      setIsAddModalOpen(false)
      setSelectedFile(null)
      setUrl('')
      setSourceType('file')
    } catch (uploadError) {
      setError(uploadError instanceof Error ? uploadError.message : translate('playbooks.knowledge_base.errors.upload_failed'))
    } finally {
      setIsUploading(false)
      if (fileInputRef.current) fileInputRef.current.value = ''
    }
  }

  return (
    <PlaybookLayout
      playbook={playbook}
      currentTab="knowledge_base"
      flash={flash}
      canApprove={canApprove}
      canRequestChanges={canRequestChanges}
      canArchive={canArchive}
      fullBleed
    >
      <div className="min-h-full bg-[#111417] text-white">
        <section className="px-5 py-7 sm:px-6 lg:px-8">
          <div className="relative mx-auto max-w-7xl overflow-hidden rounded-[28px] border border-white/[0.08] bg-[#11161c] shadow-[0_28px_80px_rgba(0,0,0,0.32)]">
            <img
              src={gradientImage}
              alt=""
              className="absolute inset-0 h-full w-full object-cover object-center opacity-90"
            />
            <div className="absolute inset-0 bg-[radial-gradient(circle_at_20%_20%,rgba(53,202,222,0.24),transparent_28%),linear-gradient(100deg,rgba(7,10,14,0.94)_0%,rgba(12,16,21,0.74)_48%,rgba(11,9,18,0.86)_100%)]" />
            <div className="absolute right-10 top-8 hidden h-40 w-40 rounded-full bg-[var(--accent)]/10 blur-3xl lg:block" />

            <div className="relative z-10 px-6 py-6 lg:px-8 lg:py-7">
              <div className="flex flex-col gap-6 xl:flex-row xl:items-start xl:justify-between">
                <div className="max-w-4xl">
                  <div className="mb-4 inline-flex items-center gap-2 rounded-full border border-[var(--accent)]/25 bg-[var(--accent)]/10 px-3.5 py-1.5 text-sm font-medium text-[var(--accent)] shadow-[0_0_32px_rgba(53,202,222,0.08)]">
                    <Sparkles className="h-4 w-4" />
                    {t('playbooks.knowledge_base.hero_badge')}
                  </div>
                  <h1 className="max-w-4xl text-4xl font-semibold leading-[0.96] tracking-[-0.055em] text-white md:text-5xl">
                    {t('playbooks.knowledge_base.title_prefix')} <span className="text-[var(--accent)]">{t('playbooks.knowledge_base.title_accent')}</span>
                  </h1>
                  <p className="mt-4 max-w-3xl text-base leading-7 text-white/64 md:text-lg">
                    {t('playbooks.knowledge_base.hero_description')}
                  </p>
                </div>

                <div className="flex flex-wrap gap-3 xl:justify-end">
                  <button
                    type="button"
                    disabled={isUploading}
                    onClick={openAddModal}
                    className="inline-flex items-center justify-center gap-2 rounded-2xl bg-[var(--accent)] px-5 py-3 text-sm font-semibold text-[var(--primary-foreground)] shadow-[0_14px_35px_rgba(53,202,222,0.2)] transition-colors hover:bg-[var(--accent-hover)] focus:outline-none focus:ring-2 focus:ring-[var(--accent)] focus:ring-offset-2 focus:ring-offset-transparent disabled:cursor-not-allowed disabled:opacity-60"
                  >
                    {isUploading ? <Loader className="h-4 w-4 animate-spin" /> : <Plus className="h-4 w-4" />}
                    {t('playbooks.knowledge_base.add_knowledge')}
                  </button>
                </div>
              </div>

              {error && (
                <div className="mt-5 rounded-2xl border border-red-400/25 bg-red-500/10 px-4 py-3 text-sm text-red-100 shadow-[inset_0_1px_0_rgba(255,255,255,0.04)] backdrop-blur-sm">
                  {error}
                </div>
              )}

              <div className="mt-6 grid grid-cols-2 gap-3 md:grid-cols-4 lg:gap-4">
                <StatCard label={t('playbooks.knowledge_base.stats.total_entries')} value={stats.total} icon={LibraryBig} accentClass="text-cyan-300" />
                <StatCard label={t('playbooks.knowledge_base.stats.websites')} value={stats.website} icon={Globe2} accentClass="text-blue-300" />
                <StatCard label={t('playbooks.knowledge_base.stats.pdfs')} value={stats.pdf} icon={FileType2} accentClass="text-fuchsia-300" />
                <StatCard label={t('playbooks.knowledge_base.stats.docs')} value={stats.document} icon={FileText} accentClass="text-rose-300" />
              </div>
            </div>
          </div>
        </section>

        <section className="border-b border-white/[0.08] bg-[#0e1012]/60 px-5 py-4 sm:px-6 lg:px-8">
          <div className="mx-auto flex max-w-7xl flex-col gap-3 md:flex-row md:items-center md:justify-between">
            <label className="flex h-11 min-w-0 flex-1 items-center gap-2.5 rounded-xl border border-white/[0.08] bg-white/[0.045] px-3.5 text-slate-400 shadow-[inset_0_1px_0_rgba(255,255,255,0.04)] transition-all focus-within:border-cyan-300/35 focus-within:ring-4 focus-within:ring-cyan-400/10 md:min-w-[16rem] xl:max-w-3xl">
              <Search className="h-4 w-4 shrink-0" />
              <input
                type="text"
                value={searchQuery}
                onChange={(event) => setSearchQuery(event.target.value)}
                placeholder={t('playbooks.knowledge_base.search_placeholder')}
                className="min-w-0 flex-1 appearance-none border-none !bg-transparent text-sm text-white outline-none placeholder:text-slate-500 focus:!bg-transparent focus:outline-none focus:ring-0"
              />
            </label>

            <div className="flex shrink-0 flex-col gap-3 sm:flex-row sm:items-center">
              <div className="flex overflow-x-auto rounded-xl bg-white/[0.045] p-1 [&::-webkit-scrollbar]:hidden [scrollbar-width:none]">
                {filterOptions.map((option) => {
                  const Icon = option.icon
                  const active = activeFilter === option.value

                  return (
                    <button
                      key={option.value}
                      type="button"
                      onClick={() => setActiveFilter(option.value)}
                      className={`inline-flex h-8 items-center gap-1.5 rounded-lg px-3 text-xs font-medium transition-all whitespace-nowrap ${active ? 'bg-[#090b0d] text-white shadow-[0_8px_24px_rgba(0,0,0,0.25)]' : 'text-slate-400 hover:text-white'}`}
                    >
                      <Icon className="h-3.5 w-3.5" />
                      {typePluralLabel(option.value)}
                    </button>
                  )
                })}
              </div>

              <label className="relative block sm:w-44">
                <select
                  value={sortMode}
                  onChange={(event) => setSortMode(event.target.value as SortMode)}
                  className="h-10 w-full appearance-none rounded-xl border border-white/[0.08] bg-white/[0.045] py-0 pl-3.5 pr-9 text-xs font-semibold text-white outline-none transition-all focus:border-cyan-300/35 focus:ring-4 focus:ring-cyan-400/10"
                >
                  <option value="recent">{t('playbooks.knowledge_base.sort.most_recent')}</option>
                  <option value="oldest">{t('playbooks.knowledge_base.sort.oldest_first')}</option>
                  <option value="name">{t('playbooks.knowledge_base.sort.name_az')}</option>
                </select>
                <ChevronDown className="pointer-events-none absolute right-3 top-1/2 h-3.5 w-3.5 -translate-y-1/2 text-slate-400" />
              </label>
            </div>
          </div>
        </section>

        <section className="px-5 py-7 sm:px-6 lg:px-8">
          <div className="mx-auto max-w-7xl">
            {knowledgeBaseFiles.length === 0 ? (
              <EmptyKnowledgeBase isUploading={isUploading} onUpload={openAddModal} />
            ) : visibleFiles.length === 0 ? (
              <div className="rounded-3xl border border-white/[0.08] bg-white/[0.04] px-6 py-12 text-center">
                <Search className="mx-auto mb-3 h-8 w-8 text-slate-500" />
                <h2 className="text-lg font-semibold text-white">{t('playbooks.knowledge_base.no_matches_title')}</h2>
                <p className="mt-2 text-sm text-slate-400">{t('playbooks.knowledge_base.no_matches_description')}</p>
              </div>
            ) : (
              <div className="grid gap-4 lg:grid-cols-2 2xl:grid-cols-3">
                {visibleFiles.map(({ file, kind, visual }) => {
                  const Icon = getTypeIcon(kind)
                  const FooterIcon = getFooterIcon(kind)
                  const tags = summaryTags(file)

                  return (
                    <article
                      key={file.id}
                      role="button"
                      tabIndex={0}
                      onClick={() => setSelectedFileRecordId(file.record_id)}
                      onKeyDown={(event) => {
                        if (event.target !== event.currentTarget) return
                        if (event.key !== 'Enter' && event.key !== ' ') return
                        event.preventDefault()
                        setSelectedFileRecordId(file.record_id)
                      }}
                      className="group relative min-h-[270px] cursor-pointer overflow-hidden rounded-3xl border border-white/[0.08] bg-[#15191d] shadow-[0_18px_60px_rgba(0,0,0,0.18)] transition-all duration-300 hover:-translate-y-1 hover:border-white/[0.16] hover:shadow-[0_28px_80px_rgba(0,0,0,0.28)] focus:outline-none focus-visible:ring-2 focus-visible:ring-cyan-300/70 focus-visible:ring-offset-2 focus-visible:ring-offset-[#111417]"
                    >
                      <div className="relative h-28 overflow-hidden border-b border-white/[0.04] bg-[#080a0c]">
                        <div className={`absolute inset-x-0 bottom-0 h-20 bg-gradient-to-r ${visual.glow} blur-xl transition-transform duration-500 group-hover:scale-110`} aria-hidden="true" />
                        <div className="absolute inset-0 bg-[radial-gradient(circle_at_70%_0%,rgba(255,255,255,0.08),transparent_38%),linear-gradient(180deg,rgba(0,0,0,0.05),rgba(0,0,0,0.62))]" aria-hidden="true" />
                        <div className="relative flex h-full flex-col justify-between p-4">
                          <div className="flex items-start justify-between gap-3">
                            <div className="inline-flex items-center gap-1.5 text-[11px] font-black uppercase tracking-[0.14em] text-white">
                              <Icon className="h-3.5 w-3.5" />
                              {typeLabel(kind)}
                            </div>
                            <div className="inline-flex items-center gap-1 rounded-full bg-black/45 px-2.5 py-1 text-[11px] font-medium text-slate-300 backdrop-blur">
                              <Sparkles className="h-3 w-3 text-cyan-300" />
                              {t('playbooks.knowledge_base.ai_summary')}
                            </div>
                          </div>
                          <div className={`flex h-10 w-10 items-center justify-center rounded-xl ${visual.icon}`}>
                            <Icon className="h-5 w-5" />
                          </div>
                        </div>
                      </div>

                      <div className="flex min-h-[164px] flex-col p-4">
                        <div className="mb-2.5 flex flex-wrap items-center gap-2">
                          <Badge variant={statusVariant(file.extraction_status)}>{statusLabel(file.extraction_status)}</Badge>
                          {file.applies_to_all_playbooks && <Badge variant="info">{t('playbooks.knowledge_base.all_playbooks')}</Badge>}
                        </div>

                        <h3 className="line-clamp-2 text-base font-bold leading-tight tracking-[-0.02em] text-white">
                          {displayName(file)}
                        </h3>
                        <p className="mt-2 line-clamp-3 text-xs leading-5 text-slate-400">
                          {summaryPreview(file)}
                        </p>

                        {tags.length > 0 && (
                          <div className="mt-3 mb-4 flex flex-wrap gap-1.5">
                            {tags.map((tag) => (
                              <span key={tag} className="rounded-full bg-white/[0.07] px-2 py-0.5 text-[11px] text-slate-400">
                                {tag}
                              </span>
                            ))}
                          </div>
                        )}

                        {isProcessing(file.extraction_status) && (
                          <div className="mt-4 space-y-1.5">
                            <div className="flex items-center justify-between text-xs text-slate-400">
                              <span>{statusLabel(file.extraction_status)}</span>
                              <span>{statusProgress(file.extraction_status)}%</span>
                            </div>
                            <div className="h-1.5 rounded-full bg-white/[0.08]">
                              <div
                                className="h-1.5 rounded-full bg-cyan-300 transition-all"
                                style={{ width: `${statusProgress(file.extraction_status)}%` }}
                              />
                            </div>
                          </div>
                        )}

                        <div className="mt-auto flex items-center justify-between gap-3 border-t border-white/[0.07] pt-4 text-xs text-slate-400">
                          <div className="min-w-0 space-y-1">
                            <div className="flex min-w-0 items-center gap-2">
                              <FooterIcon className="h-3.5 w-3.5 shrink-0" />
                              <span className="truncate">{sourceLabel(file, kind)}</span>
                            </div>
                            <div className="flex items-center gap-2">
                              <Clock3 className="h-3.5 w-3.5" />
                              <span>{formatFileSize(file.file_size_bytes)}</span>
                              <span>·</span>
                              <span>{relativeDate(file.created_at)}</span>
                            </div>
                          </div>
                          {kind !== 'website' && (
                            <Button
                              variant="ghost"
                              size="sm"
                              className="shrink-0 border-white/[0.08] bg-white/[0.03] text-slate-200 hover:bg-white/[0.08]"
                              icon={<Download className="h-4 w-4" />}
                              onClick={(event) => {
                                event.stopPropagation()
                                window.location.href = `/playbooks/${playbook.id}/knowledge_base_files/${file.record_id}/download`
                              }}
                            >
                              {t('playbooks.knowledge_base.download')}
                            </Button>
                          )}
                        </div>
                      </div>
                    </article>
                  )
                })}
              </div>
            )}
          </div>
        </section>

        {selectedEntry && (
          <KnowledgeFileSlideOver
            entry={selectedEntry}
            playbookId={playbook.id}
            onClose={() => setSelectedFileRecordId(null)}
          />
        )}

        {isAddModalOpen && (
          <div
            className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4 backdrop-blur-sm"
            onMouseDown={closeAddModal}
          >
            <div
              role="dialog"
              aria-modal="true"
              aria-labelledby="add-knowledge-modal-title"
              className="w-full max-w-lg rounded-2xl border border-white/[0.08] bg-[#15191d] p-5 shadow-2xl"
              onMouseDown={(event) => event.stopPropagation()}
            >
              <div className="mb-5 flex items-start justify-between gap-4">
                <div>
                  <h2 id="add-knowledge-modal-title" className="text-lg font-semibold tracking-[-0.02em] text-white">{t('playbooks.knowledge_base.modal.title')}</h2>
                  <p className="mt-1 text-sm text-slate-400">{t('playbooks.knowledge_base.modal.description')}</p>
                </div>
                <button
                  type="button"
                  onClick={closeAddModal}
                  className="rounded-lg p-1 text-slate-400 transition-colors hover:bg-white/[0.06] hover:text-white disabled:cursor-not-allowed disabled:opacity-50"
                  disabled={isUploading}
                  aria-label={t('playbooks.knowledge_base.modal.close')}
                >
                  <X className="h-5 w-5" />
                </button>
              </div>

              <div className="space-y-4">
                <div className="grid grid-cols-2 gap-2 rounded-xl bg-white/[0.045] p-1">
                  <button
                    type="button"
                    onClick={() => {
                      setSourceType('file')
                      setError(selectedFile && fileExceedsUploadLimit(selectedFile) ? `${selectedFile.name} exceeds the ${MAX_UPLOAD_FILE_SIZE_LABEL} upload limit.` : null)
                    }}
                    className={`inline-flex h-9 items-center justify-center gap-2 rounded-lg text-sm font-medium transition-all ${sourceType === 'file' ? 'bg-[#090b0d] text-white shadow-[0_8px_24px_rgba(0,0,0,0.25)]' : 'text-slate-400 hover:text-white'}`}
                  >
                    <FileText className="h-4 w-4" />
                    {t('playbooks.knowledge_base.modal.file')}
                  </button>
                  <button
                    type="button"
                    onClick={() => {
                      setSourceType('url')
                      setError(null)
                    }}
                    className={`inline-flex h-9 items-center justify-center gap-2 rounded-lg text-sm font-medium transition-all ${sourceType === 'url' ? 'bg-[#090b0d] text-white shadow-[0_8px_24px_rgba(0,0,0,0.25)]' : 'text-slate-400 hover:text-white'}`}
                  >
                    <Link className="h-4 w-4" />
                    {t('playbooks.knowledge_base.modal.url')}
                  </button>
                </div>

                {sourceType === 'file' ? (
                  <>
                    <input
                      ref={fileInputRef}
                      type="file"
                      className="hidden"
                      onChange={(event) => selectFile(event.target.files)}
                    />
                    <button
                      type="button"
                      onClick={() => fileInputRef.current?.click()}
                      onDragOver={(event) => event.preventDefault()}
                      onDrop={(event) => {
                        event.preventDefault()
                        selectFile(event.dataTransfer.files)
                      }}
                      className="flex w-full flex-col items-center justify-center rounded-2xl border border-dashed border-white/15 bg-white/[0.04] px-6 py-8 text-center transition-all hover:border-cyan-300/35 hover:bg-cyan-300/[0.06]"
                    >
                      <Upload className="mb-2 h-7 w-7 text-slate-400" />
                      <p className="text-sm font-medium text-white">{t('playbooks.knowledge_base.modal.dropzone_title')}</p>
                      {selectedFile ? (
                        <div className="mt-2 max-w-full text-xs">
                          <div className={`flex max-w-sm items-center justify-center gap-3 ${fileExceedsUploadLimit(selectedFile) ? 'text-red-200' : 'text-cyan-200'}`}>
                            <span className="truncate">{selectedFile.name}</span>
                            <span className="shrink-0">{formatFileSize(selectedFile.size)}</span>
                          </div>
                          {fileExceedsUploadLimit(selectedFile) && (
                            <p className="mt-1 text-red-200">File exceeds {MAX_UPLOAD_FILE_SIZE_LABEL} and cannot be uploaded.</p>
                          )}
                        </div>
                      ) : (
                        <p className="mt-1 text-xs text-slate-500">{t('playbooks.knowledge_base.modal.dropzone_hint')} Max file size: {MAX_UPLOAD_FILE_SIZE_LABEL}</p>
                      )}
                    </button>
                  </>
                ) : (
                  <label className="block text-sm font-medium text-white">
                    {t('playbooks.knowledge_base.modal.source_url')}
                    <input
                      type="url"
                      value={url}
                      onChange={(event) => {
                        setUrl(event.target.value)
                        setError(null)
                      }}
                      placeholder={t('playbooks.knowledge_base.modal.url_placeholder')}
                      className="mt-2 h-11 w-full rounded-xl border border-white/[0.08] bg-white/[0.045] px-3.5 text-sm text-white outline-none transition-all placeholder:text-slate-500 focus:border-cyan-300/35 focus:ring-4 focus:ring-cyan-400/10"
                    />
                    <span className="mt-1.5 block text-xs font-normal text-slate-500">{t('playbooks.knowledge_base.modal.url_hint')}</span>
                  </label>
                )}

                {error && <p className="rounded-xl border border-red-400/25 bg-red-500/10 px-3 py-2 text-sm text-red-200">{error}</p>}

                <div className="flex justify-end gap-2 pt-1">
                  <Button variant="secondary" onClick={closeAddModal} disabled={isUploading}>{t('playbooks.knowledge_base.modal.cancel')}</Button>
                  <Button
                    variant="primary"
                    disabled={isUploading || (sourceType === 'file' ? !selectedFile || fileExceedsUploadLimit(selectedFile) : !url.trim())}
                    icon={isUploading ? <Loader className="h-4 w-4 animate-spin" /> : undefined}
                    onClick={() => void uploadKnowledge()}
                  >
                    {t('playbooks.knowledge_base.add_knowledge')}
                  </Button>
                </div>
              </div>
            </div>
          </div>
        )}
      </div>
    </PlaybookLayout>
  )
}

interface StatCardProps {
  label: string
  value: number
  icon: typeof LibraryBig
  accentClass: string
}

function StatCard({ label, value, icon: Icon, accentClass }: StatCardProps) {
  return (
    <div className="min-w-0 rounded-2xl border border-white/[0.09] bg-black/18 px-4 py-3.5 backdrop-blur-sm shadow-[inset_0_1px_0_rgba(255,255,255,0.045)] lg:px-5">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="truncate text-xs text-white/55 lg:text-sm">{label}</p>
          <p className="mt-1.5 text-3xl font-semibold tracking-[-0.04em] text-white">{value}</p>
        </div>
        <Icon className={`h-5 w-5 ${accentClass}`} />
      </div>
    </div>
  )
}

interface KnowledgeFileSlideOverProps {
  entry: KnowledgeFileEntry
  playbookId: number
  onClose: () => void
}

function KnowledgeFileSlideOver({ entry, playbookId, onClose }: KnowledgeFileSlideOverProps) {
  const { file, kind } = entry
  const [extractedText, setExtractedText] = useState<string | null>(file.extracted_text || null)
  const [isExtractLoading, setIsExtractLoading] = useState(false)
  const [extractError, setExtractError] = useState<string | null>(null)
  const Icon = getTypeIcon(kind)
  const tags = summaryTags(file)
  const source = sourceLabel(file, kind)
  const sourceUrl = file.source_final_url || file.source_url
  const createdAt = new Date(file.created_at).toLocaleDateString('en-US', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  })
  const extractedContent = extractedText || extractError || (
    isProcessing(file.extraction_status)
      ? translate('playbooks.knowledge_base.slideover.extraction_running')
      : file.extraction_error || translate('playbooks.knowledge_base.slideover.no_extracted_content')
  )
  const downloadPath = `/playbooks/${playbookId}/knowledge_base_files/${file.record_id}/download`

  useEffect(() => {
    if (isProcessing(file.extraction_status)) return

    const controller = new AbortController()

    const loadExtract = async () => {
      setIsExtractLoading(true)
      setExtractError(null)

      try {
        const response = await fetch(`/playbooks/${playbookId}/knowledge_base_files/${file.record_id}/extract`, {
          headers: { Accept: 'application/json' },
          signal: controller.signal,
        })
        const payload = await parseJsonResponse<KnowledgeExtractResponse>(response)

        if (!response.ok) throw new Error(payload.error || translate('playbooks.knowledge_base.errors.request_failed', { status: response.status }))
        setExtractedText(payload.extracted_text || null)
      } catch (loadError) {
        if (loadError instanceof DOMException && loadError.name === 'AbortError') return

        setExtractError(loadError instanceof Error ? loadError.message : translate('playbooks.knowledge_base.errors.request_failed', { status: 0 }))
      } finally {
        if (!controller.signal.aborted) setIsExtractLoading(false)
      }
    }

    void loadExtract()

    return () => controller.abort()
  }, [file.record_id, file.extraction_status, playbookId])

  return (
    <div
      className="fixed inset-0 z-50 flex justify-end bg-black/70 backdrop-blur-[2px]"
      onMouseDown={onClose}
    >
      <aside
        role="dialog"
        aria-modal="true"
        aria-labelledby="knowledge-file-slideover-title"
        className="relative h-full w-full max-w-3xl overflow-y-auto border-l border-white/[0.08] bg-[#090a0b] text-white shadow-[-28px_0_80px_rgba(0,0,0,0.45)]"
        onMouseDown={(event) => event.stopPropagation()}
      >
        <div className="pointer-events-none absolute inset-x-0 top-0 h-36 bg-[radial-gradient(circle_at_50%_0%,rgba(34,211,238,0.18),transparent_42%),linear-gradient(100deg,rgba(20,184,166,0.10),rgba(168,85,247,0.10),transparent_65%)]" aria-hidden="true" />
        <button
          type="button"
          onClick={onClose}
          className="absolute right-4 top-4 z-10 rounded-full p-1.5 text-slate-400 transition-colors hover:bg-white/[0.06] hover:text-white focus:outline-none focus-visible:ring-2 focus-visible:ring-cyan-300/70"
          aria-label={t('playbooks.knowledge_base.slideover.close')}
        >
          <X className="h-5 w-5" />
        </button>

        <div className="relative px-6 pb-8 pt-6 sm:px-8 lg:px-10">
          <div className="inline-flex items-center gap-2 text-xs font-black uppercase tracking-[0.16em] text-cyan-200">
            <Sparkles className="h-3.5 w-3.5 text-cyan-300" />
            {typeLabel(kind)}
          </div>

          <div className="mt-28 space-y-5">
            <div>
              <h2 id="knowledge-file-slideover-title" className="text-3xl font-bold tracking-[-0.04em] text-white">
                {displayName(file)}
              </h2>
              <div className="mt-4 flex flex-wrap items-center gap-x-5 gap-y-2 text-sm text-slate-400">
                <span className="inline-flex items-center gap-2">
                  <CalendarDays className="h-4 w-4" />
                  {createdAt}
                </span>
                <span className="inline-flex items-center gap-2">
                  <Clock3 className="h-4 w-4" />
                  {formatFileSize(file.file_size_bytes)}
                </span>
                <span className="inline-flex items-center gap-2">
                  <Icon className="h-4 w-4" />
                  {statusLabel(file.extraction_status)}
                </span>
              </div>
            </div>

            <section className="rounded-2xl border border-cyan-300/25 bg-cyan-300/[0.055] p-5 shadow-[inset_0_1px_0_rgba(255,255,255,0.04)]">
              <div className="mb-3 inline-flex items-center gap-2 text-xs font-black uppercase tracking-[0.12em] text-cyan-300">
                <Sparkles className="h-4 w-4" />
                {t('playbooks.knowledge_base.ai_summary')}
              </div>
              <p className="text-base font-medium leading-7 text-slate-100">
                {summaryPreview(file)}
              </p>
            </section>

            {tags.length > 0 && (
              <section>
                <h3 className="text-sm font-semibold text-white">{t('playbooks.knowledge_base.slideover.tags')}</h3>
                <div className="mt-3 flex flex-wrap gap-2">
                  {tags.map((tag) => (
                    <span key={tag} className="rounded-full bg-white/[0.10] px-3 py-1 text-sm text-slate-300">
                      {tag}
                    </span>
                  ))}
                </div>
              </section>
            )}

            <section>
              <h3 className="text-sm font-semibold text-white">{t('playbooks.knowledge_base.slideover.source')}</h3>
              {sourceUrl ? (
                <a
                  href={sourceUrl}
                  target="_blank"
                  rel="noreferrer"
                  className="mt-3 flex items-center justify-between gap-3 rounded-2xl bg-white/[0.08] px-4 py-3 text-sm font-semibold text-slate-100 transition-colors hover:bg-white/[0.12] focus:outline-none focus-visible:ring-2 focus-visible:ring-cyan-300/70"
                >
                  <span className="inline-flex min-w-0 items-center gap-3">
                    <Globe2 className="h-4 w-4 shrink-0 text-cyan-300" />
                    <span className="truncate">{source}</span>
                  </span>
                  <ExternalLink className="h-4 w-4 shrink-0 text-cyan-300" />
                </a>
              ) : (
                <button
                  type="button"
                  onClick={() => { window.location.href = downloadPath }}
                  className="mt-3 flex w-full items-center justify-between gap-3 rounded-2xl bg-white/[0.08] px-4 py-3 text-sm font-semibold text-slate-100 transition-colors hover:bg-white/[0.12] focus:outline-none focus-visible:ring-2 focus-visible:ring-cyan-300/70"
                >
                  <span className="inline-flex min-w-0 items-center gap-3">
                    <FileText className="h-4 w-4 shrink-0 text-cyan-300" />
                    <span className="truncate">{source}</span>
                  </span>
                  <Download className="h-4 w-4 shrink-0 text-cyan-300" />
                </button>
              )}
            </section>

            <section>
              <h3 className="text-sm font-semibold text-white">{t('playbooks.knowledge_base.slideover.extracted_content')}</h3>
              <div className="mt-3 max-h-72 overflow-y-auto rounded-2xl bg-white/[0.08] px-4 py-4 text-sm leading-6 text-slate-300 custom-scrollbar">
                {isExtractLoading ? <Loader className="h-4 w-4 animate-spin text-cyan-300" /> : extractedContent}
              </div>
            </section>

            {kind !== 'website' && (
              <Button
                variant="secondary"
                fullWidth
                className="border-white/[0.10] bg-transparent text-slate-100 hover:bg-white/[0.08]"
                icon={<Download className="h-4 w-4" />}
                onClick={() => { window.location.href = downloadPath }}
              >
                {t('playbooks.knowledge_base.slideover.download_source')}
              </Button>
            )}
          </div>
        </div>
      </aside>
    </div>
  )
}

interface EmptyKnowledgeBaseProps {
  isUploading: boolean
  onUpload: () => void
}

function EmptyKnowledgeBase({ isUploading, onUpload }: EmptyKnowledgeBaseProps) {
  return (
    <div className="relative overflow-hidden rounded-3xl border border-dashed border-white/[0.12] bg-white/[0.035] px-6 py-12 text-center shadow-[inset_0_1px_0_rgba(255,255,255,0.04)]">
      <div className="pointer-events-none absolute inset-x-0 top-0 h-24 bg-gradient-to-r from-cyan-400/20 via-violet-400/15 to-rose-400/20 blur-2xl" aria-hidden="true" />
      <div className="relative mx-auto flex h-12 w-12 items-center justify-center rounded-2xl bg-cyan-400 text-slate-950 shadow-[0_18px_48px_rgba(34,211,238,0.2)]">
        <BookOpenText className="h-6 w-6" />
      </div>
      <h2 className="relative mt-5 text-lg font-bold tracking-[-0.03em] text-white">{t('playbooks.knowledge_base.empty_title')}</h2>
      <p className="relative mx-auto mt-2 max-w-xl text-sm leading-6 text-slate-400">
        {t('playbooks.knowledge_base.empty_description')}
      </p>
      <button
        type="button"
        disabled={isUploading}
        onClick={onUpload}
        className="relative mt-6 inline-flex h-10 items-center justify-center gap-2 rounded-xl bg-cyan-400 px-5 text-sm font-semibold text-slate-950 transition-all hover:-translate-y-0.5 hover:bg-cyan-300 disabled:cursor-not-allowed disabled:opacity-60"
      >
        {isUploading ? <Loader className="h-4 w-4 animate-spin" /> : <File className="h-4 w-4" />}
        {t('playbooks.knowledge_base.upload_first_source')}
      </button>
    </div>
  )
}
