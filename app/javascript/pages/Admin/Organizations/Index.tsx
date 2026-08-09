/**
 * Admin Organizations Index Page
 * Lists all organizations in a card grid with pagination
 *
 * Design: Dark theme with OrganizationCard components in responsive grid
 * Migration: Task 5.3.4 (Phase 5) - Updated to card grid
 */
import { Link, router } from '@inertiajs/react'
import { useState, useRef, useEffect } from 'react'
import AuthenticatedLayout from '../../../layouts/AuthenticatedLayout'
import OrganizationCard from '../../../components/Admin/OrganizationCard'
import { t } from '../../../lib/i18n'
import { Button } from '../../../components/ui/Button'
import { Plus, Upload, X, AlertTriangle, FileJson, Search } from 'lucide-react'

interface Organization {
  id: number
  name: string
  industry: string | null
  size: string | null
  onboarded: boolean
  deactivated_at: string | null
  created_at: string
  agents_count: number
  playbooks_count: number
  senders_count: number
  mailboxes_count: number
  card_sending_stats: {
    daily_sending_capacity: number
    messages_sent_today: number
    messages_sent_previous_sending_day: number
  }
  ai_reply_agent_enabled: boolean
}

interface Pagination {
  current_page: number
  total_pages: number
  total_count: number
}

interface Filters {
  search?: string
  status?: 'archived' | 'deactivated'
}

interface AdminOrganizationsIndexProps {
  auth: {
    account: {
      id: number
      email: string
      first_name: string
      last_name: string
      full_name: string
      role: string
    }
  }
  organizations: Organization[]
  pagination: Pagination
  filters: Filters
  flash?: {
    notice?: string
    alert?: string
  }
}

