import { useRef, useState } from 'react'
import { router } from '@inertiajs/react'
import { Mail, Globe, Upload, Download, Plus, Trash2, XCircle, Search, ChevronLeft, ChevronRight } from 'lucide-react'
import SettingsLayout from '../../../../layouts/SettingsLayout'
import { Card, CardHeader, CardContent } from '../../../../components/ui/Card'
import { Button } from '../../../../components/ui/Button'
import { Textarea } from '../../../../components/ui/Textarea'
import { Badge } from '../../../../components/ui/Badge'
import { Table, TableHeader, TableBody, TableRow, TableHead, TableCell } from '../../../../components/ui/Table'
import { t } from '../../../../lib/i18n'

interface BlacklistEntry {
  id: number
  value: string
  value_type: 'email' | 'domain'
  source: string
  reason: string | null
  is_global: boolean
  can_delete: boolean
  created_at: string
  created_by: string | null
}

interface PaginationDetails {
  current_page: number
  total_pages: number
  total_count: number
  per_page: number
}

interface Pagination {
  emails: PaginationDetails
  domains: PaginationDetails
}

interface Filters {
  email_search: string
  domain_search: string
}

interface Props {
  email_blacklists: BlacklistEntry[]
  domain_blacklists: BlacklistEntry[]
  pagination: Pagination
  totals: {
    emails: number
    domains: number
  }
  filters: Filters
  canManage: boolean
  canAdd: boolean
  canRemove: boolean
  value_types: string[]
  errors?: string[]
  form_values?: {
    value: string
    value_type: string
  }
}

