import { Link, router, usePage } from '@inertiajs/react'
import { ReactNode, useEffect, useRef, useState } from 'react'
import {
  ArrowLeft,
  CheckCircle,
  AlertCircle,
  Archive,
  Database,
  MessageSquare,
  Upload,
  FolderOpen,
  PenLine,
  X,
  Sparkles,
  Users,
  Layers3,
  Library,
  ShieldCheck
} from 'lucide-react'
import AuthenticatedLayout from './AuthenticatedLayout'
import { Badge } from '../components/ui/Badge'
import { ExpandableText } from '../components/ui/ExpandableText'
import { t } from '../lib/i18n'
import type { PlaybookFeedbackContext } from '../lib/playbookFeedbackContext'

export const GRADIENT_COLORS = ['orange', 'green', 'blue', 'purple'] as const

export function getPlaybookGradient(playbookId: number) {
  return GRADIENT_COLORS[playbookId % GRADIENT_COLORS.length]
}

export function getStatusBadgeVariant(status: string) {
  switch (status) {
    case 'draft':
      return 'draft' as const
    case 'changes_requested':
      return 'warning' as const
    case 'approved':
      return 'approved' as const
    case 'archived':
      return 'error' as const
    default:
      return 'default' as const
  }
}

interface ApprovedBy {
  id: number
  first_name: string
  last_name: string
  full_name: string
}

interface Playbook {
  id: number
  product: {
    name: string
    description: string
  }
  status: string
  approved_at: string | null
  approved_by: ApprovedBy | null
  personae?: unknown[]
  use_cases?: unknown[]
  references?: unknown[]
  proof_points?: unknown[]
  'knowledge_base_available?'?: boolean
}

interface Account {
  id: number
  email: string
  first_name: string
  last_name: string
  full_name: string
  role: string
  'amplifa_admin?'?: boolean
  'customer_admin?'?: boolean
  'customer_user?'?: boolean
}

interface Organization {
  id: number
  name: string
}

interface Flash {
  notice?: string
  alert?: string
}

interface PlaybookLayoutProps {
  playbook: Playbook
  currentTab: 'training_data' | 'samples' | 'import_leads' | 'knowledge_base'
  children: ReactNode
  canApprove?: boolean
  canRequestChanges?: boolean
  canArchive?: boolean
  flash?: Flash
  fullBleed?: boolean
  feedbackContext?: Partial<PlaybookFeedbackContext>
  canEditProductDescription?: boolean
  onApprove?: () => void
  onRequestChanges?: () => void
  onArchive?: () => void
  onEditProductDescription?: () => void
}

