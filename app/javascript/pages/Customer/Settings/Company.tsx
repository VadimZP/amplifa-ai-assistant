import { useForm, usePage } from '@inertiajs/react'
import { Building2, Calendar, DollarSign, Globe, Info } from 'lucide-react'
import { Badge } from '../../../components/ui/Badge'
import { Button } from '../../../components/ui/Button'
import { Card, CardContent, CardHeader } from '../../../components/ui/Card'
import { Input } from '../../../components/ui/Input'
import SettingsLayout from '../../../layouts/SettingsLayout'
import { t } from '../../../lib/i18n'

interface Organization {
  id: number
  name: string
  website?: string
  average_contract_value?: number
  monthly_subscription?: number
  calendly_url?: string
  currency?: string
  locale?: string
}

interface CompanyProps {
  organization: Organization
  canEdit: boolean
  currencies: string[]
  errors?: Record<string, string[]>
}

interface SharedProps {
  [key: string]: unknown
  flash?: {
    notice?: string
    alert?: string
  }
}

export default function Company({ organization, canEdit, currencies, errors }: CompanyProps) {
  const { flash } = usePage<SharedProps>().props

  const { data, setData, patch, processing, isDirty } = useForm({
    organization: {
      website: organization.website || '',
      average_contract_value: organization.average_contract_value?.toString() || '',
      calendly_url: organization.calendly_url || '',
      currency: organization.currency || currencies[0] || 'EUR'
    }
  })

  const submit = (event: React.FormEvent) => {
    event.preventDefault()
    if (!canEdit) return

    patch('/settings/company', {
      preserveScroll: true
    })
  }

  return (
    <SettingsLayout currentTab="company">
      <div className="space-y-6 max-w-4xl">
        <div className="rounded-lg border border-[var(--accent)]/25 bg-[var(--accent)]/10 p-4">
          <div className="flex items-start gap-3">
            <Info className="h-5 w-5 text-[var(--accent)] mt-0.5" />
            <div className="text-sm text-[var(--accent)]">
              {canEdit
                ? t('customer_settings.company.editable_notice')
                : t('customer_settings.company.readonly_notice')}
            </div>
          </div>
        </div>

        <Card>
          <CardHeader>
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-3">
                <div className="h-10 w-10 rounded-lg bg-[var(--accent)]/10 flex items-center justify-center">
                  <Building2 className="h-5 w-5 text-[var(--accent)]" />
                </div>
                <div>
                  <div className="text-lg font-semibold text-[var(--foreground)]">{t('customer_settings.company.title')}</div>
                  <div className="text-sm text-[var(--foreground-muted)]">{t('customer_settings.company.description')}</div>
                </div>
              </div>
              {canEdit ? <Badge variant="success">{t('customer_settings.company.editable')}</Badge> : <Badge variant="default">{t('customer_settings.company.read_only')}</Badge>}
            </div>
          </CardHeader>
          <CardContent>
            <form onSubmit={submit} className="space-y-6">
              <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                <Input
                  label={t('customer_settings.company.organization_name')}
                  value={organization.name}
                  onChange={() => {}}
                  disabled
                />

                <div className="space-y-2">
                  <label htmlFor="company-currency" className="block text-sm font-medium text-[var(--foreground)]">
                    {t('customer_settings.company.currency')}
                  </label>
                  <select
                    id="company-currency"
                    value={data.organization.currency}
                    disabled={!canEdit}
                    onChange={(event) => setData('organization', { ...data.organization, currency: event.target.value })}
                    className="block w-full px-3 py-2.5 bg-[var(--input)] border border-[var(--input-border)] rounded-lg text-[var(--foreground)] text-sm focus:outline-none focus:ring-2 focus:ring-[var(--ring)]"
                  >
                    {currencies.map((currency) => (
                      <option key={currency} value={currency}>{currency}</option>
                    ))}
                  </select>
                  {errors?.currency && <p className="text-sm text-[var(--error)]">{errors.currency[0]}</p>}
                </div>

                <Input
                  label={t('customer_settings.company.website')}
                  value={data.organization.website}
                  icon={<Globe className="h-4 w-4" />}
                  onChange={(event) => setData('organization', { ...data.organization, website: event.target.value })}
                  disabled={!canEdit}
                  error={errors?.website?.[0]}
                  placeholder={t('customer_settings.company.website_placeholder')}
                />

                <Input
                  label={t('customer_settings.company.calendly_url')}
                  value={data.organization.calendly_url}
                  icon={<Calendar className="h-4 w-4" />}
                  onChange={(event) => setData('organization', { ...data.organization, calendly_url: event.target.value })}
                  disabled={!canEdit}
                  error={errors?.calendly_url?.[0]}
                  placeholder={t('customer_settings.company.calendly_placeholder')}
                />

                <Input
                  label={t('customer_settings.company.average_contract_value')}
                  type="number"
                  value={data.organization.average_contract_value}
                  icon={<DollarSign className="h-4 w-4" />}
                  onChange={(event) => setData('organization', { ...data.organization, average_contract_value: event.target.value })}
                  disabled={!canEdit}
                  error={errors?.average_contract_value?.[0]}
                  placeholder="25000"
                />


              </div>

              {canEdit && (
                <div className="flex justify-end">
                  <Button type="submit" disabled={!isDirty || processing} loading={processing}>
                    {t('customer_settings.company.save')}
                  </Button>
                </div>
              )}

              {flash?.alert && (
                <p className="text-sm text-[var(--error)]">{flash.alert}</p>
              )}
            </form>
          </CardContent>
        </Card>
      </div>
    </SettingsLayout>
  )
}
