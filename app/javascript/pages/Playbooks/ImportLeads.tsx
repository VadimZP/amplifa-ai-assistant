import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import PlaybookLayout from '../../layouts/PlaybookLayout'
import { t } from '../../lib/i18n'
import { Card, CardContent } from '../../components/ui/Card'
import { Button } from '../../components/ui/Button'
import { Badge } from '../../components/ui/Badge'
import { AlertCircle, ArrowRight, Check, Download, FileText, Loader, Upload } from 'lucide-react'

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
}

interface Agent {
  id: number
  name: string
}

interface LeadImport {
  id: number
  original_filename: string
  status: string
  total_rows: number
  processed_rows: number
  created_count: number
  updated_count: number
  skipped_count: number
  blacklisted_count: number
  error_count: number
  progress_percentage: number
  created_at: string
  completed_at: string | null
  agent: Agent | null
}

interface AnalysisSummary {
  total_rows: number
  new_person_count: number
  new_lead_count: number
  update_lead_count: number
  invalid_count: number
}

interface AnalysisResult {
  summary: AnalysisSummary
}

interface ImportLeadsProps {
  playbook: Playbook
  lead_imports: LeadImport[]
  lead_list_files?: LeadListFile[]
  canApprove?: boolean
  canRequestChanges?: boolean
  canArchive?: boolean
  flash?: {
    notice?: string
    alert?: string
  }
}

interface LeadListFile {
  id: number
  original_filename: string
  file_size_bytes: number | null
  content_type: string | null
  created_at: string
}

const LEAD_FIELDS = [
  { value: '', labelKey: 'playbooks.import_leads_ui.skip_column' },
  { value: 'email', labelKey: 'playbooks.import_leads_ui.field_email' },
  { value: 'first_name', labelKey: 'playbooks.import_leads_ui.field_first_name' },
  { value: 'last_name', labelKey: 'playbooks.import_leads_ui.field_last_name' },
  { value: 'full_name', labelKey: 'playbooks.import_leads_ui.field_full_name' },
  { value: 'job_title', labelKey: 'playbooks.import_leads_ui.field_job_title' },
  { value: 'company', labelKey: 'playbooks.import_leads_ui.field_company' },
  { value: 'company_website', labelKey: 'playbooks.import_leads_ui.field_company_website' },
  { value: 'linkedin_url', labelKey: 'playbooks.import_leads_ui.field_linkedin_url' },
  { value: 'location', labelKey: 'playbooks.import_leads_ui.field_location' },
]

const sanitizeColumnMapping = (mapping: Record<string, string>) => {
  return Object.fromEntries(
    Object.entries(mapping).filter(([, value]) => value.trim() !== '')
  )
}

