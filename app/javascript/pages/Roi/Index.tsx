import { useEffect, useState } from 'react'
import { usePage, router } from '@inertiajs/react'
import AuthenticatedLayout from '../../layouts/AuthenticatedLayout'
import { Card, CardContent } from '../../components/ui/Card'
import { Button } from '../../components/ui/Button'
import { Input } from '../../components/ui/Input'
import { toast } from '../../components/ui/Toaster'
import { t } from '../../lib/i18n'
import {
  Pencil,
  RefreshCw,
  X
} from 'lucide-react'

interface RoiProps {
  metrics: {
    roi_percentage: number
    positive_outcomes: number
    acv: number
    pipeline_revenue: number
    total_investment: number
    months_of_partnership: number
    leads_contacted: number
    emails_sent: number
    reply_rate: number
    meeting_rate: number
    emails_replied: number
    total_meetings: number
  }
  monthly_trends: Array<{
    month: string
    sent: number
    opened: number
    replied: number
    meetings: number
    positive_outcomes: number
  }>
  agents: Array<{ id: number; name: string }>
  current_agent_id: string
  currency: string
  can_edit_metrics: boolean
  errors?: Record<string, string[]>
}

interface SharedProps {
  [key: string]: unknown;
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
}

export default function Index({ metrics, monthly_trends, agents, current_agent_id, currency, can_edit_metrics, errors }: RoiProps) {
  const { auth, flash } = usePage<SharedProps>().props
  const { account, organization } = auth
  const [isEditModalOpen, setIsEditModalOpen] = useState(false)
  const [editingField, setEditingField] = useState<'acv' | null>(null)
  const [formValue, setFormValue] = useState('')
  const [isSaving, setIsSaving] = useState(false)
  const [fieldError, setFieldError] = useState<string | null>(null)

  useEffect(() => {
    if (flash?.notice) toast.success(flash.notice)
    if (flash?.alert) toast.error(flash.alert)
  }, [flash?.notice, flash?.alert])

  // Format currency
  const formatCurrency = (value: number) => {
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: currency || 'USD',
      notation: 'compact',
      maximumFractionDigits: 1
    }).format(value)
  }

  // Format number
  const formatNumber = (value: number) => {
    return new Intl.NumberFormat('en-US').format(value)
  }

  // Format percentage
  const formatPercent = (value: number) => {
    return `${value}%`
  }

  const handleAgentChange = (e: React.ChangeEvent<HTMLSelectElement>) => {
    router.get('/roi', { agent_id: e.target.value }, { preserveState: true })
  }

  const handleRefresh = () => {
    router.reload()
  }

  const openEditModal = () => {
    setEditingField('acv')
    setFormValue(String(metrics?.acv || 0))
    setFieldError(null)
    setIsEditModalOpen(true)
  }

  const closeEditModal = () => {
    setIsEditModalOpen(false)
    setEditingField(null)
    setFormValue('')
    setFieldError(null)
  }

  const submitMetricUpdate = (e: React.FormEvent) => {
    e.preventDefault()
    if (!editingField) return

    const organizationPayload = { average_contract_value: formValue || null }

    setIsSaving(true)
    setFieldError(null)

    router.patch('/roi', { organization: organizationPayload }, {
      preserveScroll: true,
      preserveState: true,
      onSuccess: () => {
        closeEditModal()
      },
      onError: (formErrors) => {
        const errorKey = 'average_contract_value'
        const rawError = formErrors[errorKey]
        if (Array.isArray(rawError)) {
          setFieldError(rawError[0] || null)
        } else if (typeof rawError === 'string') {
          setFieldError(rawError)
        } else {
          setFieldError(null)
        }
      },
      onFinish: () => {
        setIsSaving(false)
      }
    })
  }

  const stickyNavigation = (
    <div className="flex flex-col justify-between gap-4 py-3 sm:flex-row sm:items-center">
      <div className="flex items-center gap-4">
        <div className="relative">
          <select
            value={current_agent_id || 'all'}
            onChange={handleAgentChange}
            className="appearance-none rounded-xl border border-[var(--input-border)] bg-[var(--input)] py-2.5 pl-3.5 pr-9 text-sm text-[var(--foreground)] shadow-[inset_0_1px_0_rgba(255,255,255,0.03)] focus:outline-none focus:ring-2 focus:ring-[var(--accent)]"
          >
            <option value="all">{t('roi.filter_all')}</option>
            {agents?.map(agent => (
              <option key={agent.id} value={agent.id}>{agent.name}</option>
            ))}
          </select>
          <div className="pointer-events-none absolute inset-y-0 right-0 flex items-center px-2 text-[var(--foreground-subtle)]">
            <svg aria-hidden="true" focusable="false" className="h-4 w-4 fill-current" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20">
              <path d="M9.293 12.95l.707.707L15.657 8l-1.414-1.414L10 10.828 5.757 6.586 4.343 8z" />
            </svg>
          </div>
        </div>
      </div>

      <Button variant="secondary" size="sm" icon={<RefreshCw className="h-3.5 w-3.5" />} onClick={handleRefresh}>
        {t('roi.refresh')}
      </Button>
    </div>
  )

  // Sparkline components
  const BarSparkline = () => {
    if (!monthly_trends || monthly_trends.length === 0) return null;
    const maxVal = Math.max(...monthly_trends.map(d => d.positive_outcomes || 0), 1);
    return (
      <div className="h-16 w-full flex items-end gap-1 mt-4">
        {monthly_trends.map(d => {
          const height = Math.max((d.positive_outcomes / maxVal) * 100, 4);
          return (
            <div key={d.month} className="flex-1 bg-[var(--accent)]/20 rounded-t-sm relative group">
              <div 
                className="absolute bottom-0 left-0 right-0 bg-[var(--accent)] rounded-t-sm transition-all duration-300"
                style={{ height: `${height}%` }}
              />
            </div>
          );
        })}
      </div>
    );
  };

  const AreaSparkline = ({ data, colorClass, fillClass }: { data: number[], colorClass: string, fillClass: string }) => {
    if (!data || data.length === 0) return null;
    const max = Math.max(...data, 1);
    const min = Math.min(...data, 0);
    const range = max - min || 1;
    
    const points = data.map((val, i) => {
      const x = data.length > 1 ? (i / (data.length - 1)) * 100 : 50;
      const y = 100 - ((val - min) / range) * 100;
      return `${x},${y}`;
    }).join(' ');

    const areaPoints = `0,100 ${points} 100,100`;

    return (
      <svg aria-hidden="true" focusable="false" className="w-full h-10 mt-2 overflow-visible" preserveAspectRatio="none" viewBox="0 0 100 100">
        <polygon points={areaPoints} className={fillClass} />
        <polyline points={points} fill="none" className={colorClass} strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" />
      </svg>
    );
  };

  const LineSparkline = ({ data, colorClass }: { data: number[], colorClass: string }) => {
    if (!data || data.length === 0) return null;
    const max = Math.max(...data, 1);
    const min = Math.min(...data, 0);
    const range = max - min || 1;
    
    const points = data.map((val, i) => {
      const x = data.length > 1 ? (i / (data.length - 1)) * 100 : 50;
      const y = 100 - ((val - min) / range) * 100;
      return `${x},${y}`;
    }).join(' ');

    return (
      <svg aria-hidden="true" focusable="false" className="w-full h-10 mt-2 overflow-visible" preserveAspectRatio="none" viewBox="0 0 100 100">
        <polyline points={points} fill="none" className={colorClass} strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" />
        {data.map((val, i) => {
          const x = data.length > 1 ? (i / (data.length - 1)) * 100 : 50;
          const y = 100 - ((val - min) / range) * 100;
          return <circle key={`${x}-${val}`} cx={x} cy={y} r="2" className={colorClass} fill="currentColor" />;
        })}
      </svg>
    );
  };

  // Extract trend data for sparklines
  const revenueData = monthly_trends?.map(d => d.meetings * (metrics?.acv || 0)) || [0, 0, 0, 0, 0, 0];
  const acvData = monthly_trends?.map(() => metrics?.acv || 0) || [0, 0, 0, 0, 0, 0]; // Flat line for ACV

  const investmentData = monthly_trends?.map(() => (metrics?.total_investment || 0) / (metrics?.months_of_partnership || 1)) || [0, 0, 0, 0, 0, 0];

  return (
    <AuthenticatedLayout
      title={t('roi.title')}
      subtitle={t('roi.subtitle')}
      account={account}
      organization={organization}
      flash={flash}
      stickyNavigation={stickyNavigation}
    >
      <div className="space-y-6">
          <div className="grid grid-cols-1 md:grid-cols-12 gap-6">
            {/* Amplifa ROI */}
            <Card className="!py-0 md:col-span-6 lg:col-span-6 lg:row-span-2">
              <CardContent className="p-6 flex flex-col h-full justify-between">
                <div>
                  <p className="text-sm font-medium text-[var(--foreground-muted)]">
                    {t('roi.metrics.amplifa_roi')}
                  </p>
                  <div className="mt-2 flex items-baseline gap-3">
                    <span className="text-5xl font-bold text-white tabular-nums">
                      {formatNumber(metrics?.roi_percentage || 0)}%
                    </span>
                  </div>
                </div>
                <BarSparkline />
              </CardContent>
            </Card>

            {/* Average Contract Value */}
            <Card className="!py-0 md:col-span-6 lg:col-span-6">
              <CardContent className="p-6 flex flex-col h-full justify-between">
                <div>
                  <div className="flex items-center justify-between gap-2">
                    <p className="text-sm font-medium text-[var(--foreground-muted)]">
                      {t('roi.metrics.acv')}
                    </p>
                    {can_edit_metrics && (
                      <Button
                        type="button"
                        variant="ghost"
                        size="sm"
                        className="h-7 w-7 p-0"
                        onClick={() => openEditModal()}
                        aria-label={t('roi.metrics.edit_acv')}
                        icon={<Pencil className="h-3.5 w-3.5" />}
                      />
                    )}
                  </div>
                  <p className="mt-2 text-4xl font-bold text-emerald-400 tabular-nums">
                    {formatCurrency(metrics?.acv || 0)}
                  </p>
                </div>
                <LineSparkline data={acvData} colorClass="stroke-emerald-400/50 text-emerald-400/50" />
              </CardContent>
            </Card>

            {/* Pipeline Revenue Driven */}
            <Card className="!py-0 md:col-span-6 lg:col-span-3">
              <CardContent className="p-6 flex flex-col h-full justify-between">
                <div>
                  <p className="text-sm font-medium text-[var(--foreground-muted)]">
                    {t('roi.metrics.pipeline_revenue')}
                  </p>
                  <p className="mt-2 text-4xl font-bold text-white tabular-nums">
                    {formatCurrency(metrics?.pipeline_revenue || 0)}
                  </p>
                </div>
                <AreaSparkline data={revenueData} colorClass="stroke-emerald-400" fillClass="fill-emerald-400/20" />
              </CardContent>
            </Card>

            {/* Total Amplifa Investment */}
            <Card className="!py-0 md:col-span-6 lg:col-span-3">
              <CardContent className="p-6 flex flex-col h-full justify-between">
                <div>
                  <p className="text-sm font-medium text-[var(--foreground-muted)]">
                    {t('roi.metrics.total_investment')}
                  </p>
                  <p className="mt-2 text-4xl font-bold text-red-400 tabular-nums">
                    {formatCurrency(metrics?.total_investment || 0)}
                  </p>
                  <p className="mt-1 text-xs text-[var(--foreground-muted)]">
                    {t('roi.metrics.across_months', { count: metrics?.months_of_partnership || 0 })}
                  </p>
                </div>
                <LineSparkline data={investmentData} colorClass="stroke-red-400/50 text-red-400/50" />
              </CardContent>
            </Card>
          </div>

          {/* Row 3: Stats Bar */}
          <div className="grid grid-cols-2 lg:grid-cols-6 gap-4">
            <Card className="!py-0">
              <CardContent className="p-5">
                <p className="text-sm text-[var(--foreground-muted)]">
                  Leads Contacted
                </p>
                <p className="mt-1 text-2xl font-bold text-white tabular-nums">
                  {formatNumber(metrics?.leads_contacted || 0)}
                </p>
              </CardContent>
            </Card>
            <Card className="!py-0">
              <CardContent className="p-5">
                <p className="text-sm text-[var(--foreground-muted)]">
                  {t('roi.metrics.emails_sent')}
                </p>
                <p className="mt-1 text-2xl font-bold text-white tabular-nums">
                  {formatNumber(metrics?.emails_sent || 0)}
                </p>
              </CardContent>
            </Card>
            <Card className="!py-0">
              <CardContent className="p-5">
                <p className="text-sm text-[var(--foreground-muted)]">
                  {t('roi.metrics.reply_rate')}
                </p>
                <p className="mt-1 text-2xl font-bold text-white tabular-nums">
                  {formatPercent(metrics?.reply_rate || 0)}
                </p>
              </CardContent>
            </Card>
            <Card className="!py-0">
              <CardContent className="p-5">
                <p className="text-sm text-[var(--foreground-muted)]">
                  {t('roi.metrics.meeting_rate')}
                </p>
                <p className="mt-1 text-2xl font-bold text-white tabular-nums">
                  {formatPercent(metrics?.meeting_rate || 0)}
                </p>
              </CardContent>
            </Card>
            <Card className="!py-0">
              <CardContent className="p-5">
                <p className="text-sm text-[var(--foreground-muted)]">
                  {t('roi.funnel.meetings')}
                </p>
                <p className="mt-1 text-2xl font-bold text-white tabular-nums">
                  {formatNumber(metrics?.total_meetings || 0)}
                </p>
              </CardContent>
            </Card>
            <Card className="!py-0">
              <CardContent className="p-5">
                <p className="text-sm text-[var(--foreground-muted)]">
                  {t('roi.metrics.positive_outcomes')}
                </p>
                <p className="mt-1 text-2xl font-bold text-white tabular-nums">
                  {formatNumber(metrics?.positive_outcomes || 0)}
                </p>
              </CardContent>
            </Card>
          </div>
      </div>

      {isEditModalOpen && editingField && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm p-4 animate-in fade-in duration-200">
          <div className="bg-[var(--card)] border border-[var(--border)] rounded-2xl max-w-md w-full p-6 shadow-2xl">
            <div className="flex items-center justify-between mb-4">
              <h2 className="text-xl font-semibold text-[var(--foreground)]">
                {t('roi.metrics.edit_acv')}
              </h2>
              <Button
                type="button"
                variant="ghost"
                size="sm"
                className="h-8 w-8 p-0"
                onClick={closeEditModal}
                aria-label={t('common.cancel')}
                icon={<X className="h-4 w-4" />}
              />
            </div>

            <form onSubmit={submitMetricUpdate} className="space-y-4">
              <Input
                type="number"
                step="0.01"
                min="0"
                label={t('roi.metrics.acv')}
                value={formValue}
                onChange={e => setFormValue(e.target.value)}
                error={fieldError || errors?.average_contract_value}
              />

              <div className="flex items-center justify-end gap-2 pt-2">
                <Button type="button" variant="ghost" size="sm" onClick={closeEditModal}>
                  {t('common.cancel')}
                </Button>
                <Button type="submit" size="sm" loading={isSaving}>
                  {t('common.save')}
                </Button>
              </div>
            </form>
          </div>
        </div>
      )}
    </AuthenticatedLayout>
  )
}