export default function Index({ auth, organizations, pagination, filters, flash }: AdminOrganizationsIndexProps) {
  const account = auth.account
  
  const [showImportDialog, setShowImportDialog] = useState(false)
  const [importFile, setImportFile] = useState<File | null>(null)
  const [importing, setImporting] = useState(false)
  const [importError, setImportError] = useState<string | null>(null)
  const [searchInput, setSearchInput] = useState(filters.search || '')
  const fileInputRef = useRef<HTMLInputElement>(null)
  const searchDebounceTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const lastSubmittedSearchRef = useRef(filters.search || '')

  useEffect(() => {
    lastSubmittedSearchRef.current = filters.search || ''
  }, [filters.search])

  useEffect(() => {
    if (searchDebounceTimeoutRef.current) {
      clearTimeout(searchDebounceTimeoutRef.current)
    }

    if (searchInput === lastSubmittedSearchRef.current) {
      return
    }

    searchDebounceTimeoutRef.current = setTimeout(() => {
      lastSubmittedSearchRef.current = searchInput

      router.get('/admin/organizations', {
        search: searchInput || undefined,
        page: 1,
        status: filters.status || undefined
      }, { preserveState: true, replace: true })
    }, 300)

    return () => {
      if (searchDebounceTimeoutRef.current) {
        clearTimeout(searchDebounceTimeoutRef.current)
      }
    }
  }, [searchInput, filters.status])

  const handleOpenImportDialog = () => {
    setShowImportDialog(true)
    setImportFile(null)
    setImportError(null)
  }

  const handleCloseImportDialog = () => {
    if (importing) return
    setShowImportDialog(false)
    setImportFile(null)
    setImportError(null)
  }

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (file) {
      if (!file.name.endsWith('.json')) {
        setImportError(t('admin.organizations.import.invalid_file_type'))
        return
      }
      setImportFile(file)
      setImportError(null)
    }
  }

  const handleImportSubmit = () => {
    if (!importFile) return

    setImporting(true)
    setImportError(null)

    const formData = new FormData()
    formData.append('file', importFile)

    router.post('/admin/organizations/import', formData, {
      forceFormData: true,
      onSuccess: () => {
        setShowImportDialog(false)
        setImportFile(null)
      },
      onError: (errors) => {
        setImportError(errors.file || errors.base || t('admin.organizations.import.error'))
      },
      onFinish: () => {
        setImporting(false)
      }
    })
  }

  const handleClearSearch = () => {
    setSearchInput('')
  }

  const handlePageChange = (page: number) => {
    router.get('/admin/organizations', {
      page,
      search: filters.search || undefined,
      status: filters.status || undefined
    }, { preserveState: true })
  }

  return (
    <AuthenticatedLayout
      title={t('admin.organizations.title')}
      account={account}
      flash={flash}
      headerActions={
        <div className="flex flex-wrap items-center gap-3">
          <div className="flex flex-col gap-1">
            <div className="relative">
              <Search className="absolute left-2 top-1/2 -translate-y-1/2 w-3.5 h-3.5 text-[var(--foreground-muted)]" />
              <input
                type="text"
                value={searchInput}
                onChange={(e) => setSearchInput(e.target.value)}
                placeholder={t('admin.organizations.search_placeholder')}
                className="h-9 w-72 pl-7 pr-7 text-sm rounded-lg border border-[var(--border)] bg-[var(--card)] text-[var(--foreground)] placeholder-[var(--foreground-muted)] focus:outline-none focus:ring-2 focus:ring-[var(--primary)] focus:border-transparent"
              />
              {searchInput && (
                <button
                  type="button"
                  onClick={handleClearSearch}
                  className="absolute right-2 top-1/2 -translate-y-1/2 text-[var(--foreground-muted)] hover:text-[var(--foreground)]"
                >
                  <X className="w-3.5 h-3.5" />
                </button>
              )}
            </div>

            <div className="flex items-center gap-2 text-xs text-[var(--foreground-muted)]">
              <Link
                href="/admin/organizations"
                data={{
                  search: filters.search || undefined,
                  page: 1,
                  status: undefined
                }}
                preserveState
                replace
                className={filters.status ? 'hover:text-[var(--foreground)] underline underline-offset-2' : 'text-[var(--foreground)]'}
              >
                all
              </Link>
              <span>·</span>
              <Link
                href="/admin/organizations"
                data={{
                  search: filters.search || undefined,
                  page: 1,
                  status: 'archived'
                }}
                preserveState
                replace
                className={filters.status === 'archived' ? 'text-[var(--foreground)]' : 'hover:text-[var(--foreground)] underline underline-offset-2'}
              >
                archived
              </Link>
              <span>·</span>
              <Link
                href="/admin/organizations"
                data={{
                  search: filters.search || undefined,
                  page: 1,
                  status: 'deactivated'
                }}
                preserveState
                replace
                className={filters.status === 'deactivated' ? 'text-[var(--foreground)]' : 'hover:text-[var(--foreground)] underline underline-offset-2'}
              >
                deactivated
              </Link>
            </div>
          </div>

          <Button
            type="button"
            variant="secondary"
            onClick={handleOpenImportDialog}
            icon={<Upload className="h-4 w-4" />}
          >
            {t('admin.organizations.import.button')}
          </Button>
          <Link
            href="/admin/organizations/new"
            className="inline-flex items-center justify-center h-9 px-4 gap-2 text-sm font-medium rounded-lg bg-[var(--primary)] text-[var(--primary-foreground)] hover:bg-[var(--primary-hover)] transition-colors"
          >
            <Plus className="h-4 w-4" />
            {t('admin.organizations.create_button')}
          </Link>
        </div>
      }
    >
      {/* Organizations Card Grid */}
      {organizations.length === 0 ? (
        <div className="text-center py-12">
          <p className="text-[var(--foreground-muted)]">
            {t('admin.organizations.empty')}
          </p>
        </div>
      ) : (
        <>
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-5">
            {organizations.map((org) => (
              <OrganizationCard key={org.id} organization={org} />
            ))}
          </div>

          {/* Pagination */}
          {pagination.total_pages > 1 && (
            <div className="mt-8 flex justify-center items-center gap-2">
              <button
                type="button"
                onClick={() => handlePageChange(pagination.current_page - 1)}
                disabled={pagination.current_page === 1}
                className="px-4 py-2 text-sm font-medium rounded-lg bg-[var(--card)] border border-[var(--border)] text-[var(--foreground)] disabled:opacity-50 disabled:cursor-not-allowed hover:bg-[var(--card-hover)] transition-colors"
              >
                {t('admin.common.previous')}
              </button>
              <span className="px-4 py-2 text-sm text-[var(--foreground-muted)]">
                {t('admin.common.page')} {pagination.current_page} {t('admin.common.of')} {pagination.total_pages}
              </span>
              <button
                type="button"
                onClick={() => handlePageChange(pagination.current_page + 1)}
                disabled={pagination.current_page === pagination.total_pages}
                className="px-4 py-2 text-sm font-medium rounded-lg bg-[var(--card)] border border-[var(--border)] text-[var(--foreground)] disabled:opacity-50 disabled:cursor-not-allowed hover:bg-[var(--card-hover)] transition-colors"
              >
                {t('admin.common.next')}
              </button>
            </div>
          )}
        </>
      )}

      {/* Import Dialog */}
      {showImportDialog && (
        <div className="fixed inset-0 z-50 overflow-y-auto">
          <div className="flex min-h-screen items-center justify-center p-4">
            <button
              type="button"
              aria-label={t('admin.common.close')}
              className="fixed inset-0 bg-black/60 backdrop-blur-sm transition-opacity"
              onClick={handleCloseImportDialog}
            />

            <div className="relative bg-[var(--card)] rounded-xl shadow-2xl max-w-md w-full p-6 border border-[var(--border)]">
              <div className="flex items-start justify-between mb-4">
                <div>
                  <h3 className="text-xl font-semibold text-[var(--foreground)]">
                    {t('admin.organizations.import.title')}
                  </h3>
                  <p className="mt-1 text-sm text-[var(--foreground-muted)]">
                    {t('admin.organizations.import.description')}
                  </p>
                </div>
                {!importing && (
                  <button
                    type="button"
                    onClick={handleCloseImportDialog}
                    className="text-[var(--foreground-muted)] hover:text-[var(--foreground)] transition-colors"
                  >
                    <X className="h-6 w-6" />
                  </button>
                )}
              </div>

              {importError && (
                <div className="mb-4 p-4 bg-[var(--error)]/10 border border-[var(--error)]/20 rounded-lg">
                  <div className="flex gap-3">
                    <AlertTriangle className="h-5 w-5 text-[var(--error)] shrink-0" />
                    <p className="text-sm text-[var(--error)]">{importError}</p>
                  </div>
                </div>
              )}

              <div className="mb-6">
                <input
                  ref={fileInputRef}
                  type="file"
                  accept=".json"
                  onChange={handleFileChange}
                  className="hidden"
                  id="import-file-input"
                />
                <label
                  htmlFor="import-file-input"
                  className="flex flex-col items-center justify-center p-8 border-2 border-dashed border-[var(--border)] rounded-lg cursor-pointer hover:border-[var(--accent)] transition-colors"
                >
                  {importFile ? (
                    <>
                      <FileJson className="h-12 w-12 text-[var(--accent)] mb-3" />
                      <span className="text-sm font-medium text-[var(--foreground)]">{importFile.name}</span>
                      <span className="text-xs text-[var(--foreground-muted)] mt-1">
                        {t('admin.organizations.import.click_to_change')}
                      </span>
                    </>
                  ) : (
                    <>
                      <Upload className="h-12 w-12 text-[var(--foreground-muted)] mb-3" />
                      <span className="text-sm font-medium text-[var(--foreground)]">
                        {t('admin.organizations.import.select_file')}
                      </span>
                      <span className="text-xs text-[var(--foreground-muted)] mt-1">
                        {t('admin.organizations.import.file_hint')}
                      </span>
                    </>
                  )}
                </label>
              </div>

              <div className="flex justify-end gap-3">
                <Button
                  type="button"
                  variant="secondary"
                  onClick={handleCloseImportDialog}
                  disabled={importing}
                >
                  {t('admin.common.cancel')}
                </Button>
                <Button
                  type="button"
                  onClick={handleImportSubmit}
                  disabled={!importFile}
                  loading={importing}
                >
                  {importing ? t('admin.organizations.import.importing') : t('admin.organizations.import.submit')}
                </Button>
              </div>
            </div>
          </div>
        </div>
      )}
    </AuthenticatedLayout>
  )
}