export default function Index({
  email_blacklists,
  domain_blacklists,
  pagination,
  totals,
  filters,
  canAdd,
  canRemove
}: Props) {
  const [emailSearch, setEmailSearch] = useState(filters.email_search || '')
  const [domainSearch, setDomainSearch] = useState(filters.domain_search || '')
  
  const [showAddEmail, setShowAddEmail] = useState(false)
  const [showAddDomain, setShowAddDomain] = useState(false)
  const [isImportingFile, setIsImportingFile] = useState(false)
  const [importError, setImportError] = useState<string | null>(null)
  const importFileInputRef = useRef<HTMLInputElement>(null)

  const [deletingId, setDeletingId] = useState<number | null>(null)

  const emailFilterActive = filters.email_search.trim().length > 0
  const domainFilterActive = filters.domain_search.trim().length > 0
  const emailSubtitle = emailFilterActive
    ? `${pagination.emails.total_count} of ${totals.emails} emails match`
    : `${totals.emails} emails blocked`
  const domainSubtitle = domainFilterActive
    ? `${pagination.domains.total_count} of ${totals.domains} domains match`
    : `${totals.domains} domains blocked`

  const navigate = (params: Record<string, string>) => {
    router.get('/settings/blacklists', params, {
      preserveState: true,
      preserveScroll: true
    })
  }

  const buildParams = (overrides: Partial<Record<'email_search' | 'domain_search' | 'email_page' | 'domain_page', string>> = {}) => {
    const params: Record<string, string> = {}

    const nextEmailSearch = overrides.email_search ?? filters.email_search
    const nextDomainSearch = overrides.domain_search ?? filters.domain_search
    const nextEmailPage = overrides.email_page ?? pagination.emails.current_page.toString()
    const nextDomainPage = overrides.domain_page ?? pagination.domains.current_page.toString()

    if (nextEmailSearch.trim()) params.email_search = nextEmailSearch.trim()
    if (nextDomainSearch.trim()) params.domain_search = nextDomainSearch.trim()
    if (nextEmailPage !== '1') params.email_page = nextEmailPage
    if (nextDomainPage !== '1') params.domain_page = nextDomainPage

    return params
  }

  const applyEmailSearch = () => {
    navigate(buildParams({ email_search: emailSearch, email_page: '1' }))
  }

  const applyDomainSearch = () => {
    navigate(buildParams({ domain_search: domainSearch, domain_page: '1' }))
  }

  const goToEmailPage = (page: number) => {
    navigate(buildParams({ email_page: page.toString() }))
  }

  const goToDomainPage = (page: number) => {
    navigate(buildParams({ domain_page: page.toString() }))
  }

  const handleCsvImport = async (file: File | null) => {
    if (!file) return

    setImportError(null)
    setIsImportingFile(true)

    try {
      const text = await file.text()
      const entries = parseImportInput(text)

      if (entries.length === 0) {
        setImportError(t('customer_settings.blacklists.import.empty_file_error'))
        return
      }

      router.post('/settings/blacklists/import', {
        input: entries.join('\n')
      }, {
        preserveScroll: true,
        onError: () => {
          setImportError(t('customer_settings.blacklists.import.failed_error'))
        }
      })
    } catch {
      setImportError(t('customer_settings.blacklists.import.read_error'))
    } finally {
      setIsImportingFile(false)
    }
  }

  const handleDelete = (id: number) => {
    if (confirm(t('customer_settings.blacklists.delete_confirm'))) {
      setDeletingId(id)
      router.delete(`/settings/blacklists/${id}`, {
        preserveScroll: true,
        onFinish: () => setDeletingId(null)
      })
    }
  }

  const formatDate = (dateString: string) => {
    return new Date(dateString).toLocaleDateString('en-US', {
      year: 'numeric',
      month: 'short',
      day: 'numeric'
    })
  }

  const getReasonBadgeVariant = (reason: string | null) => {
    if (!reason) return 'default'
    const r = reason.toLowerCase()
    if (r.includes('bounce')) return 'warning'
    if (r.includes('invalid')) return 'error'
    return 'default'
  }

  return (
    <SettingsLayout
      currentTab="blacklists"
      sidebarSections={[
            { id: 'emails', label: t('customer_settings.blacklists.sections.email') },
            { id: 'domains', label: t('customer_settings.blacklists.sections.domain') },
            { id: 'import', label: t('customer_settings.blacklists.sections.import') },
            { id: 'export', label: t('customer_settings.blacklists.sections.export') },
          ]}
    >
      <div className="space-y-8 max-w-5xl">
        {/* Section 1: Email Blacklist */}
        <div id="emails" className="scroll-mt-8">
          <Card>
            <CardHeader>
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-3">
                  <div className="h-10 w-10 rounded-lg bg-white/5 flex items-center justify-center">
                    <Mail className="h-5 w-5 text-[var(--foreground-muted)]" />
                  </div>
                  <div>
                    <div className="text-lg font-semibold text-[var(--foreground)]">{t('customer_settings.blacklists.email_title')}</div>
                    <div className="text-sm text-[var(--foreground-muted)]">{emailSubtitle}</div>
                  </div>
                </div>
                {canAdd && (
                  <Button variant="secondary" icon={<Plus className="h-4 w-4" />} onClick={() => setShowAddEmail(true)}>
                    {t('common.add')}
                  </Button>
                )}
              </div>
            </CardHeader>
            <CardContent>
              <div className="mb-4 relative">
                <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-[var(--foreground-muted)]" />
                <input 
                  type="text"
                  placeholder={t('customer_settings.blacklists.search_emails')}
                  value={emailSearch}
                  onChange={e => setEmailSearch(e.target.value)}
                  onKeyDown={e => {
                    if (e.key === 'Enter') applyEmailSearch()
                  }}
                  onBlur={applyEmailSearch}
                  className="w-full pl-9 pr-4 py-2 bg-[var(--input)] border border-[var(--input-border)] rounded-lg text-sm text-[var(--foreground)] focus:outline-none focus:ring-2 focus:ring-[var(--accent)]"
                />
              </div>
              
              <div className="border border-[var(--border)] rounded-lg overflow-hidden">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>{t('customer_settings.blacklists.table.email')}</TableHead>
                      <TableHead>{t('customer_settings.blacklists.table.added')}</TableHead>
                      <TableHead>{t('customer_settings.blacklists.table.reason')}</TableHead>
                      {canRemove && <TableHead className="w-16"><span className="sr-only">{t('customer_settings.common.actions')}</span></TableHead>}
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {email_blacklists.length === 0 ? (
                      <TableRow>
                        <TableCell colSpan={canRemove ? 4 : 3} className="text-center py-8 text-[var(--foreground-muted)]">
                          {t('customer_settings.blacklists.email_empty')}
                        </TableCell>
                      </TableRow>
                    ) : (
                      email_blacklists.map(entry => (
                        <TableRow key={entry.id}>
                          <TableCell className="font-medium text-[var(--foreground)]">{entry.value}</TableCell>
                          <TableCell className="text-[var(--foreground-muted)]">{formatDate(entry.created_at)}</TableCell>
                          <TableCell>
                            <Badge variant={getReasonBadgeVariant(entry.reason)}>
                              {entry.reason || t('customer_settings.blacklists.manual_reason')}
                            </Badge>
                          </TableCell>
                          {canRemove && (
                            <TableCell className="text-right">
                              {entry.can_delete && (
                                <button
                                  type="button"
                                  onClick={() => handleDelete(entry.id)}
                                  disabled={deletingId === entry.id}
                                  title={t('customer_settings.blacklists.remove_entry')}
                                  aria-label={t('customer_settings.blacklists.remove_entry')}
                                  className="inline-flex h-8 w-8 items-center justify-center rounded-md text-[var(--foreground-muted)] hover:text-[var(--error)] hover:bg-[var(--error)]/10 transition-colors disabled:opacity-50"
                                >
                                  <Trash2 className="h-4 w-4" />
                                </button>
                              )}
                            </TableCell>
                          )}
                        </TableRow>
                      ))
                    )}
                  </TableBody>
                </Table>
              </div>

              {pagination.emails.total_pages > 1 && (
                <div className="mt-4 flex items-center justify-between">
                  <p className="text-xs text-[var(--foreground-muted)]">
                    {t('customer_settings.blacklists.pagination.emails', { start: (pagination.emails.current_page - 1) * pagination.emails.per_page + 1, end: Math.min(pagination.emails.current_page * pagination.emails.per_page, pagination.emails.total_count), total: pagination.emails.total_count })}
                  </p>
                  <div className="inline-flex items-center gap-2">
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => goToEmailPage(pagination.emails.current_page - 1)}
                      disabled={pagination.emails.current_page === 1}
                      icon={<ChevronLeft className="h-4 w-4" />}
                    >
                      {t('common.previous')}
                    </Button>
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => goToEmailPage(pagination.emails.current_page + 1)}
                      disabled={pagination.emails.current_page === pagination.emails.total_pages}
                      icon={<ChevronRight className="h-4 w-4" />}
                    >
                      {t('common.next')}
                    </Button>
                  </div>
                </div>
              )}
            </CardContent>
          </Card>
        </div>

        {/* Section 2: Domain Blacklist */}
        <div id="domains" className="scroll-mt-8">
          <Card>
            <CardHeader>
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-3">
                  <div className="h-10 w-10 rounded-lg bg-white/5 flex items-center justify-center">
                    <Globe className="h-5 w-5 text-[var(--foreground-muted)]" />
                  </div>
                  <div>
                    <div className="text-lg font-semibold text-[var(--foreground)]">{t('customer_settings.blacklists.domain_title')}</div>
                    <div className="text-sm text-[var(--foreground-muted)]">{domainSubtitle}</div>
                  </div>
                </div>
                {canAdd && (
                  <Button variant="secondary" icon={<Plus className="h-4 w-4" />} onClick={() => setShowAddDomain(true)}>
                    {t('common.add')}
                  </Button>
                )}
              </div>
            </CardHeader>
            <CardContent>
              <div className="mb-4 relative">
                <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-[var(--foreground-muted)]" />
                <input 
                  type="text"
                  placeholder={t('customer_settings.blacklists.search_domains')}
                  value={domainSearch}
                  onChange={e => setDomainSearch(e.target.value)}
                  onKeyDown={e => {
                    if (e.key === 'Enter') applyDomainSearch()
                  }}
                  onBlur={applyDomainSearch}
                  className="w-full pl-9 pr-4 py-2 bg-[var(--input)] border border-[var(--input-border)] rounded-lg text-sm text-[var(--foreground)] focus:outline-none focus:ring-2 focus:ring-[var(--accent)]"
                />
              </div>
              
              <div className="border border-[var(--border)] rounded-lg overflow-hidden">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>{t('customer_settings.blacklists.table.domain')}</TableHead>
                      <TableHead>{t('customer_settings.blacklists.table.added')}</TableHead>
                      <TableHead>{t('customer_settings.blacklists.table.reason')}</TableHead>
                      {canRemove && <TableHead className="w-16"><span className="sr-only">{t('customer_settings.common.actions')}</span></TableHead>}
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {domain_blacklists.length === 0 ? (
                      <TableRow>
                        <TableCell colSpan={canRemove ? 4 : 3} className="text-center py-8 text-[var(--foreground-muted)]">
                          {t('customer_settings.blacklists.domain_empty')}
                        </TableCell>
                      </TableRow>
                    ) : (
                      domain_blacklists.map(entry => (
                        <TableRow key={entry.id}>
                          <TableCell className="font-medium text-[var(--foreground)]">{entry.value}</TableCell>
                          <TableCell className="text-[var(--foreground-muted)]">{formatDate(entry.created_at)}</TableCell>
                          <TableCell>
                            <Badge variant={getReasonBadgeVariant(entry.reason)}>
                              {entry.reason || t('customer_settings.blacklists.manual_reason')}
                            </Badge>
                          </TableCell>
                          {canRemove && (
                            <TableCell className="text-right">
                              {entry.can_delete && (
                                <button
                                  type="button"
                                  onClick={() => handleDelete(entry.id)}
                                  disabled={deletingId === entry.id}
                                  title={t('customer_settings.blacklists.remove_entry')}
                                  aria-label={t('customer_settings.blacklists.remove_entry')}
                                  className="inline-flex h-8 w-8 items-center justify-center rounded-md text-[var(--foreground-muted)] hover:text-[var(--error)] hover:bg-[var(--error)]/10 transition-colors disabled:opacity-50"
                                >
                                  <Trash2 className="h-4 w-4" />
                                </button>
                              )}
                            </TableCell>
                          )}
                        </TableRow>
                      ))
                    )}
                  </TableBody>
                </Table>
              </div>

              {pagination.domains.total_pages > 1 && (
                <div className="mt-4 flex items-center justify-between">
                  <p className="text-xs text-[var(--foreground-muted)]">
                    {t('customer_settings.blacklists.pagination.domains', { start: (pagination.domains.current_page - 1) * pagination.domains.per_page + 1, end: Math.min(pagination.domains.current_page * pagination.domains.per_page, pagination.domains.total_count), total: pagination.domains.total_count })}
                  </p>
                  <div className="inline-flex items-center gap-2">
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => goToDomainPage(pagination.domains.current_page - 1)}
                      disabled={pagination.domains.current_page === 1}
                      icon={<ChevronLeft className="h-4 w-4" />}
                    >
                      {t('common.previous')}
                    </Button>
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => goToDomainPage(pagination.domains.current_page + 1)}
                      disabled={pagination.domains.current_page === pagination.domains.total_pages}
                      icon={<ChevronRight className="h-4 w-4" />}
                    >
                      {t('common.next')}
                    </Button>
                  </div>
                </div>
              )}
            </CardContent>
          </Card>
        </div>

        {/* Section 3: Import/Export */}
        <div id="import" className="scroll-mt-8">
          <Card>
            <CardHeader>
              <div className="flex items-center gap-3">
                <div className="h-10 w-10 rounded-lg bg-white/5 flex items-center justify-center">
                  <Upload className="h-5 w-5 text-[var(--foreground-muted)]" />
                </div>
                <div>
                  <div className="text-lg font-semibold text-[var(--foreground)]">{t('customer_settings.blacklists.import.title')}</div>
                  <div className="text-sm text-[var(--foreground-muted)]">{t('customer_settings.blacklists.import.description')}</div>
                </div>
              </div>
            </CardHeader>
            <CardContent>
              <div className="border border-[var(--border)] rounded-lg p-6 flex flex-col items-center text-center hover:border-[var(--foreground-subtle)] transition-colors">
                  <div className="h-12 w-12 rounded-full bg-white/5 flex items-center justify-center mb-4">
                    <Upload className="h-6 w-6 text-[var(--foreground)]" />
                  </div>
                  <h3 className="font-medium text-[var(--foreground)] mb-2">{t('customer_settings.blacklists.import.csv_title')}</h3>
                  <p className="text-sm text-[var(--foreground-muted)] mb-6">{t('customer_settings.blacklists.import.csv_description')}</p>
                  <input
                    type="file"
                    accept=".csv,.txt"
                    className="hidden"
                    ref={importFileInputRef}
                    onChange={(e) => {
                      const selectedFile = e.target.files?.[0] || null
                      void handleCsvImport(selectedFile)
                      e.currentTarget.value = ''
                    }}
                    disabled={isImportingFile}
                  />
                  <Button
                    type="button"
                    variant="secondary"
                    className="w-full"
                    disabled={isImportingFile}
                    onClick={() => importFileInputRef.current?.click()}
                  >
                    {isImportingFile ? t('customer_settings.blacklists.import.importing') : t('customer_settings.blacklists.import.select_file')}
                  </Button>
                </div>

              {importError && (
                <div className="mt-4 rounded-lg border border-[var(--error)]/30 bg-[var(--error)]/10 px-4 py-3 text-sm text-[var(--error)]">
                  {importError}
                </div>
              )}
            </CardContent>
          </Card>
        </div>

        <div id="export" className="scroll-mt-8">
          <Card>
            <CardHeader>
              <div className="flex items-center gap-3">
                <div className="h-10 w-10 rounded-lg bg-white/5 flex items-center justify-center">
                  <Download className="h-5 w-5 text-[var(--foreground-muted)]" />
                </div>
                <div>
                  <div className="text-lg font-semibold text-[var(--foreground)]">{t('customer_settings.blacklists.export.title')}</div>
                  <div className="text-sm text-[var(--foreground-muted)]">{t('customer_settings.blacklists.export.description')}</div>
                </div>
              </div>
            </CardHeader>
            <CardContent>
              <div className="border border-[var(--border)] rounded-lg p-6 flex flex-col items-center text-center hover:border-[var(--foreground-subtle)] transition-colors">
                <div className="h-12 w-12 rounded-full bg-white/5 flex items-center justify-center mb-4">
                  <Download className="h-6 w-6 text-[var(--foreground)]" />
                </div>
                <h3 className="font-medium text-[var(--foreground)] mb-2">{t('customer_settings.blacklists.export.csv_title')}</h3>
                <p className="text-sm text-[var(--foreground-muted)] mb-6">{t('customer_settings.blacklists.export.csv_description')}</p>
                <Button asChild variant="secondary" className="w-full">
                  <a href="/settings/blacklists/export" download>
                    {t('customer_settings.blacklists.export.download')}
                  </a>
                </Button>
              </div>
            </CardContent>
          </Card>
        </div>
      </div>

      {/* Dialogs */}
      {showAddEmail && <AddEmailDialog onClose={() => setShowAddEmail(false)} />}
      {showAddDomain && <AddDomainDialog onClose={() => setShowAddDomain(false)} />}
    </SettingsLayout>
  )
}

