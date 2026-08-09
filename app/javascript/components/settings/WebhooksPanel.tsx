import { router, useForm } from '@inertiajs/react'
import { Link2, Plus, Trash2, Webhook } from 'lucide-react'
import { Button } from '../ui/Button'
import { Card, CardContent, CardHeader } from '../ui/Card'
import { Input } from '../ui/Input'
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '../ui/Table'
import { t } from '../../lib/i18n'

interface WebhookEndpoint {
  id: number
  url: string
  active: boolean
}

interface WebhooksPanelProps {
  clickTrackingEnabled: boolean
  webhookEndpoints: WebhookEndpoint[]
  canManageWebhooks: boolean
  clickEvents?: ClickEvent[]
  clickEventsPagination?: ClickEventsPagination
  showClickEventsTable?: boolean
  errors?: Record<string, string[]>
  settingsPath: string
  endpointsPath: string
  endpointPath: (endpointId: number) => string
}

interface ClickEventsPagination {
  current_page: number
  total_pages: number
  total_count: number
  per_page: number
}

interface ClickEvent {
  id: number
  clicked_at: string
  target_url: string
  lead_email: string | null
  ip_address: string | null
  user_agent: string | null
  referrer: string | null
}

export default function WebhooksPanel({
  clickTrackingEnabled,
  webhookEndpoints,
  canManageWebhooks,
  clickEvents = [],
  clickEventsPagination,
  showClickEventsTable = false,
  errors,
  settingsPath,
  endpointsPath,
  endpointPath,
}: WebhooksPanelProps) {
  const { data, setData, patch, processing } = useForm({
    organization: {
      click_tracking_enabled: clickTrackingEnabled,
    },
  })

  const {
    data: endpointData,
    setData: setEndpointData,
    post,
    processing: endpointProcessing,
    reset,
  } = useForm({
    organization_webhook_endpoint: {
      url: '',
      active: true,
    },
  })

  const submitTrackingSettings = (event: React.FormEvent) => {
    event.preventDefault()
    patch(settingsPath, { preserveScroll: true })
  }

  const submitEndpoint = (event: React.FormEvent) => {
    event.preventDefault()
    post(endpointsPath, {
      preserveScroll: true,
      onSuccess: () => {
        reset('organization_webhook_endpoint')
        setEndpointData('organization_webhook_endpoint', { url: '', active: true })
      },
    })
  }

  const toggleEndpoint = (endpoint: WebhookEndpoint) => {
    if (!canManageWebhooks) return

    router.patch(
      endpointPath(endpoint.id),
      {
        organization_webhook_endpoint: {
          url: endpoint.url,
          active: !endpoint.active,
        },
      },
      { preserveScroll: true }
    )
  }

  const removeEndpoint = (endpointId: number) => {
    if (!canManageWebhooks) return
    if (!confirm(t('customer_settings.webhooks.remove_confirm'))) return

    router.delete(endpointPath(endpointId), {
      preserveScroll: true,
    })
  }

  const formatDateTime = (value: string) => {
    return new Date(value).toLocaleDateString('en-US', {
      year: 'numeric',
      month: 'short',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
    })
  }

  const goToClickEventsPage = (page: number) => {
    router.get(settingsPath, { events_page: page }, { preserveState: true, preserveScroll: true })
  }

  return (
    <div className="space-y-8 max-w-5xl">
      <div id="tracking" className="scroll-mt-8">
        <Card>
          <CardHeader>
            <div className="flex items-center gap-3">
              <div className="h-10 w-10 rounded-lg bg-[var(--accent)]/10 flex items-center justify-center">
                <Link2 className="h-5 w-5 text-[var(--accent)]" />
              </div>
              <div>
                <div className="text-lg font-semibold text-[var(--foreground)]">{t('customer_settings.webhooks.click_tracking.title')}</div>
                <div className="text-sm text-[var(--foreground-muted)]">
                  {t('customer_settings.webhooks.click_tracking.description')}
                </div>
              </div>
            </div>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="rounded-lg border border-dashed border-[var(--border)] px-4 py-3">
              <div className="text-xs font-medium text-[var(--foreground-muted)] mb-1.5">{t('customer_settings.webhooks.click_tracking.example')}</div>
              <div className="font-mono text-xs leading-relaxed">
                <span className="text-[var(--foreground-muted)]">https://example.com/pricing</span>
                <br />
                <span className="text-[var(--foreground-muted)]">&rarr; https://app.amplifa.ai/s/a1b2c3d4-e5f6-&hellip;</span>
              </div>
            </div>

            <form onSubmit={submitTrackingSettings} className="space-y-4">
              <label className="flex items-center gap-3 rounded-lg border border-[var(--border)] px-4 py-3">
                <input
                  type="checkbox"
                  checked={data.organization.click_tracking_enabled}
                  disabled={!canManageWebhooks || processing}
                  onChange={(event) => {
                    setData('organization', {
                      click_tracking_enabled: event.target.checked,
                    })
                  }}
                />
                <span className="text-sm text-[var(--foreground)]">{t('customer_settings.webhooks.click_tracking.enable')}</span>
              </label>

              {!canManageWebhooks && (
                <p className="text-sm text-[var(--foreground-muted)]">{t('customer_settings.webhooks.only_authorized')}</p>
              )}

              <div className="flex justify-end">
                <Button type="submit" disabled={!canManageWebhooks || processing}>
                  {t('customer_settings.common.save_settings')}
                </Button>
              </div>
            </form>
          </CardContent>
        </Card>
      </div>

      <div id="endpoints" className="scroll-mt-8">
        <Card>
          <CardHeader>
            <div className="flex items-center gap-3">
              <div className="h-10 w-10 rounded-lg bg-[var(--accent)]/10 flex items-center justify-center">
                <Webhook className="h-5 w-5 text-[var(--accent)]" />
              </div>
              <div>
                <div className="text-lg font-semibold text-[var(--foreground)]">{t('customer_settings.webhooks.endpoints.title')}</div>
                <div className="text-sm text-[var(--foreground-muted)]">
                  Add one or more HTTPS endpoints to receive click events.
                </div>
              </div>
            </div>
          </CardHeader>
          <CardContent className="space-y-6">
            <form onSubmit={submitEndpoint} className="space-y-4">
              <Input
                label="Endpoint URL"
                type="url"
                placeholder="https://example.com/webhooks/amplifa"
                value={endpointData.organization_webhook_endpoint.url}
                disabled={!canManageWebhooks || endpointProcessing}
                onChange={(event) => {
                  setEndpointData('organization_webhook_endpoint', {
                    ...endpointData.organization_webhook_endpoint,
                    url: event.target.value,
                  })
                }}
                error={errors?.url?.[0]}
              />

              <div className="flex justify-end">
                <Button type="submit" disabled={!canManageWebhooks || endpointProcessing}>
                  <Plus className="h-4 w-4" />
                  Add endpoint
                </Button>
              </div>
            </form>

            <div className="space-y-2">
              {webhookEndpoints.length === 0 ? (
                <div className="text-sm text-[var(--foreground-muted)]">No webhook endpoints configured yet.</div>
              ) : (
                webhookEndpoints.map((endpoint) => (
                  <div
                    key={endpoint.id}
                    className="rounded-lg border border-[var(--border)] px-4 py-3 flex items-center justify-between gap-3"
                  >
                    <div>
                      <div className="text-sm font-medium text-[var(--foreground)] break-all">{endpoint.url}</div>
                      <div className="text-xs text-[var(--foreground-muted)]">
                        Status: {endpoint.active ? 'Active' : 'Disabled'}
                      </div>
                    </div>

                    <div className="flex items-center gap-2">
                      <Button
                        type="button"
                        size="sm"
                        variant="secondary"
                        disabled={!canManageWebhooks}
                        onClick={() => toggleEndpoint(endpoint)}
                      >
                        {endpoint.active ? 'Disable' : 'Enable'}
                      </Button>
                      <Button
                        type="button"
                        size="sm"
                        variant="secondary"
                        disabled={!canManageWebhooks}
                        onClick={() => removeEndpoint(endpoint.id)}
                      >
                        <Trash2 className="h-4 w-4" />
                        Remove
                      </Button>
                    </div>
                  </div>
                ))
              )}
            </div>
          </CardContent>
        </Card>
      </div>

      {showClickEventsTable && (
        <div id="events" className="scroll-mt-8">
          <Card>
            <CardHeader>
              <div className="text-lg font-semibold text-[var(--foreground)]">{t('customer_settings.webhooks.events.title')}</div>
              <div className="text-sm text-[var(--foreground-muted)]">{t('customer_settings.webhooks.events.description')}</div>
            </CardHeader>
            <CardContent>
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>{t('customer_settings.webhooks.events.table.clicked_at')}</TableHead>
                    <TableHead>{t('customer_settings.webhooks.events.table.lead')}</TableHead>
                    <TableHead>{t('customer_settings.webhooks.events.table.target_url')}</TableHead>
                    <TableHead>IP</TableHead>
                    <TableHead>{t('customer_settings.webhooks.events.table.referrer')}</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {clickEvents.length === 0 ? (
                    <TableRow>
                      <TableCell colSpan={5} className="text-sm text-[var(--foreground-muted)] text-center py-6">
                        {t('customer_settings.webhooks.events.empty')}
                      </TableCell>
                    </TableRow>
                  ) : (
                    clickEvents.map((event) => (
                      <TableRow key={event.id}>
                        <TableCell>{formatDateTime(event.clicked_at)}</TableCell>
                        <TableCell>{event.lead_email || '—'}</TableCell>
                        <TableCell className="max-w-[28rem] break-all">{event.target_url}</TableCell>
                        <TableCell>{event.ip_address || '—'}</TableCell>
                        <TableCell className="max-w-[20rem] break-all">{event.referrer || '—'}</TableCell>
                      </TableRow>
                    ))
                  )}
                </TableBody>
              </Table>

              {clickEventsPagination && (
                <div className="mt-4 flex items-center justify-between">
                  <div className="text-xs text-[var(--foreground-muted)]">
                    {clickEventsPagination.total_count} events • Page {clickEventsPagination.current_page} of {clickEventsPagination.total_pages}
                  </div>
                  {clickEventsPagination.total_pages > 1 && (
                    <div className="flex items-center gap-2">
                      <Button
                        type="button"
                        variant="secondary"
                        size="sm"
                        onClick={() => goToClickEventsPage(clickEventsPagination.current_page - 1)}
                        disabled={clickEventsPagination.current_page <= 1}
                      >
                        Previous
                      </Button>
                      <Button
                        type="button"
                        variant="secondary"
                        size="sm"
                        onClick={() => goToClickEventsPage(clickEventsPagination.current_page + 1)}
                        disabled={clickEventsPagination.current_page >= clickEventsPagination.total_pages}
                      >
                        Next
                      </Button>
                    </div>
                  )}
                </div>
              )}
            </CardContent>
          </Card>
        </div>
      )}
    </div>
  )
}
