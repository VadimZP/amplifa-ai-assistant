// Customer-facing playbook detail page
// Shows full playbook content with colored header bar and approve/request changes workflow
// Customers can upload files to references and proof points when playbook is editable
import { Link, router, usePage } from '@inertiajs/react'
import PlaybookLayout from '../../layouts/PlaybookLayout'
import { t } from '../../lib/i18n'
import { useEffect, useRef, useState, type ReactNode } from 'react'
import { Card, CardContent } from '../../components/ui/Card'
import { Badge } from '../../components/ui/Badge'
import { ExpandableText } from '../../components/ui/ExpandableText'
import {
  FileText,
  CheckCircle,
  AlertCircle,
  Archive,
  User,
  Target,
  Building,
  Award,
  MessageSquare,
  X,
  Upload,
  Loader2,
  Sparkles,
  Link2,
  Pencil,
  Plus,
  Trash2,
  type LucideIcon
} from 'lucide-react'
import {
  buildCustomerPlaybookFeedbackHref,
  getPlaybookFeedbackContextLabel,
  type PlaybookFeedbackContext
} from '../../lib/playbookFeedbackContext'


interface ApprovedBy {
  id: number
  first_name: string
  last_name: string
  full_name: string
}

interface Persona {
  [key: string]: string | number | string[] | undefined
  id: string
  name: string
  title: string
  order: number
  pain_points?: string[]
}

interface UseCase {
  [key: string]: string | number
  id: string
  title: string
  description: string
  order: number
}

interface Reference {
  [key: string]: string | number | undefined
  id: string
  customer_name?: string
  name?: string
  description: string
  order: number
  file_url?: string
  file_name?: string
  file_size?: number
}

interface ProofPoint {
  [key: string]: string | number | undefined
  id: string
  claim?: string
  title?: string
  description: string
  order: number
  file_url?: string
  file_name?: string
  file_size?: number
}

interface Comment {
  id: number
  body: string
  comment_type: string
  created_at: string
   feedback_context?: PlaybookFeedbackContext | null
  account: {
    id: number
    first_name: string
    last_name: string
    full_name: string
    'amplifa_admin?': boolean
  }
}

interface Playbook {
  id: number
  product: {
    name: string
    description: string
  }
  value_proposition: string | null
  status: string
  language: string
  created_at: string
  updated_at: string
  approved_at: string | null
  approved_by: ApprovedBy | null
  personae: Persona[]
  use_cases: UseCase[]
  references: Reference[]
  proof_points: ProofPoint[]
}

interface PlaybooksShowProps {
  playbook: Playbook
  comments: Comment[]
  canApprove: boolean
  canRequestChanges: boolean
  canArchive: boolean
  canUploadFiles: boolean
}

interface SharedProps {
  [key: string]: unknown
  auth: {
    account: {
      id: number
      email: string
      first_name: string
      last_name: string
      full_name: string
      role: string
    }
    organization?: {
      id: number
      name: string
    }
  }
  flash?: {
    notice?: string
    alert?: string
  }
  impersonating?: boolean
  impersonating_admin?: {
    id: number
    name: string
    email: string
  }
}

type KnowledgeTone = 'cyan' | 'blue' | 'purple' | 'emerald' | 'pink' | 'amber'
type EditableSection = 'product_description' | 'value_proposition' | 'personae' | 'use_cases' | 'references' | 'proof_points'
type PlaybookSectionDraft = string | Persona[] | UseCase[] | Reference[] | ProofPoint[] | null

const KNOWLEDGE_TONES: Record<KnowledgeTone, { glow: string; icon: string; band: string; chip: string }> = {
  cyan: {
    glow: 'before:bg-[radial-gradient(circle_at_22%_0%,rgba(53,202,222,0.28),transparent_42%)]',
    icon: 'bg-cyan-300/10 text-cyan-200 border-cyan-300/20',
    band: 'from-cyan-400/24 via-cyan-300/8 to-transparent',
    chip: 'border-cyan-300/18 bg-cyan-300/8 text-cyan-100'
  },
  blue: {
    glow: 'before:bg-[radial-gradient(circle_at_24%_0%,rgba(59,130,246,0.24),transparent_42%)]',
    icon: 'bg-blue-300/10 text-blue-200 border-blue-300/20',
    band: 'from-blue-400/24 via-blue-300/8 to-transparent',
    chip: 'border-blue-300/18 bg-blue-300/8 text-blue-100'
  },
  purple: {
    glow: 'before:bg-[radial-gradient(circle_at_24%_0%,rgba(168,85,247,0.24),transparent_42%)]',
    icon: 'bg-purple-300/10 text-purple-200 border-purple-300/20',
    band: 'from-purple-400/24 via-purple-300/8 to-transparent',
    chip: 'border-purple-300/18 bg-purple-300/8 text-purple-100'
  },
  emerald: {
    glow: 'before:bg-[radial-gradient(circle_at_24%_0%,rgba(16,185,129,0.24),transparent_42%)]',
    icon: 'bg-emerald-300/10 text-emerald-200 border-emerald-300/20',
    band: 'from-emerald-400/24 via-emerald-300/8 to-transparent',
    chip: 'border-emerald-300/18 bg-emerald-300/8 text-emerald-100'
  },
  pink: {
    glow: 'before:bg-[radial-gradient(circle_at_24%_0%,rgba(236,72,153,0.24),transparent_42%)]',
    icon: 'bg-pink-300/10 text-pink-200 border-pink-300/20',
    band: 'from-pink-400/24 via-pink-300/8 to-transparent',
    chip: 'border-pink-300/18 bg-pink-300/8 text-pink-100'
  },
  amber: {
    glow: 'before:bg-[radial-gradient(circle_at_24%_0%,rgba(245,158,11,0.24),transparent_42%)]',
    icon: 'bg-amber-300/10 text-amber-200 border-amber-300/20',
    band: 'from-amber-400/24 via-amber-300/8 to-transparent',
    chip: 'border-amber-300/18 bg-amber-300/8 text-amber-100'
  }
}

interface KnowledgeSectionProps {
  icon: LucideIcon
  eyebrow: string
  title: string
  count?: number
  tone: KnowledgeTone
  action?: ReactNode
  children: ReactNode
}