export default function PlaybookLayout({
  playbook,
  currentTab,
  children,
  canApprove,
  canRequestChanges,
  canArchive,
  flash,
  fullBleed,
  feedbackContext,
  canEditProductDescription,
  onApprove,
  onRequestChanges,
  onArchive,
  onEditProductDescription
}: PlaybookLayoutProps) {
  const { auth } = usePage<{
    auth: { account: Account; organization?: Organization }
    [key: string]: unknown
  }>().props

  const { account, organization } = auth

  const gradient = getPlaybookGradient(playbook.id)
  const gradientImage = `/card-gradient-${gradient}.jpg?v2`
  const knowledgeStats = [
    { label: t('playbooks.sections.personae'), value: playbook.personae?.length, icon: Users, tone: 'text-cyan-300', hideWhenEmpty: false },
    { label: t('playbooks.sections.use_cases'), value: playbook.use_cases?.length, icon: Layers3, tone: 'text-blue-300', hideWhenEmpty: false },
    { label: t('playbooks.sections.references'), value: playbook.references?.length, icon: Library, tone: 'text-purple-300', hideWhenEmpty: true },
    { label: t('playbooks.sections.proof_points'), value: playbook.proof_points?.length, icon: ShieldCheck, tone: 'text-pink-300', hideWhenEmpty: true },
  ].filter((stat): stat is typeof stat & { value: number } => (
    typeof stat.value === 'number' && (!stat.hideWhenEmpty || stat.value > 0)
  ))

  const showsApprovalStrip = playbook.status === 'draft' || playbook.status === 'changes_requested'

  // Approval strip state (for draft playbooks)
  const [showFeedbackModal, setShowFeedbackModal] = useState(false)
  const [feedbackComment, setFeedbackComment] = useState('')
  const [isSubmittingFeedback, setIsSubmittingFeedback] = useState(false)
  const [isApproving, setIsApproving] = useState(false)
  const feedbackTextareaRef = useRef<HTMLTextAreaElement | null>(null)

  useEffect(() => {
    if (!showFeedbackModal) return

    feedbackTextareaRef.current?.focus()
  }, [showFeedbackModal])

  const handleDirectApprove = () => {
    setIsApproving(true)
    router.post(`/playbooks/${playbook.id}/approve`, { return_to: currentTab }, {
      onFinish: () => setIsApproving(false)
    })
  }

  const handleSubmitFeedback = () => {
    if (!feedbackComment.trim()) return
    setIsSubmittingFeedback(true)
    router.post(`/playbooks/${playbook.id}/request_changes`, {
      comment: feedbackComment,
      return_to: currentTab,
      feedback_context: {
        ...feedbackContext,
        tab: currentTab
      }
    }, {
      onFinish: () => {
        setIsSubmittingFeedback(false)
        setShowFeedbackModal(false)
        setFeedbackComment('')
      }
    })
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

  const TABS = [
    { id: 'training_data', label: t('playbooks.tabs.training_data'), href: `/playbooks/${playbook.id}`, icon: Database },
    { id: 'samples', label: t('playbooks.tabs.sample_leads_messages'), href: `/playbooks/${playbook.id}/samples`, icon: MessageSquare },
    ...(playbook['knowledge_base_available?'] ? [
      { id: 'knowledge_base', label: t('playbooks.tabs.knowledge_base'), href: `/playbooks/${playbook.id}/knowledge-base`, icon: FolderOpen },
    ] : []),
    { id: 'import_leads', label: t('playbooks.tabs.import_leads'), href: `/playbooks/${playbook.id}/import_leads`, icon: Upload },
  ]

  const tabs = (
    <nav className="relative z-[1] flex items-end gap-3 -mb-px overflow-x-auto [&::-webkit-scrollbar]:hidden [scrollbar-width:none] -mx-4 lg:-ml-3 lg:mr-0 px-4 lg:px-0">
      <Link
        href="/playbooks"
        className="mb-1 inline-flex h-9 items-center gap-1.5 rounded-full border border-transparent px-3.5 text-sm text-[var(--foreground-muted)] hover:border-white/[0.12] hover:bg-white/[0.04] hover:text-[var(--foreground)] transition-colors whitespace-nowrap"
      >
        <ArrowLeft className="w-3.5 h-3.5" />
        {t('playbooks.back_to_list')}
      </Link>
      <span className="mb-3 h-5 w-px bg-white/[0.08] select-none" aria-hidden="true" />
      <div className="flex items-end gap-1">
        {TABS.map((tab) => {
          const isActive = currentTab === tab.id
          const Icon = tab.icon

          return (
            <Link
              key={tab.id}
              href={tab.href}
              className={`
                relative inline-flex h-11 items-center gap-2 rounded-t-2xl border border-transparent px-4 text-sm font-medium whitespace-nowrap transition-colors duration-200 select-none
                ${isActive
                  ? 'border-white/[0.12] border-b-transparent bg-[var(--background)] text-[var(--foreground)] shadow-[0_-10px_28px_rgba(0,0,0,0.18)] after:absolute after:inset-x-0 after:-bottom-px after:h-px after:bg-[var(--background)] after:content-[""]'
                  : 'text-[var(--foreground-muted)] hover:border-white/[0.10] hover:border-b-transparent hover:bg-white/[0.03] hover:text-[var(--foreground)]'
                }
              `}
            >
              <Icon className="w-4 h-4 shrink-0" />
              <span>{tab.label}</span>
            </Link>
          )
        })}
      </div>
    </nav>
  )

  const mainContentClassName = (() => {
    if (!fullBleed) return ''
    if (currentTab === 'samples') return 'flex-1 flex flex-col min-h-0 overflow-hidden'

    const baseClassName = currentTab === 'knowledge_base'
      ? 'flex-1 overflow-y-auto custom-scrollbar'
      : 'flex-1 p-6 overflow-y-auto custom-scrollbar'

    return currentTab === 'knowledge_base' && showsApprovalStrip ? `${baseClassName} pb-24` : baseClassName
  })()

  const authenticatedMainClassName = [
    !fullBleed ? 'custom-scrollbar' : '',
    showsApprovalStrip && !fullBleed ? 'pb-32' : '',
  ].filter(Boolean).join(' ')

  return (
    <AuthenticatedLayout
      title={playbook.product.name}
      account={account}
      organization={organization}
      flash={flash}
      fullBleed={fullBleed}
      mainClassName={authenticatedMainClassName}
      stickyNavigation={tabs}
    >
      <div className={mainContentClassName}>
        {currentTab === 'training_data' && (
        <div className="relative mb-8 overflow-hidden rounded-[28px] border border-white/[0.08] bg-[#11161c] shadow-[0_28px_80px_rgba(0,0,0,0.32)]">
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
                <div className="mb-4 flex max-w-4xl items-center justify-between gap-3">
                  <div className="inline-flex items-center gap-2 rounded-full border border-[var(--accent)]/25 bg-[var(--accent)]/10 px-3.5 py-1.5 text-sm font-medium text-[var(--accent)] shadow-[0_0_32px_rgba(53,202,222,0.08)]">
                    <Sparkles className="h-4 w-4" />
                    {t('playbooks.knowledge_ui.hero_badge')}
                  </div>
                  {canEditProductDescription && onEditProductDescription && (
                    <button
                      type="button"
                      onClick={onEditProductDescription}
                      className="inline-flex h-9 shrink-0 items-center gap-2 rounded-full border border-white/[0.12] bg-white/[0.05] px-3 text-sm font-medium text-[var(--foreground)] transition-colors hover:bg-white/[0.09]"
                    >
                      <PenLine className="h-4 w-4" />
                      {t('admin.common.edit')}
                    </button>
                  )}
                </div>
                <div className="max-w-4xl">
                  <h2 className="text-4xl font-semibold leading-[0.96] tracking-[-0.055em] text-white md:text-5xl">
                    {playbook.product.name}
                  </h2>
                </div>
                {playbook.product.description && (
                  <div className="mt-4 max-w-4xl">
                    <ExpandableText
                      text={playbook.product.description}
                      collapsedLines={10}
                      className="text-base leading-7 text-white/64 md:text-lg"
                      buttonClassName="border-[var(--accent)]/25 bg-[var(--accent)]/10 text-[var(--accent)] hover:bg-[var(--accent)]/15"
                      seeMoreLabel={t('playbooks.knowledge_ui.see_more')}
                      seeLessLabel={t('playbooks.knowledge_ui.see_less')}
                    />
                  </div>
                )}
                <div className="mt-5 flex flex-wrap items-center gap-3">
                  <Badge variant={getStatusBadgeVariant(playbook.status)}>
                    {t(`playbooks.statuses.${playbook.status}`)}
                  </Badge>
                  {playbook.approved_at && playbook.approved_by && (
                    <span className="text-sm text-white/60">
                      {t('playbooks.show.approved_by')} {playbook.approved_by.full_name} {t('playbooks.show.on_date')} {formatDate(playbook.approved_at)}
                    </span>
                  )}
                </div>
              </div>

              {!showsApprovalStrip && (
                <div className="flex flex-wrap gap-3 xl:justify-end">
                  {canApprove && (
                    <button
                      type="button"
                      onClick={onApprove}
                      className="inline-flex items-center gap-2 rounded-2xl bg-[var(--success)] px-5 py-3 text-sm font-semibold text-white shadow-[0_14px_35px_rgba(34,197,94,0.2)] hover:bg-green-600 focus:outline-none focus:ring-2 focus:ring-[var(--success)] focus:ring-offset-2 focus:ring-offset-transparent transition-colors"
                    >
                      <CheckCircle className="h-4 w-4" />
                      {t('playbooks.show.approve')}
                    </button>
                  )}
                  {canRequestChanges && (
                    <button
                      type="button"
                      onClick={onRequestChanges}
                      className="inline-flex items-center gap-2 rounded-2xl border border-[var(--warning)]/50 bg-white/10 px-5 py-3 text-sm font-semibold text-[var(--warning)] shadow-sm backdrop-blur-sm hover:bg-white/20 focus:outline-none focus:ring-2 focus:ring-[var(--warning)] focus:ring-offset-2 focus:ring-offset-transparent transition-colors"
                    >
                      <AlertCircle className="h-4 w-4" />
                      {t('playbooks.show.request_changes')}
                    </button>
                  )}
                  {canArchive && (
                    <button
                      type="button"
                      onClick={onArchive}
                      className="inline-flex items-center gap-2 rounded-2xl border border-white/20 bg-white/10 px-5 py-3 text-sm font-semibold text-white shadow-sm backdrop-blur-sm hover:bg-white/20 focus:outline-none focus:ring-2 focus:ring-white/50 focus:ring-offset-2 focus:ring-offset-transparent transition-colors"
                    >
                      <Archive className="h-4 w-4" />
                      {t('playbooks.show.archive')}
                    </button>
                  )}
                </div>
              )}
            </div>
            {knowledgeStats.length > 0 && (
              <div className="mt-6 grid grid-cols-2 gap-3 md:grid-cols-4 lg:gap-4">
                {knowledgeStats.map((stat) => {
                  const Icon = stat.icon

                  return (
                    <div key={stat.label} className="min-w-0 rounded-2xl border border-white/[0.09] bg-black/18 px-4 py-3.5 backdrop-blur-sm shadow-[inset_0_1px_0_rgba(255,255,255,0.045)] lg:px-5">
                      <div className="flex items-start justify-between gap-3">
                        <div className="min-w-0">
                          <p className="truncate text-xs text-white/55 lg:text-sm">{stat.label}</p>
                          <p className="mt-1.5 text-3xl font-semibold tracking-[-0.04em] text-white">{stat.value}</p>
                        </div>
                        <Icon className={`h-5 w-5 ${stat.tone}`} />
                      </div>
                    </div>
                  )
                })}
              </div>
            )}
          </div>
        </div>
        )}
        {/* Main Content */}
        {children}
        {/* Spacer for approval strip */}
        {showsApprovalStrip && !fullBleed && <div className="h-32" />}
      </div>

      {/* Approval Strip - fixed at bottom for draft and changes_requested playbooks */}
      {showsApprovalStrip && (
        <div className="fixed bottom-0 left-0 lg:left-20 right-3 z-40 border-t border-white/10 bg-[rgba(16,16,18,0.95)] backdrop-blur-md">
          <div className="flex items-center justify-between px-6 py-4">
            {/* Share Feedback (secondary) */}
            <button
              type="button"
              onClick={() => setShowFeedbackModal(true)}
              className="inline-flex items-center gap-2 rounded-lg border border-white/20 bg-white/5 px-5 py-2.5 text-sm font-medium text-white hover:bg-white/10 transition-colors"
            >
              <PenLine className="h-4 w-4" />
              {t('playbooks.approval_strip.share_feedback')}
            </button>

            {/* Center message */}
            <p className="text-sm text-[var(--foreground-muted)] hidden md:block">
              {t('playbooks.approval_strip.message')}
            </p>

            {/* Approve (primary CTA) */}
            <button
              type="button"
              onClick={handleDirectApprove}
              disabled={isApproving}
              className="inline-flex items-center gap-2 rounded-lg bg-[var(--accent)] px-6 py-2.5 text-sm font-semibold text-white shadow-sm hover:brightness-110 disabled:opacity-50 transition-all"
            >
              {isApproving ? t('playbooks.actions.approving') : t('playbooks.actions.approve_button')}
            </button>
          </div>
        </div>
      )}

      {/* Feedback Modal */}
      {showFeedbackModal && (
        <div className="fixed inset-0 z-50 overflow-y-auto">
          <div className="flex min-h-full items-center justify-center p-4">
            <button
              type="button"
              className="fixed inset-0 bg-black/60 transition-opacity"
              onClick={() => setShowFeedbackModal(false)}
              aria-label={t('playbooks.aria.close_feedback_modal')}
            />
            <div className="relative bg-[var(--card)] border border-[var(--border)] rounded-xl shadow-xl max-w-lg w-full p-6">
              <div className="flex items-center justify-between mb-4">
                <h3 className="text-lg font-semibold text-[var(--foreground)]">
                  {t('playbooks.actions.request_changes_title')}
                </h3>
                <button type="button" onClick={() => setShowFeedbackModal(false)} className="text-[var(--foreground-subtle)] hover:text-[var(--foreground)] transition-colors">
                  <X className="h-5 w-5" />
                </button>
              </div>
              <p className="text-sm text-[var(--foreground-muted)] mb-4">
                {t('playbooks.actions.request_changes_description')}
              </p>
              <div className="mb-4">
                <label htmlFor="feedback-comment" className="block text-sm font-medium text-[var(--foreground)] mb-1">
                  {t('playbooks.actions.request_changes_comment_label')} <span className="text-[var(--error)]">*</span>
                </label>
                <textarea
                  id="feedback-comment"
                  ref={feedbackTextareaRef}
                  rows={4}
                  value={feedbackComment}
                  onChange={(e) => setFeedbackComment(e.target.value)}
                  className="block w-full rounded-lg bg-[var(--input)] border border-[var(--input-border)] text-[var(--foreground)] px-4 py-2.5 focus:ring-2 focus:ring-[var(--warning)] focus:border-transparent transition-colors"
                  placeholder={t('playbooks.actions.request_changes_comment_placeholder')}
                  required
                />
              </div>
              <div className="flex justify-end gap-3">
                <button
                  type="button"
                  onClick={() => setShowFeedbackModal(false)}
                  className="rounded-lg border border-[var(--border)] bg-[var(--card)] px-4 py-2 text-sm font-medium text-[var(--foreground)] hover:bg-[var(--card-hover)] transition-colors"
                >
                  {t('common.cancel')}
                </button>
                <button
                  type="button"
                  onClick={handleSubmitFeedback}
                  disabled={isSubmittingFeedback || !feedbackComment.trim()}
                  className="inline-flex items-center gap-2 rounded-lg bg-[var(--warning)] px-4 py-2 text-sm font-medium text-white hover:bg-yellow-600 disabled:opacity-50 transition-colors"
                >
                  <AlertCircle className="h-4 w-4" />
                  {isSubmittingFeedback ? t('playbooks.actions.requesting') : t('playbooks.actions.request_changes_button')}
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </AuthenticatedLayout>
  )
}