export default function ImportLeads({
  playbook,
  lead_imports,
  lead_list_files = [],
  flash,
  canApprove,
  canRequestChanges,
  canArchive,
}: ImportLeadsProps) {
  const [imports, setImports] = useState(lead_imports)
  const [leadListFiles, setLeadListFiles] = useState(lead_list_files)
  const [step, setStep] = useState(1)
  const [file, setFile] = useState<File | null>(null)
  const [csvHeaders, setCsvHeaders] = useState<string[]>([])
  const [previewRows, setPreviewRows] = useState<Record<string, string>[]>([])
  const [columnMapping, setColumnMapping] = useState<Record<string, string>>({})
  const [totalRows, setTotalRows] = useState(0)
  const [isSubmitting, setIsSubmitting] = useState(false)
  const [isAnalyzing, setIsAnalyzing] = useState(false)
  const [analysisError, setAnalysisError] = useState<string | null>(null)
  const [analysisResult, setAnalysisResult] = useState<AnalysisResult | null>(null)
  const [formError, setFormError] = useState<string | null>(null)
  const [isLeadListUploading, setIsLeadListUploading] = useState(false)
  const [leadListError, setLeadListError] = useState<string | null>(null)

  const fileInputRef = useRef<HTMLInputElement>(null)
  const leadListFileInputRef = useRef<HTMLInputElement>(null)
  const processingImportIds = useMemo(
    () => imports.filter((item) => item.status === 'pending' || item.status === 'processing').map((item) => item.id),
    [imports],
  )

  useEffect(() => {
    setImports(lead_imports)
  }, [lead_imports])

  useEffect(() => {
    setLeadListFiles(lead_list_files)
  }, [lead_list_files])

  useEffect(() => {
    if (processingImportIds.length === 0) {
      return undefined
    }

    const interval = setInterval(async () => {
      const updates = await Promise.all(
        processingImportIds.map(async (id) => {
          const response = await fetch(`/api/v1/lead_imports/${id}`)
          if (!response.ok) {
            return null
          }

          const json = await response.json()
          return {
            id,
            status: json.status,
            total_rows: json.total_rows,
            processed_rows: json.processed_rows,
            created_count: json.created_count,
            updated_count: json.updated_count,
            skipped_count: json.skipped_count,
            blacklisted_count: json.blacklisted_count,
            error_count: json.error_count,
            progress_percentage: json.progress_percentage,
            completed_at: json.completed_at,
          }
        }),
      )

      setImports((prev) =>
        prev.map((entry) => {
          const update = updates.find((item) => item && item.id === entry.id)
          return update ? { ...entry, ...update } : entry
        }),
      )
    }, 3000)

    return () => clearInterval(interval)
  }, [processingImportIds])

  const hasEmailMapping = Object.values(columnMapping).includes('email')
  const emailColumn = Object.entries(columnMapping).find(([, field]) => field === 'email')?.[0]
  const mappedFields = new Set(Object.values(columnMapping).filter((value) => value !== ''))

  const parseCsvLine = (line: string): string[] => {
    const result: string[] = []
    let current = ''
    let inQuotes = false

    for (let index = 0; index < line.length; index += 1) {
      const character = line[index]

      if (character === '"') {
        inQuotes = !inQuotes
      } else if (character === ',' && !inQuotes) {
        result.push(current.trim())
        current = ''
      } else {
        current += character
      }
    }

    result.push(current.trim())
    return result
  }

  const suggestColumnMappings = (headers: string[]): Record<string, string> => {
    const mappings: Record<string, string> = {}
    const fieldPatterns: Record<string, RegExp[]> = {
      email: [/^e[-_\s]?mail$/i, /^e[-_\s]?mail[-_\s]?address$/i, /^mail$/i],
      first_name: [/^first[-_\s]?name$/i, /^fname$/i],
      last_name: [/^last[-_\s]?name$/i, /^lname$/i, /^surname$/i],
      full_name: [/^full[-_\s]?name$/i, /^name$/i],
      job_title: [/^job[-_\s]?title$/i, /^title$/i, /^position$/i],
      company: [/^company$/i, /^company[-_\s]?name$/i, /^organization$/i],
      company_website: [
        /^website$/i,
        /^company[-_\s]?website$/i,
        /^company[-_\s]?domain$/i,
        /^domain$/i,
        /^website[-_\s]?domain$/i,
        /^website[-_\s]?url$/i,
        /^url$/i,
        /^company[-_\s]?url$/i,
        /^homepage$/i,
        /^web$/i,
      ],
      linkedin_url: [/^linkedin$/i, /^linkedin[-_\s]?url$/i],
      location: [/^location$/i, /^city$/i, /^address$/i],
    }

    headers.forEach((header) => {
      Object.entries(fieldPatterns).forEach(([field, patterns]) => {
        if (mappings[header]) {
          return
        }

        if (patterns.some((pattern) => pattern.test(header.trim())) && !Object.values(mappings).includes(field)) {
          mappings[header] = field
        }
      })
    })

    return mappings
  }

  const parseCsvPreview = async (csvFile: File) => {
    const content = await csvFile.text()
    const lines = content.split('\n').filter((line) => line.trim())
    if (lines.length === 0) {
      return
    }

    const headers = parseCsvLine(lines[0])
    setCsvHeaders(headers)
    setTotalRows(lines.length - 1)

    const rows: Record<string, string>[] = []
    for (let rowIndex = 1; rowIndex < Math.min(6, lines.length); rowIndex += 1) {
      const values = parseCsvLine(lines[rowIndex])
      const row: Record<string, string> = {}

      headers.forEach((header, headerIndex) => {
        row[header] = values[headerIndex] || ''
      })

      rows.push(row)
    }

    setPreviewRows(rows)
    setColumnMapping(suggestColumnMappings(headers))
  }

  const resetForm = () => {
    setStep(1)
    setFile(null)
    setCsvHeaders([])
    setPreviewRows([])
    setColumnMapping({})
    setTotalRows(0)
    setAnalysisResult(null)
    setAnalysisError(null)
    setFormError(null)
    if (fileInputRef.current) {
      fileInputRef.current.value = ''
    }
  }

  const handleFileChange = async (event: React.ChangeEvent<HTMLInputElement>) => {
    const selectedFile = event.target.files?.[0]
    if (!selectedFile) {
      return
    }

    if (!(selectedFile.type === 'text/csv' || selectedFile.name.endsWith('.csv'))) {
      setFormError('Please upload a valid CSV file')
      return
    }

    setFormError(null)
    setFile(selectedFile)
    await parseCsvPreview(selectedFile)
  }

  const runAnalysis = useCallback(async () => {
    if (!file || !emailColumn) {
      return
    }

    setIsAnalyzing(true)
    setAnalysisError(null)

    try {
      const formData = new FormData()
      formData.append('csv_file', file)
      formData.append('email_column', emailColumn)

      const response = await fetch(`/playbooks/${playbook.id}/import_leads_analyze`, {
        method: 'POST',
        body: formData,
        headers: {
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || '',
        },
      })

      const json = await response.json()
      if (!response.ok) {
        setAnalysisError(json.error || 'Analysis failed')
        setAnalysisResult(null)
      } else {
        setAnalysisResult(json)
      }
    } catch {
      setAnalysisError('Analysis failed')
      setAnalysisResult(null)
    } finally {
      setIsAnalyzing(false)
    }
  }, [emailColumn, file, playbook.id])

  useEffect(() => {
    if (step === 2 && hasEmailMapping) {
      void runAnalysis()
    }
  }, [step, hasEmailMapping, runAnalysis])

  const handleCreateImport = async () => {
    if (!file || !hasEmailMapping) {
      return
    }

    setIsSubmitting(true)
    setFormError(null)

    try {
      const formData = new FormData()
      formData.append('lead_import[csv_file]', file)
      formData.append('lead_import[column_mapping]', JSON.stringify(sanitizeColumnMapping(columnMapping)))

      const response = await fetch(`/playbooks/${playbook.id}/import_leads`, {
        method: 'POST',
        body: formData,
        headers: {
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || '',
        },
      })

      const json = await response.json()
      if (!response.ok) {
        const firstError = Object.values(json.errors || {})[0]
        const message = Array.isArray(firstError) ? firstError[0] : 'Import could not be started'
        setFormError(message)
        return
      }

      setImports((prev) => [json.lead_import as LeadImport, ...prev])
      resetForm()
    } catch {
      setFormError('Import could not be started')
    } finally {
      setIsSubmitting(false)
    }
  }

  const formatDate = (value: string | null) => {
    if (!value) {
      return '—'
    }

    return new Date(value).toLocaleDateString('en-US', {
      year: 'numeric',
      month: 'short',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
    })
  }

  const formatFileSize = (bytes: number | null) => {
    if (!bytes || bytes <= 0) {
      return '—'
    }

    if (bytes < 1024) {
      return `${bytes} B`
    }

    if (bytes < 1024 * 1024) {
      return `${(bytes / 1024).toFixed(1)} KB`
    }

    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
  }

  const getStatusBadgeVariant = (status: string): 'default' | 'success' | 'warning' | 'error' | 'info' => {
    switch (status) {
      case 'pending':
        return 'warning'
      case 'processing':
        return 'info'
      case 'completed':
        return 'success'
      case 'failed':
        return 'error'
      default:
        return 'default'
    }
  }

  const handleLeadListFileUpload = async (event: React.ChangeEvent<HTMLInputElement>) => {
    const selectedFile = event.target.files?.[0]
    if (!selectedFile) {
      return
    }

    setLeadListError(null)
    setIsLeadListUploading(true)

    try {
      const formData = new FormData()
      formData.append('lead_list_file', selectedFile)

      const response = await fetch(`/playbooks/${playbook.id}/lead_list_files`, {
        method: 'POST',
        body: formData,
        headers: {
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || '',
        },
      })

      const json = await response.json()
      if (!response.ok) {
        setLeadListError(json.error || 'File upload failed')
        return
      }

      setLeadListFiles((prev) => [json.lead_list_file as LeadListFile, ...prev])
    } catch {
      setLeadListError('File upload failed')
    } finally {
      setIsLeadListUploading(false)
      if (leadListFileInputRef.current) {
        leadListFileInputRef.current.value = ''
      }
    }
  }

  return (
    <PlaybookLayout
      playbook={playbook}
      currentTab="import_leads"
      canApprove={canApprove}
      canRequestChanges={canRequestChanges}
      canArchive={canArchive}
      flash={flash}
    >
      <div className="space-y-6">
        <Card>
          <CardContent className="p-6 space-y-4">
            <div className="flex items-start justify-between gap-4">
              <div>
                <h3 className="text-lg font-semibold text-[var(--foreground)]">{t('playbooks.import_leads_ui.lead_list_title')}</h3>
                <p className="text-sm text-[var(--foreground-muted)] mt-1">
                  {t('playbooks.import_leads_ui.lead_list_description')}
                </p>
              </div>

              <div>
                <input
                  ref={leadListFileInputRef}
                  type="file"
                  className="hidden"
                  onChange={(event) => {
                    void handleLeadListFileUpload(event)
                  }}
                />
                <Button
                  type="button"
                  onClick={() => leadListFileInputRef.current?.click()}
                  disabled={isLeadListUploading}
                >
                  {isLeadListUploading ? t('playbooks.import_leads_ui.uploading') : t('playbooks.import_leads_ui.upload_file')}
                </Button>
              </div>
            </div>

            {leadListError && <p className="text-sm text-[var(--error)]">{leadListError}</p>}

            {leadListFiles.length > 0 && (
              <div className="space-y-2">
                {leadListFiles.map((fileItem) => (
                  <div key={fileItem.id} className="flex items-center justify-between gap-4 rounded-lg border border-[var(--border)] bg-[var(--card)] px-4 py-3">
                    <div className="min-w-0">
                      <p className="truncate text-sm font-medium text-[var(--foreground)]">{fileItem.original_filename}</p>
                      <p className="text-xs text-[var(--foreground-muted)]">
                        {t('playbooks.import_leads_ui.uploaded_at', { date: formatDate(fileItem.created_at) })} · {formatFileSize(fileItem.file_size_bytes)}
                      </p>
                    </div>

                    <a
                      href={`/playbooks/${playbook.id}/lead_list_files/${fileItem.id}/download`}
                      className="inline-flex items-center text-[var(--accent)] hover:text-[var(--accent-hover)]"
                      title={t('playbooks.files.download')}
                    >
                      <Download className="h-4 w-4" />
                    </a>
                  </div>
                ))}
              </div>
            )}
          </CardContent>
        </Card>

        {imports.length > 0 && (
          <Card>
            <CardContent className="p-6">
              <div className="mb-4 flex items-center justify-between">
                <h3 className="text-lg font-semibold text-[var(--foreground)]">{t('admin.lead_imports.title')}</h3>
              </div>

              <div className="space-y-3">
                {imports.map((item) => (
                  <div key={item.id} className="rounded-lg border border-[var(--border)] p-4 bg-[var(--card)]">
                    <div className="flex flex-wrap items-center justify-between gap-3">
                      <div>
                        <p className="font-medium text-[var(--foreground)]">{item.original_filename}</p>
                        <p className="text-xs text-[var(--foreground-muted)]">{t('playbooks.import_leads_ui.imported_at', { date: formatDate(item.created_at) })}</p>
                        {item.completed_at && (
                          <p className="text-xs text-[var(--foreground-muted)]">{t('playbooks.import_leads_ui.completed_at', { date: formatDate(item.completed_at) })}</p>
                        )}
                      </div>

                      <div className="flex items-center gap-2">
                        <Badge variant={getStatusBadgeVariant(item.status)}>{t(`admin.lead_imports.statuses.${item.status}`)}</Badge>
                        <a
                          href={`/playbooks/${playbook.id}/imports/${item.id}/download`}
                          className="inline-flex items-center text-[var(--accent)] hover:text-[var(--accent-hover)]"
                          title={t('admin.lead_imports.download.button')}
                        >
                          <Download className="h-4 w-4" />
                        </a>
                      </div>
                    </div>

                    <div className="mt-3 flex items-center gap-2">
                      <div className="h-1.5 w-32 rounded-full bg-[var(--secondary)]">
                        <div
                          className="h-1.5 rounded-full bg-[var(--accent)] transition-all"
                          style={{ width: `${item.progress_percentage}%` }}
                        />
                      </div>
                      <span className="text-xs text-[var(--foreground-muted)]">{item.progress_percentage}%</span>
                    </div>

                    {item.status === 'completed' && (
                      <p className="mt-2 text-xs text-[var(--foreground-muted)]">
                        {t('playbooks.import_leads_ui.created_count', { count: item.created_count })} · {t('playbooks.import_leads_ui.updated_count', { count: item.updated_count })} · {t('playbooks.import_leads_ui.blacklisted_count', { count: item.blacklisted_count })} · {t('playbooks.import_leads_ui.error_count', { count: item.error_count })}
                      </p>
                    )}
                  </div>
                ))}
              </div>
            </CardContent>
          </Card>
        )}

        <Card>
          <CardContent className="p-6 space-y-5">
            <div className="flex items-center gap-3 text-sm text-[var(--foreground-muted)]">
              <Badge variant={step === 1 ? 'info' : 'default'}>{t('playbooks.import_leads_ui.step_upload_csv')}</Badge>
              <ArrowRight className="h-4 w-4" />
              <Badge variant={step === 2 ? 'info' : 'default'}>{t('playbooks.import_leads_ui.step_map_fields')}</Badge>
            </div>

            {step === 1 && (
              <>
                <div>
                  <input
                    ref={fileInputRef}
                    type="file"
                    accept=".csv,text/csv"
                    className="hidden"
                    onChange={(event) => {
                      void handleFileChange(event)
                    }}
                  />

                  <button
                    type="button"
                    onClick={() => fileInputRef.current?.click()}
                    className="flex w-full flex-col items-center justify-center rounded-xl border-2 border-dashed border-[var(--border)] bg-[var(--input)] px-6 py-8 text-center hover:border-[var(--foreground-subtle)]"
                  >
                    <Upload className="mb-2 h-7 w-7 text-[var(--foreground-muted)]" />
                    <p className="text-sm text-[var(--foreground)]">{t('playbooks.import_leads_ui.click_to_upload_csv')}</p>
                    <p className="text-xs text-[var(--foreground-muted)]">{t('playbooks.import_leads_ui.max_file_size')}</p>
                    {file && (
                      <p className="mt-2 text-xs text-[var(--accent)]">
                        {file.name} · {t('playbooks.import_leads_ui.selected_rows', { count: totalRows })}
                      </p>
                    )}
                  </button>
                </div>

                <div className="flex items-center justify-between">
                  <a
                    href={`/playbooks/${playbook.id}/import_leads_template`}
                    className="inline-flex items-center gap-1 text-sm text-[var(--accent)] hover:text-[var(--accent-hover)]"
                  >
                    <Download className="h-4 w-4" />
                    {t('admin.lead_imports.new.download_template')}
                  </a>

                  <Button
                    onClick={() => setStep(2)}
                    disabled={!file}
                  >
                    {t('playbooks.import_leads_ui.next_map_fields')}
                    <ArrowRight className="ml-2 h-4 w-4" />
                  </Button>
                </div>
              </>
            )}

            {step === 2 && (
              <>
                <div className="space-y-3">
                  {csvHeaders.map((header) => {
                    const currentMapping = columnMapping[header] || ''

                    return (
                      <div key={header} className="flex items-center gap-3 rounded-lg border border-[var(--border)] p-3">
                        <div className="min-w-0 flex-1">
                          <p className="truncate text-sm font-medium text-[var(--foreground)]">{header}</p>
                          {previewRows[0]?.[header] && (
                            <p className="truncate text-xs text-[var(--foreground-muted)]">{t('playbooks.import_leads_ui.example_value', { value: previewRows[0][header] })}</p>
                          )}
                        </div>

                        <ArrowRight className="h-4 w-4 text-[var(--foreground-subtle)]" />

                        <select
                          value={currentMapping}
                          onChange={(event) => {
                            setColumnMapping((prev) => {
                              if (event.target.value === '') {
                                const next = { ...prev }
                                delete next[header]
                                return next
                              }

                              return {
                                ...prev,
                                [header]: event.target.value,
                              }
                            })
                          }}
                          className="w-52 rounded-lg border border-[var(--input-border)] bg-[var(--input)] px-3 py-2 text-sm text-[var(--foreground)]"
                        >
                          {LEAD_FIELDS.map((field) => {
                            const alreadyMapped = Boolean(field.value && mappedFields.has(field.value) && currentMapping !== field.value)
                            return (
                              <option key={field.value} value={field.value} disabled={alreadyMapped}>
                                {t(field.labelKey)}
                              </option>
                            )
                          })}
                          <option disabled>──────────</option>
                          <option value={`custom_fields.${header.toLowerCase().replace(/\s+/g, '_')}`}>
                            {t('playbooks.import_leads_ui.custom_field', { field: header })}
                          </option>
                        </select>

                        {currentMapping && <Check className="h-4 w-4 text-[var(--success)]" />}
                      </div>
                    )
                  })}
                </div>

                {!hasEmailMapping && (
                  <div className="flex items-center gap-2 text-sm text-[var(--error)]">
                    <AlertCircle className="h-4 w-4" />
                    {t('admin.lead_imports.preview.email_required')}
                  </div>
                )}

                <div className="rounded-lg border border-[var(--border)] p-4">
                  <div className="mb-2 flex items-center gap-2 text-sm font-medium text-[var(--foreground)]">
                    <FileText className="h-4 w-4" />
                    {t('playbooks.import_leads_ui.import_analysis')}
                  </div>

                  {isAnalyzing && (
                    <p className="text-sm text-[var(--foreground-muted)] inline-flex items-center gap-2">
                      <Loader className="h-4 w-4 animate-spin" />
                      {t('playbooks.import_leads_ui.analyzing')}
                    </p>
                  )}

                  {analysisError && <p className="text-sm text-[var(--error)]">{analysisError}</p>}

                  {analysisResult && !isAnalyzing && (
                    <p className="text-sm text-[var(--foreground-muted)]">
                      {t('playbooks.import_leads_ui.analysis_summary', {
                        new_people: analysisResult.summary.new_person_count,
                        new_leads: analysisResult.summary.new_lead_count,
                        lead_updates: analysisResult.summary.update_lead_count,
                        invalid: analysisResult.summary.invalid_count
                      })}
                    </p>
                  )}
                </div>

                <div className="flex items-center justify-between">
                  <Button variant="secondary" onClick={() => setStep(1)}>
                    {t('playbooks.import_leads_ui.back')}
                  </Button>

                  <Button onClick={handleCreateImport} disabled={!hasEmailMapping || isSubmitting}>
                    {isSubmitting ? t('playbooks.import_leads_ui.starting_import') : t('admin.lead_imports.preview.start_import')}
                  </Button>
                </div>
              </>
            )}

            {formError && (
              <div className="flex items-center gap-2 text-sm text-[var(--error)]">
                <AlertCircle className="h-4 w-4" />
                {formError}
              </div>
            )}
          </CardContent>
        </Card>
      </div>
    </PlaybookLayout>
  )
}