function KnowledgeSection({ icon: Icon, eyebrow, title, count, tone, action, children }: KnowledgeSectionProps) {
  const classes = KNOWLEDGE_TONES[tone]

  return (
    <Card className={`!gap-0 !overflow-hidden !rounded-[28px] !py-0 before:opacity-100 ${classes.glow}`}>
      <div className={`relative bg-gradient-to-r ${classes.band} px-6 py-5 lg:px-7`}>
        <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
          <div className="flex items-stretch gap-4">
            <div className={`grid w-14 shrink-0 place-items-center rounded-2xl border shadow-[0_14px_32px_rgba(0,0,0,0.24)] ${classes.icon}`}>
              <Icon className="h-6 w-6" />
            </div>
            <div>
              <div className="mb-2 inline-flex items-center gap-1.5 rounded-full border border-white/[0.12] bg-white/[0.07] px-2.5 py-1 text-xs font-semibold uppercase tracking-[0.14em] text-[var(--foreground-muted)] shadow-[inset_0_1px_0_rgba(255,255,255,0.04)]">
                <Sparkles className="h-3.5 w-3.5 text-[var(--accent)]" />
                {eyebrow}
              </div>
              <h3 className="text-2xl font-semibold tracking-[-0.04em] text-[var(--foreground)]">{title}</h3>
            </div>
          </div>
          <div className="flex items-center gap-3 sm:justify-end">
            {typeof count === 'number' && (
              <span className={`inline-flex w-fit items-center rounded-full border px-3 py-1 text-sm font-semibold ${classes.chip}`}>
                {count}
              </span>
            )}
            {action}
          </div>
        </div>
      </div>
      <CardContent className="p-6 lg:p-7">
        {children}
      </CardContent>
    </Card>
  )
}

function KnowledgeItem({ children, className = '' }: { children: ReactNode; className?: string }) {
  return (
    <div className={`group rounded-2xl border border-white/[0.08] bg-white/[0.035] p-4 shadow-[inset_0_1px_0_rgba(255,255,255,0.035)] transition-all duration-200 hover:border-white/[0.16] hover:bg-white/[0.055] ${className}`}>
      {children}
    </div>
  )
}

function EmptyKnowledgeState({ children }: { children: ReactNode }) {
  return (
    <div className="rounded-2xl border border-dashed border-white/[0.12] bg-black/10 px-5 py-8 text-center text-sm text-[var(--foreground-muted)]">
      {children}
    </div>
  )
}