function AddEmailDialog({ onClose }: { onClose: () => void }) {
  const [emails, setEmails] = useState('')
  const [isSubmitting, setIsSubmitting] = useState(false)

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    const emailList = emails
      .split(/\r?\n/)
      .map((value) => value.trim())
      .filter((value) => value.length > 0)

    if (emailList.length === 0) return

    setIsSubmitting(true)

    const submitNext = (index: number) => {
      if (index >= emailList.length) {
        setIsSubmitting(false)
        onClose()
        return
      }

      router.post('/settings/blacklists', {
        blacklist: { value: emailList[index], value_type: 'email' }
      }, {
        onFinish: () => submitNext(index + 1)
      })
    }

    submitNext(0)
  }

  return (
    <div className="fixed inset-0 bg-black/60 backdrop-blur-sm z-50 flex items-center justify-center p-4">
      <div className="bg-[var(--card)] border border-[var(--border)] rounded-xl shadow-2xl w-full max-w-md overflow-hidden flex flex-col">
        <div className="px-6 py-4 border-b border-[var(--border)] flex justify-between items-center">
          <h2 className="text-lg font-semibold text-[var(--foreground)]">{t('customer_settings.blacklists.dialogs.add_emails_title')}</h2>
          <button type="button" onClick={onClose} className="text-[var(--foreground-muted)] hover:text-[var(--foreground)]">
            <XCircle className="h-5 w-5" />
          </button>
        </div>
        <form onSubmit={handleSubmit}>
          <div className="p-6">
            <Textarea
              label={t('customer_settings.blacklists.dialogs.email_addresses')}
              placeholder={"badactor@example.com\nspam@contoso.com"}
              description={t('customer_settings.blacklists.dialogs.email_description')}
              value={emails}
              onChange={e => setEmails(e.target.value)}
              rows={5}
              autoFocus
            />
          </div>
          <div className="px-6 py-4 border-t border-[var(--border)] bg-white/[0.02] flex justify-end gap-3">
            <Button type="button" variant="ghost" onClick={onClose}>{t('common.cancel')}</Button>
            <Button type="submit" variant="primary" disabled={!emails.trim() || isSubmitting} loading={isSubmitting}>{t('common.add')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}

function AddDomainDialog({ onClose }: { onClose: () => void }) {
  const [domains, setDomains] = useState('')
  const [isSubmitting, setIsSubmitting] = useState(false)

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    if (!domains.trim()) return
    
    const domainList = domains
      .split(/\r?\n/)
      .map((value) => value.trim())
      .filter((value) => value.length > 0)

    if (domainList.length === 0) return

    setIsSubmitting(true)
    
    const submitNext = (index: number) => {
      if (index >= domainList.length) {
        setIsSubmitting(false)
        onClose()
        return
      }
      
      router.post('/settings/blacklists', {
        blacklist: { value: domainList[index], value_type: 'domain' }
      }, {
        onFinish: () => submitNext(index + 1)
      })
    }
    
    submitNext(0)
  }

  return (
    <div className="fixed inset-0 bg-black/60 backdrop-blur-sm z-50 flex items-center justify-center p-4">
      <div className="bg-[var(--card)] border border-[var(--border)] rounded-xl shadow-2xl w-full max-w-md overflow-hidden flex flex-col">
        <div className="px-6 py-4 border-b border-[var(--border)] flex justify-between items-center">
          <h2 className="text-lg font-semibold text-[var(--foreground)]">{t('customer_settings.blacklists.dialogs.add_domains_title')}</h2>
          <button type="button" onClick={onClose} className="text-[var(--foreground-muted)] hover:text-[var(--foreground)]">
            <XCircle className="h-5 w-5" />
          </button>
        </div>
        <form onSubmit={handleSubmit}>
          <div className="p-6">
            <Textarea 
              label={t('customer_settings.blacklists.dialogs.domains')}
              placeholder={"example.com\nbad-domain.io"}
              description={t('customer_settings.blacklists.dialogs.domain_description')}
              value={domains}
              onChange={e => setDomains(e.target.value)}
              rows={5}
              autoFocus
            />
          </div>
          <div className="px-6 py-4 border-t border-[var(--border)] bg-white/[0.02] flex justify-end gap-3">
            <Button type="button" variant="ghost" onClick={onClose}>{t('common.cancel')}</Button>
            <Button type="submit" variant="primary" disabled={!domains.trim() || isSubmitting} loading={isSubmitting}>{t('common.add')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}

function parseImportInput(input: string): string[] {
  return input
    .split(/[\n,;]+/)
    .map((value) => value.trim().toLowerCase())
    .filter((value) => value.length > 0)
}