export default function Show({
  playbook: initialPlaybook,
  comments,
  canApprove,
  canRequestChanges,
  canArchive,
  canUploadFiles
}: PlaybooksShowProps) {
  const { flash } = usePage<SharedProps>().props
  // Note: account and organization are passed to PlaybookLayout via auth context

  const localizedText = (key: string) => String(t(key))

  const [showApproveModal, setShowApproveModal] = useState(false)
  const [showRequestChangesModal, setShowRequestChangesModal] = useState(false)
  const [showArchiveModal, setShowArchiveModal] = useState(false)
  const [approveComment, setApproveComment] = useState('')
  const [changesComment, setChangesComment] = useState('')
  const [isSubmitting, setIsSubmitting] = useState(false)

  // File upload state
  const [playbook, setPlaybook] = useState(initialPlaybook)
  const [uploadingFiles, setUploadingFiles] = useState<Record<string, boolean>>({})
  const [uploadErrors, setUploadErrors] = useState<Record<string, string>>({})
  const [editingSection, setEditingSection] = useState<EditableSection | null>(null)
  const [sectionDraft, setSectionDraft] = useState<PlaybookSectionDraft>(null)
  const [savingSection, setSavingSection] = useState(false)
  const referenceFileInputs = useRef<Record<string, HTMLInputElement | null>>({})
  const proofPointFileInputs = useRef<Record<string, HTMLInputElement | null>>({})

  useEffect(() => {
    setPlaybook(initialPlaybook)
  }, [initialPlaybook])

  // Gradient and image are now handled by PlaybookLayout

  // File upload handler
  const handleFileUpload = async (itemId: string, fileType: 'reference' | 'proof_point', file: File) => {
    setUploadingFiles(prev => ({ ...prev, [itemId]: true }))
    setUploadErrors(prev => ({ ...prev, [itemId]: '' }))

    const formData = new FormData()
    formData.append('file', file)
    formData.append('file_type', fileType)
    formData.append('item_id', itemId)

    try {
      const response = await fetch(`/playbooks/${playbook.id}/upload_file`, {
        method: 'POST',
        body: formData,
        headers: {
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || ''
        }
      })

      if (!response.ok) {
        const errorData = await response.json()
        throw new Error(errorData.error || t('playbooks.files.upload_failed'))
      }

      const result = await response.json()

      // Update local state with uploaded file info
      if (fileType === 'reference') {
        setPlaybook(prev => ({
          ...prev,
          references: prev.references.map(r =>
            r.id === itemId
              ? { ...r, file_url: result.file_url, file_name: result.file_name, file_size: result.file_size }
              : r
          )
        }))
      } else {
        setPlaybook(prev => ({
          ...prev,
          proof_points: prev.proof_points.map(pp =>
            pp.id === itemId
              ? { ...pp, file_url: result.file_url, file_name: result.file_name, file_size: result.file_size }
              : pp
          )
        }))
      }
    } catch (error) {
      setUploadErrors(prev => ({
        ...prev,
        [itemId]: error instanceof Error ? error.message : t('playbooks.files.upload_failed')
      }))
    } finally {
      setUploadingFiles(prev => ({ ...prev, [itemId]: false }))
    }
  }

  const formatFileSize = (bytes?: number): string => {
    if (!bytes) return ''
    if (bytes < 1024) return `${bytes} B`
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
  }

  const formatDate = (dateString: string) => {
    return new Date(dateString).toLocaleDateString('en-US', {
      year: 'numeric',
      month: 'long',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit'
    })
  }

  const handleApprove = () => {
    setIsSubmitting(true)
    router.post(`/playbooks/${playbook.id}/approve`, { comment: approveComment }, {
      onFinish: () => {
        setIsSubmitting(false)
        setShowApproveModal(false)
        setApproveComment('')
      }
    })
  }

  const handleRequestChanges = () => {
    if (!changesComment.trim()) {
      alert(t('playbooks.actions.comment_required'))
      return
    }
    setIsSubmitting(true)
    router.post(`/playbooks/${playbook.id}/request_changes`, {
      comment: changesComment,
      feedback_context: { tab: 'training_data' }
    }, {
      onFinish: () => {
        setIsSubmitting(false)
        setShowRequestChangesModal(false)
        setChangesComment('')
      }
    })
  }

  const handleArchive = () => {
    setIsSubmitting(true)
    router.post(`/playbooks/${playbook.id}/archive`, {}, {
      onFinish: () => {
        setIsSubmitting(false)
        setShowArchiveModal(false)
      }
    })
  }

  const sectionTitle = (section: EditableSection) => {
    switch (section) {
      case 'product_description': return t('playbooks.edit.product_description')
      case 'value_proposition': return t('playbooks.sections.value_proposition')
      case 'personae': return t('playbooks.sections.personae')
      case 'use_cases': return t('playbooks.sections.use_cases')
      case 'references': return t('playbooks.sections.references')
      case 'proof_points': return t('playbooks.sections.proof_points')
    }
  }

  const openSectionEditor = (section: EditableSection) => {
    setEditingSection(section)
    switch (section) {
      case 'product_description':
        setSectionDraft(playbook.product.description || '')
        return
      case 'value_proposition':
        setSectionDraft(playbook.value_proposition || '')
        return
      case 'personae':
        setSectionDraft(playbook.personae.map((persona) => ({ ...persona, pain_points: [...(persona.pain_points || [])] })))
        return
      case 'use_cases':
        setSectionDraft(playbook.use_cases.map((useCase) => ({ ...useCase })))
        return
      case 'references':
        setSectionDraft(playbook.references.map((reference) => ({ ...reference })))
        return
      case 'proof_points':
        setSectionDraft(playbook.proof_points.map((proofPoint) => ({ ...proofPoint })))
    }
  }

  const closeSectionEditor = () => {
    if (savingSection) return
    setEditingSection(null)
    setSectionDraft(null)
  }

  const sectionPayload = () => {
    if (!editingSection) return null
    switch (editingSection) {
      case 'product_description': return { product: { ...playbook.product, description: typeof sectionDraft === 'string' ? sectionDraft : '' } }
      case 'value_proposition': return { value_proposition: typeof sectionDraft === 'string' ? sectionDraft : '' }
      case 'personae': return { personae: Array.isArray(sectionDraft) ? sectionDraft as Persona[] : [] }
      case 'use_cases': return { use_cases: Array.isArray(sectionDraft) ? sectionDraft as UseCase[] : [] }
      case 'references': return { references: Array.isArray(sectionDraft) ? sectionDraft as Reference[] : [] }
      case 'proof_points': return { proof_points: Array.isArray(sectionDraft) ? sectionDraft as ProofPoint[] : [] }
    }
  }

  const saveSection = () => {
    const payload = sectionPayload()
    if (!payload) return
    setSavingSection(true)
    router.patch(`/playbooks/${playbook.id}`, { playbook: payload }, {
      preserveScroll: true,
      onSuccess: () => closeSectionEditor(),
      onFinish: () => setSavingSection(false)
    })
  }

  const generateDraftId = () => {
    if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
      return crypto.randomUUID()
    }

    return `draft-${Date.now()}-${Math.random().toString(36).slice(2)}`
  }

  const addDraftItem = () => {
    if (!editingSection || !Array.isArray(sectionDraft)) return
    const id = generateDraftId()
    switch (editingSection) {
      case 'personae':
        setSectionDraft((currentDraft): PlaybookSectionDraft => {
          const items = Array.isArray(currentDraft) ? currentDraft as Persona[] : []
          const newItem: Persona = {
            id,
            name: localizedText('playbooks.edit.new_persona_name'),
            title: localizedText('playbooks.edit.new_persona_title'),
            order: items.length + 1,
            pain_points: [localizedText('playbooks.edit.new_pain_point')]
          }
          return [...items, newItem]
        })
        return
      case 'use_cases':
        setSectionDraft((currentDraft): PlaybookSectionDraft => {
          const items = Array.isArray(currentDraft) ? currentDraft as UseCase[] : []
          const newItem: UseCase = {
            id,
            title: localizedText('playbooks.edit.new_use_case_title'),
            description: localizedText('playbooks.edit.new_use_case_description'),
            order: items.length + 1
          }
          return [...items, newItem]
        })
        return
      case 'references':
        setSectionDraft((currentDraft): PlaybookSectionDraft => {
          const items = Array.isArray(currentDraft) ? currentDraft as Reference[] : []
          const newItem: Reference = {
            id,
            customer_name: localizedText('playbooks.edit.new_reference_customer'),
            description: localizedText('playbooks.edit.new_reference_description'),
            order: items.length + 1
          }
          return [...items, newItem]
        })
        return
      case 'proof_points':
        setSectionDraft((currentDraft): PlaybookSectionDraft => {
          const items = Array.isArray(currentDraft) ? currentDraft as ProofPoint[] : []
          const newItem: ProofPoint = {
            id,
            claim: localizedText('playbooks.edit.new_proof_point_claim'),
            description: localizedText('playbooks.edit.new_proof_point_description'),
            order: items.length + 1
          }
          return [...items, newItem]
        })
    }
  }

  const removeDraftItem = (id: string) => {
    if (!editingSection || !Array.isArray(sectionDraft)) return
    if (!confirm(t('playbooks.edit.confirm_delete_item'))) return
    switch (editingSection) {
      case 'personae':
        setSectionDraft((sectionDraft as Persona[]).filter((item) => item.id !== id))
        return
      case 'use_cases':
        setSectionDraft((sectionDraft as UseCase[]).filter((item) => item.id !== id))
        return
      case 'references':
        setSectionDraft((sectionDraft as Reference[]).filter((item) => item.id !== id))
        return
      case 'proof_points':
        setSectionDraft((sectionDraft as ProofPoint[]).filter((item) => item.id !== id))
    }
  }

  const updatePersonaDraft = (id: string, field: keyof Persona, value: string | string[]) => {
    if (!Array.isArray(sectionDraft)) return
    setSectionDraft((sectionDraft as Persona[]).map((persona) => persona.id === id ? { ...persona, [field]: value } : persona))
  }

  const updateUseCaseDraft = (id: string, field: keyof UseCase, value: string) => {
    if (!Array.isArray(sectionDraft)) return
    setSectionDraft((sectionDraft as UseCase[]).map((useCase) => useCase.id === id ? { ...useCase, [field]: value } : useCase))
  }

  const updateReferenceDraft = (id: string, field: keyof Reference, value: string) => {
    if (!Array.isArray(sectionDraft)) return
    setSectionDraft((sectionDraft as Reference[]).map((reference) => reference.id === id ? { ...reference, [field]: value } : reference))
  }

  const updateProofPointDraft = (id: string, field: keyof ProofPoint, value: string) => {
    if (!Array.isArray(sectionDraft)) return
    setSectionDraft((sectionDraft as ProofPoint[]).map((proofPoint) => proofPoint.id === id ? { ...proofPoint, [field]: value } : proofPoint))
  }

  const EditSectionButton = ({ section }: { section: EditableSection }) => {
    if (!canUploadFiles) return null
    return (
      <button
        type="button"
        onClick={() => openSectionEditor(section)}
        className="inline-flex h-9 items-center gap-2 rounded-full border border-white/[0.12] bg-white/[0.05] px-3 text-sm font-medium text-[var(--foreground)] transition-colors hover:bg-white/[0.09]"
      >
        <Pencil className="h-4 w-4" />
        {t('admin.common.edit')}
      </button>
    )
  }

  const getCommentTypeIcon = (type: string) => {
    switch (type) {
      case 'approval':
        return <CheckCircle className="h-4 w-4 text-[var(--success)]" />
      case 'request_changes':
        return <AlertCircle className="h-4 w-4 text-[var(--warning)]" />
      default:
        return <MessageSquare className="h-4 w-4 text-[var(--foreground-subtle)]" />
    }
  }

  return (
    <PlaybookLayout
      playbook={playbook}
      currentTab="training_data"
      canApprove={canApprove}
      canRequestChanges={canRequestChanges}
      canArchive={canArchive}
      flash={flash}
      canEditProductDescription={canUploadFiles}
      onApprove={() => setShowApproveModal(true)}
      onRequestChanges={() => setShowRequestChangesModal(true)}
      onArchive={() => setShowArchiveModal(true)}
      onEditProductDescription={() => openSectionEditor('product_description')}
    >
      {/* Status Banners */}
      {playbook.status === 'changes_requested' && (
        <div className="mb-6 rounded-[22px] border border-[var(--warning)]/25 bg-[var(--warning-muted)] p-4 shadow-[0_16px_42px_rgba(245,158,11,0.08)]">
          <p className="text-sm font-medium text-[var(--warning)]">
            {t('playbooks.show.changes_pending')}
          </p>
        </div>
      )}

      {/* Main Content */}
      <div className="space-y-6">
        {playbook.value_proposition && (
          <KnowledgeSection
            icon={Target}
            eyebrow={t('playbooks.knowledge_ui.value_proposition_eyebrow')}
            title={t('playbooks.sections.value_proposition')}
            tone="cyan"
            action={<EditSectionButton section="value_proposition" />}
          >
            <ExpandableText
              text={playbook.value_proposition}
              collapsedLines={10}
              className="max-w-5xl text-lg leading-8 tracking-[-0.02em] text-[var(--foreground-muted)]"
              seeMoreLabel={t('playbooks.knowledge_ui.see_more')}
              seeLessLabel={t('playbooks.knowledge_ui.see_less')}
            />
          </KnowledgeSection>
        )}

        <KnowledgeSection
          icon={User}
          eyebrow={t('playbooks.knowledge_ui.personae_eyebrow')}
          title={t('playbooks.sections.personae')}
          count={playbook.personae.length}
          tone="blue"
          action={<EditSectionButton section="personae" />}
        >
          {playbook.personae.length === 0 ? (
            <EmptyKnowledgeState>{t('admin.playbooks.no_personae')}</EmptyKnowledgeState>
          ) : (
            <div className="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-3">
              {playbook.personae.map((persona) => (
                <KnowledgeItem key={persona.id} className="min-h-[190px]">
                  <div className="mb-4 flex items-start justify-between gap-3">
                    <div>
                      <h4 className="text-lg font-semibold tracking-[-0.025em] text-[var(--foreground)]">{persona.name}</h4>
                      <p className="mt-1 text-sm font-medium text-[var(--accent)]">{persona.title}</p>
                    </div>
                    <span className="rounded-full border border-white/[0.08] bg-black/20 px-2 py-1 text-[11px] font-semibold text-[var(--foreground-subtle)]">
                      #{persona.order}
                    </span>
                  </div>
                  {persona.pain_points && persona.pain_points.length > 0 && (
                    <div>
                      <p className="mb-2 text-xs font-semibold uppercase tracking-[0.16em] text-[var(--foreground-subtle)]">
                        {t('playbooks.persona.pain_points')}
                      </p>
                      <ul className="space-y-2 text-sm leading-6 text-[var(--foreground-muted)]">
                        {persona.pain_points.map((point) => (
                          <li key={`${persona.id}-${point}`} className="flex gap-2">
                            <span className="mt-2 h-1.5 w-1.5 shrink-0 rounded-full bg-[var(--accent)]/70" />
                            <span>{point}</span>
                          </li>
                        ))}
                      </ul>
                    </div>
                  )}
                </KnowledgeItem>
              ))}
            </div>
          )}
        </KnowledgeSection>

        <KnowledgeSection
          icon={FileText}
          eyebrow={t('playbooks.knowledge_ui.use_cases_eyebrow')}
          title={t('playbooks.sections.use_cases')}
          count={playbook.use_cases.length}
          tone="purple"
          action={<EditSectionButton section="use_cases" />}
        >
          {playbook.use_cases.length === 0 ? (
            <EmptyKnowledgeState>{t('admin.playbooks.no_use_cases')}</EmptyKnowledgeState>
          ) : (
            <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
              {playbook.use_cases.map((useCase) => (
                <KnowledgeItem key={useCase.id}>
                  <div className="flex items-start gap-4">
                    <span className="grid h-9 w-9 shrink-0 place-items-center rounded-2xl border border-purple-300/15 bg-purple-300/10 text-sm font-semibold text-purple-100">
                      {useCase.order}
                    </span>
                    <div>
                      <h4 className="font-semibold tracking-[-0.02em] text-[var(--foreground)]">{useCase.title}</h4>
                      <p className="mt-2 leading-7 text-[var(--foreground-muted)]">{useCase.description}</p>
                    </div>
                  </div>
                </KnowledgeItem>
              ))}
            </div>
          )}
        </KnowledgeSection>

        <KnowledgeSection
          icon={Building}
          eyebrow={t('playbooks.knowledge_ui.references_eyebrow')}
          title={t('playbooks.sections.references')}
          count={playbook.references.length}
          tone="emerald"
          action={<EditSectionButton section="references" />}
        >
          {playbook.references.length === 0 ? (
            <EmptyKnowledgeState>{t('admin.playbooks.no_references')}</EmptyKnowledgeState>
          ) : (
            <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
              {playbook.references.map((reference) => (
                <KnowledgeItem key={reference.id}>
                  <h4 className="text-lg font-semibold tracking-[-0.025em] text-[var(--foreground)]">
                    {reference.customer_name || reference.name}
                  </h4>
                  <p className="mt-2 leading-7 text-[var(--foreground-muted)]">{reference.description}</p>
                  {reference.file_url ? (
                    <div className="mt-4 flex items-center gap-3 rounded-2xl border border-white/[0.08] bg-black/20 p-3">
                      <Link2 className="h-4 w-4 text-emerald-200" />
                      <a
                        href={reference.file_url}
                        className="min-w-0 flex-1 truncate text-sm font-medium text-[var(--accent)] hover:text-[var(--accent-hover)]"
                        target="_blank"
                        rel="noopener noreferrer"
                      >
                        {reference.file_name || t('playbooks.files.download')}
                      </a>
                      {reference.file_size && (
                        <span className="text-xs text-[var(--foreground-subtle)]">{formatFileSize(reference.file_size)}</span>
                      )}
                    </div>
                  ) : canUploadFiles && (
                    <div className="mt-4">
                      <input
                        type="file"
                        ref={el => { referenceFileInputs.current[reference.id] = el }}
                        onChange={(e) => {
                          const file = e.target.files?.[0]
                          if (file) handleFileUpload(reference.id, 'reference', file)
                        }}
                        accept=".pdf,.doc,.docx,.png,.jpg,.jpeg,.gif"
                        className="hidden"
                      />
                      <button
                        type="button"
                        onClick={() => referenceFileInputs.current[reference.id]?.click()}
                        disabled={uploadingFiles[reference.id]}
                        className="inline-flex items-center gap-2 rounded-full border border-white/[0.12] bg-white/[0.04] px-4 py-2 text-sm font-medium text-[var(--foreground)] transition-colors hover:bg-white/[0.08] disabled:opacity-50"
                      >
                        {uploadingFiles[reference.id] ? (
                          <>
                            <Loader2 className="h-4 w-4 animate-spin" />
                            {t('admin.playbooks.edit.uploading')}
                          </>
                        ) : (
                          <>
                            <Upload className="h-4 w-4" />
                            {t('admin.playbooks.edit.upload_file')}
                          </>
                        )}
                      </button>
                      {uploadErrors[reference.id] && (
                        <p className="mt-2 text-sm text-[var(--error)]">{uploadErrors[reference.id]}</p>
                      )}
                    </div>
                  )}
                </KnowledgeItem>
              ))}
            </div>
          )}
        </KnowledgeSection>

        <KnowledgeSection
          icon={Award}
          eyebrow={t('playbooks.knowledge_ui.proof_points_eyebrow')}
          title={t('playbooks.sections.proof_points')}
          count={playbook.proof_points.length}
          tone="pink"
          action={<EditSectionButton section="proof_points" />}
        >
          {playbook.proof_points.length === 0 ? (
            <EmptyKnowledgeState>{t('admin.playbooks.no_proof_points')}</EmptyKnowledgeState>
          ) : (
            <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
              {playbook.proof_points.map((proofPoint) => (
                <KnowledgeItem key={proofPoint.id}>
                  <h4 className="text-lg font-semibold tracking-[-0.025em] text-[var(--foreground)]">
                    {proofPoint.claim || proofPoint.title}
                  </h4>
                  <p className="mt-2 leading-7 text-[var(--foreground-muted)]">{proofPoint.description}</p>
                  {proofPoint.file_url ? (
                    <div className="mt-4 flex items-center gap-3 rounded-2xl border border-white/[0.08] bg-black/20 p-3">
                      <Link2 className="h-4 w-4 text-pink-200" />
                      <a
                        href={proofPoint.file_url}
                        className="min-w-0 flex-1 truncate text-sm font-medium text-[var(--accent)] hover:text-[var(--accent-hover)]"
                        target="_blank"
                        rel="noopener noreferrer"
                      >
                        {proofPoint.file_name || t('playbooks.files.download')}
                      </a>
                      {proofPoint.file_size && (
                        <span className="text-xs text-[var(--foreground-subtle)]">{formatFileSize(proofPoint.file_size)}</span>
                      )}
                    </div>
                  ) : canUploadFiles && (
                    <div className="mt-4">
                      <input
                        type="file"
                        ref={el => { proofPointFileInputs.current[proofPoint.id] = el }}
                        onChange={(e) => {
                          const file = e.target.files?.[0]
                          if (file) handleFileUpload(proofPoint.id, 'proof_point', file)
                        }}
                        accept=".pdf,.doc,.docx,.png,.jpg,.jpeg,.gif"
                        className="hidden"
                      />
                      <button
                        type="button"
                        onClick={() => proofPointFileInputs.current[proofPoint.id]?.click()}
                        disabled={uploadingFiles[proofPoint.id]}
                        className="inline-flex items-center gap-2 rounded-full border border-white/[0.12] bg-white/[0.04] px-4 py-2 text-sm font-medium text-[var(--foreground)] transition-colors hover:bg-white/[0.08] disabled:opacity-50"
                      >
                        {uploadingFiles[proofPoint.id] ? (
                          <>
                            <Loader2 className="h-4 w-4 animate-spin" />
                            {t('admin.playbooks.edit.uploading')}
                          </>
                        ) : (
                          <>
                            <Upload className="h-4 w-4" />
                            {t('admin.playbooks.edit.upload_file')}
                          </>
                        )}
                      </button>
                      {uploadErrors[proofPoint.id] && (
                        <p className="mt-2 text-sm text-[var(--error)]">{uploadErrors[proofPoint.id]}</p>
                      )}
                    </div>
                  )}
                </KnowledgeItem>
              ))}
            </div>
          )}
        </KnowledgeSection>

        <KnowledgeSection
          icon={MessageSquare}
          eyebrow={t('playbooks.knowledge_ui.comments_eyebrow')}
          title={t('playbooks.comments.title')}
          count={comments.length}
          tone="amber"
        >
          {comments.length === 0 ? (
            <EmptyKnowledgeState>{t('playbooks.comments.empty')}</EmptyKnowledgeState>
          ) : (
            <div className="space-y-4">
              {comments.map((comment) => (
                <KnowledgeItem key={comment.id}>
                  <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
                    <div className="flex flex-wrap items-center gap-2">
                      {getCommentTypeIcon(comment.comment_type)}
                      <span className="font-medium text-[var(--foreground)]">
                        {comment.account.full_name}
                      </span>
                      {comment.account['amplifa_admin?'] && (
                        <Badge variant="info" size="sm">
                          {t('navigation.app_name')}
                        </Badge>
                      )}
                      <span className="text-xs text-[var(--foreground-subtle)]">
                        {formatDate(comment.created_at)}
                      </span>
                    </div>
                    {comment.comment_type !== 'general' && (
                      <Badge variant="default" size="sm">
                        {t(`playbooks.comment_types.${comment.comment_type}`)}
                      </Badge>
                    )}
                  </div>
                  <p className="mt-3 leading-7 text-[var(--foreground-muted)]">{comment.body}</p>
                  {comment.feedback_context && getPlaybookFeedbackContextLabel(comment.feedback_context) && (
                    <div className="mt-3">
                      <Link
                        href={buildCustomerPlaybookFeedbackHref(playbook.id, comment.feedback_context) || '#'}
                        className="text-xs font-semibold uppercase tracking-[0.14em] text-[var(--accent)] transition-colors hover:text-[var(--accent-hover)]"
                      >
                        {getPlaybookFeedbackContextLabel(comment.feedback_context)}
                      </Link>
                    </div>
                  )}
                </KnowledgeItem>
              ))}
            </div>
          )}
        </KnowledgeSection>
      </div>

      {editingSection && (
        <div className="fixed inset-0 z-50 overflow-y-auto custom-scrollbar">
          <div className="flex min-h-full items-center justify-center p-4">
            <button
              type="button"
              className="fixed inset-0 bg-black/60 transition-opacity"
              onClick={closeSectionEditor}
              disabled={savingSection}
              aria-label={t('admin.common.cancel')}
            />
            <div className="relative w-full max-w-3xl rounded-xl border border-[var(--border)] bg-[var(--card)] p-6 shadow-xl">
              <div className="mb-5 flex items-start justify-between gap-4">
                <div>
              <h3 className="text-xl font-semibold text-[var(--foreground)]">{sectionTitle(editingSection)}</h3>
                  <p className="mt-1 text-sm text-[var(--foreground-muted)]">
                    {t('playbooks.edit.modal_description')}
                  </p>
                </div>
                <button type="button" onClick={closeSectionEditor} className="text-[var(--foreground-subtle)] hover:text-[var(--foreground)]">
                  <X className="h-5 w-5" />
                </button>
              </div>

              {typeof sectionDraft === 'string' && (
                <textarea
                  value={sectionDraft}
                  onChange={(event) => setSectionDraft(event.target.value)}
                  className="min-h-72 w-full rounded-xl border border-[var(--input-border)] bg-[var(--input)] px-3.5 py-3 text-sm text-[var(--foreground)] outline-none focus:ring-2 focus:ring-[var(--accent)] custom-scrollbar-skinny"
                />
              )}

              {editingSection === 'personae' && Array.isArray(sectionDraft) && (
                <div className="max-h-[60vh] space-y-4 overflow-y-auto pr-1 custom-scrollbar">
                  {(sectionDraft as Persona[]).map((persona) => (
                    <div key={persona.id} className="rounded-lg border border-[var(--border)] p-4">
                      <div className="flex items-start gap-3">
                        <div className="grid flex-1 gap-3 md:grid-cols-2">
                          <input value={persona.name} onChange={(event) => updatePersonaDraft(persona.id, 'name', event.target.value)} className="h-9 rounded-lg border border-[var(--input-border)] bg-[var(--input)] px-3 text-sm text-[var(--foreground)]" placeholder={t('admin.playbooks.edit.persona_name')} />
                          <input value={persona.title} onChange={(event) => updatePersonaDraft(persona.id, 'title', event.target.value)} className="h-9 rounded-lg border border-[var(--input-border)] bg-[var(--input)] px-3 text-sm text-[var(--foreground)]" placeholder={t('admin.playbooks.edit.persona_title')} />
                        </div>
                        <button type="button" onClick={() => removeDraftItem(persona.id)} className="text-[var(--error)] hover:text-red-400"><Trash2 className="h-4 w-4" /></button>
                      </div>
                      <textarea value={(persona.pain_points || []).join('\n')} onChange={(event) => updatePersonaDraft(persona.id, 'pain_points', event.target.value.split('\n'))} className="mt-3 min-h-24 w-full rounded-lg border border-[var(--input-border)] bg-[var(--input)] px-3 py-2 text-sm text-[var(--foreground)]" placeholder={t('playbooks.persona.pain_points')} />
                    </div>
                  ))}
                </div>
              )}

              {editingSection === 'use_cases' && Array.isArray(sectionDraft) && (
                <div className="max-h-[60vh] space-y-4 overflow-y-auto pr-1 custom-scrollbar">
                  {(sectionDraft as UseCase[]).map((useCase) => (
                    <div key={useCase.id} className="rounded-lg border border-[var(--border)] p-4">
                      <div className="flex items-start gap-3">
                        <div className="flex-1 space-y-3">
                          <input value={useCase.title} onChange={(event) => updateUseCaseDraft(useCase.id, 'title', event.target.value)} className="h-9 w-full rounded-lg border border-[var(--input-border)] bg-[var(--input)] px-3 text-sm text-[var(--foreground)]" placeholder={t('admin.playbooks.edit.use_case_title')} />
                          <textarea value={useCase.description} onChange={(event) => updateUseCaseDraft(useCase.id, 'description', event.target.value)} className="min-h-24 w-full rounded-lg border border-[var(--input-border)] bg-[var(--input)] px-3 py-2 text-sm text-[var(--foreground)]" placeholder={t('admin.playbooks.edit.description')} />
                        </div>
                        <button type="button" onClick={() => removeDraftItem(useCase.id)} className="text-[var(--error)] hover:text-red-400"><Trash2 className="h-4 w-4" /></button>
                      </div>
                    </div>
                  ))}
                </div>
              )}

              {editingSection === 'references' && Array.isArray(sectionDraft) && (
                <div className="max-h-[60vh] space-y-4 overflow-y-auto pr-1 custom-scrollbar">
                  {(sectionDraft as Reference[]).map((reference) => (
                    <div key={reference.id} className="rounded-lg border border-[var(--border)] p-4">
                      <div className="flex items-start gap-3">
                        <div className="flex-1 space-y-3">
                          <input value={reference.customer_name || reference.name || ''} onChange={(event) => updateReferenceDraft(reference.id, 'customer_name', event.target.value)} className="h-9 w-full rounded-lg border border-[var(--input-border)] bg-[var(--input)] px-3 text-sm text-[var(--foreground)]" placeholder={t('admin.playbooks.edit.customer_name')} />
                          <textarea value={reference.description} onChange={(event) => updateReferenceDraft(reference.id, 'description', event.target.value)} className="min-h-24 w-full rounded-lg border border-[var(--input-border)] bg-[var(--input)] px-3 py-2 text-sm text-[var(--foreground)]" placeholder={t('admin.playbooks.edit.description')} />
                        </div>
                        <button type="button" onClick={() => removeDraftItem(reference.id)} className="text-[var(--error)] hover:text-red-400"><Trash2 className="h-4 w-4" /></button>
                      </div>
                    </div>
                  ))}
                </div>
              )}

              {editingSection === 'proof_points' && Array.isArray(sectionDraft) && (
                <div className="max-h-[60vh] space-y-4 overflow-y-auto pr-1 custom-scrollbar">
                  {(sectionDraft as ProofPoint[]).map((proofPoint) => (
                    <div key={proofPoint.id} className="rounded-lg border border-[var(--border)] p-4">
                      <div className="flex items-start gap-3">
                        <div className="flex-1 space-y-3">
                          <input value={proofPoint.claim || proofPoint.title || ''} onChange={(event) => updateProofPointDraft(proofPoint.id, 'claim', event.target.value)} className="h-9 w-full rounded-lg border border-[var(--input-border)] bg-[var(--input)] px-3 text-sm text-[var(--foreground)]" placeholder={t('admin.playbooks.edit.claim')} />
                          <textarea value={proofPoint.description} onChange={(event) => updateProofPointDraft(proofPoint.id, 'description', event.target.value)} className="min-h-24 w-full rounded-lg border border-[var(--input-border)] bg-[var(--input)] px-3 py-2 text-sm text-[var(--foreground)]" placeholder={t('admin.playbooks.edit.description')} />
                        </div>
                        <button type="button" onClick={() => removeDraftItem(proofPoint.id)} className="text-[var(--error)] hover:text-red-400"><Trash2 className="h-4 w-4" /></button>
                      </div>
                    </div>
                  ))}
                </div>
              )}

              {editingSection !== 'product_description' && editingSection !== 'value_proposition' && (
                <button type="button" onClick={addDraftItem} className="mt-4 inline-flex h-9 items-center gap-2 rounded-lg border border-[var(--border)] px-3 text-sm text-[var(--foreground)] hover:bg-white/[0.05]">
                  <Plus className="h-4 w-4" />
                  {t('common.add')}
                </button>
              )}

              <div className="mt-6 flex justify-end gap-3">
                <button type="button" onClick={closeSectionEditor} disabled={savingSection} className="rounded-lg border border-[var(--border)] bg-[var(--card)] px-4 py-2 text-sm font-medium text-[var(--foreground)] hover:bg-[var(--card-hover)] disabled:opacity-50">
                  {t('common.cancel')}
                </button>
                <button type="button" onClick={saveSection} disabled={savingSection} className="rounded-lg bg-[var(--accent)] px-4 py-2 text-sm font-medium text-white hover:bg-[var(--accent-hover)] disabled:opacity-50">
                  {savingSection ? t('admin.common.saving') : t('admin.common.save_changes')}
                </button>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Approve Modal */}
      {showApproveModal && (
        <div className="fixed inset-0 z-50 overflow-y-auto custom-scrollbar">
          <div className="flex min-h-full items-center justify-center p-4">
            <button
              type="button"
              className="fixed inset-0 bg-black/60 transition-opacity"
              onClick={() => setShowApproveModal(false)}
              aria-label={t('playbooks.aria.close_approve_modal')}
            />
            <div className="relative bg-[var(--card)] border border-[var(--border)] rounded-xl shadow-xl max-w-lg w-full p-6">
              <div className="flex items-center justify-between mb-4">
                <h3 className="text-lg font-semibold text-[var(--foreground)]">
                  {t('playbooks.actions.approve_title')}
                </h3>
                <button type="button" onClick={() => setShowApproveModal(false)} className="text-[var(--foreground-subtle)] hover:text-[var(--foreground)] transition-colors">
                  <X className="h-5 w-5" />
                </button>
              </div>
              <p className="text-sm text-[var(--foreground-muted)] mb-4">
                {t('playbooks.actions.approve_description')}
              </p>
              <div className="mb-4">
                <label htmlFor="approve-comment" className="block text-sm font-medium text-[var(--foreground)] mb-1">
                  {t('playbooks.actions.approve_comment_label')}
                </label>
                <textarea
                  id="approve-comment"
                  rows={3}
                  value={approveComment}
                  onChange={(e) => setApproveComment(e.target.value)}
                  className="block w-full rounded-lg bg-[var(--input)] border border-[var(--input-border)] text-[var(--foreground)] px-4 py-2.5 focus:ring-2 focus:ring-[var(--success)] focus:border-transparent transition-colors custom-scrollbar-skinny"
                  placeholder={t('playbooks.actions.approve_comment_placeholder')}
                />
              </div>
              <div className="flex justify-end gap-3">
                <button
                  type="button"
                  onClick={() => setShowApproveModal(false)}
                  className="rounded-lg border border-[var(--border)] bg-[var(--card)] px-4 py-2 text-sm font-medium text-[var(--foreground)] hover:bg-[var(--card-hover)] transition-colors"
                >
                  {t('common.cancel')}
                </button>
                <button
                  type="button"
                  onClick={handleApprove}
                  disabled={isSubmitting}
                  className="inline-flex items-center gap-2 rounded-lg bg-[var(--success)] px-4 py-2 text-sm font-medium text-white hover:bg-green-600 disabled:opacity-50 transition-colors"
                >
                  <CheckCircle className="h-4 w-4" />
                  {isSubmitting ? t('playbooks.actions.approving') : t('playbooks.actions.approve_button')}
                </button>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Request Changes Modal */}
      {showRequestChangesModal && (
        <div className="fixed inset-0 z-50 overflow-y-auto custom-scrollbar">
          <div className="flex min-h-full items-center justify-center p-4">
            <button
              type="button"
              className="fixed inset-0 bg-black/60 transition-opacity"
              onClick={() => setShowRequestChangesModal(false)}
              aria-label={t('playbooks.aria.close_request_changes_modal')}
            />
            <div className="relative bg-[var(--card)] border border-[var(--border)] rounded-xl shadow-xl max-w-lg w-full p-6">
              <div className="flex items-center justify-between mb-4">
                <h3 className="text-lg font-semibold text-[var(--foreground)]">
                  {t('playbooks.actions.request_changes_title')}
                </h3>
                <button type="button" onClick={() => setShowRequestChangesModal(false)} className="text-[var(--foreground-subtle)] hover:text-[var(--foreground)] transition-colors">
                  <X className="h-5 w-5" />
                </button>
              </div>
              <p className="text-sm text-[var(--foreground-muted)] mb-4">
                {t('playbooks.actions.request_changes_description')}
              </p>
              <div className="mb-4">
                <label htmlFor="changes-comment" className="block text-sm font-medium text-[var(--foreground)] mb-1">
                  {t('playbooks.actions.request_changes_comment_label')} <span className="text-[var(--error)]">*</span>
                </label>
                <textarea
                  id="changes-comment"
                  rows={4}
                  value={changesComment}
                  onChange={(e) => setChangesComment(e.target.value)}
                  className="block w-full rounded-lg bg-[var(--input)] border border-[var(--input-border)] text-[var(--foreground)] px-4 py-2.5 focus:ring-2 focus:ring-[var(--warning)] focus:border-transparent transition-colors custom-scrollbar-skinny"
                  placeholder={t('playbooks.actions.request_changes_comment_placeholder')}
                  required
                />
              </div>
              <div className="flex justify-end gap-3">
                <button
                  type="button"
                  onClick={() => setShowRequestChangesModal(false)}
                  className="rounded-lg border border-[var(--border)] bg-[var(--card)] px-4 py-2 text-sm font-medium text-[var(--foreground)] hover:bg-[var(--card-hover)] transition-colors"
                >
                  {t('common.cancel')}
                </button>
                <button
                  type="button"
                  onClick={handleRequestChanges}
                  disabled={isSubmitting || !changesComment.trim()}
                  className="inline-flex items-center gap-2 rounded-lg bg-[var(--warning)] px-4 py-2 text-sm font-medium text-white hover:bg-yellow-600 disabled:opacity-50 transition-colors"
                >
                  <AlertCircle className="h-4 w-4" />
                  {isSubmitting ? t('playbooks.actions.requesting') : t('playbooks.actions.request_changes_button')}
                </button>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Archive Modal */}
      {showArchiveModal && (
        <div className="fixed inset-0 z-50 overflow-y-auto custom-scrollbar">
          <div className="flex min-h-full items-center justify-center p-4">
            <button
              type="button"
              className="fixed inset-0 bg-black/60 transition-opacity"
              onClick={() => setShowArchiveModal(false)}
              aria-label={t('playbooks.aria.close_archive_modal')}
            />
            <div className="relative bg-[var(--card)] border border-[var(--border)] rounded-xl shadow-xl max-w-lg w-full p-6">
              <div className="flex items-center justify-between mb-4">
                <h3 className="text-lg font-semibold text-[var(--foreground)]">
                  {t('playbooks.actions.archive_title')}
                </h3>
                <button type="button" onClick={() => setShowArchiveModal(false)} className="text-[var(--foreground-subtle)] hover:text-[var(--foreground)] transition-colors">
                  <X className="h-5 w-5" />
                </button>
              </div>
              <p className="text-sm text-[var(--foreground-muted)] mb-4">
                {t('playbooks.actions.archive_description')}
              </p>
              <p className="text-sm text-[var(--foreground)] mb-4">
                {t('playbooks.actions.archive_confirm')}
              </p>
              <div className="flex justify-end gap-3">
                <button
                  type="button"
                  onClick={() => setShowArchiveModal(false)}
                  className="rounded-lg border border-[var(--border)] bg-[var(--card)] px-4 py-2 text-sm font-medium text-[var(--foreground)] hover:bg-[var(--card-hover)] transition-colors"
                >
                  {t('common.cancel')}
                </button>
                <button
                  type="button"
                  onClick={handleArchive}
                  disabled={isSubmitting}
                  className="inline-flex items-center gap-2 rounded-lg bg-[var(--error)] px-4 py-2 text-sm font-medium text-white hover:bg-red-600 disabled:opacity-50 transition-colors"
                >
                  <Archive className="h-4 w-4" />
                  {isSubmitting ? t('playbooks.actions.archiving') : t('playbooks.actions.archive_button')}
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </PlaybookLayout>
  )
}
