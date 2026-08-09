
import { router } from '@inertiajs/react';
import { Card, CardHeader, CardContent } from '../../../components/ui/Card';
import { Button } from '../../../components/ui/Button';
import { Badge } from '../../../components/ui/Badge';
import SettingsLayout from '../../../layouts/SettingsLayout';
import { Sparkles, Calendar, AlertTriangle, Zap, Crown, CheckCircle2 } from 'lucide-react';
import { t } from '../../../lib/i18n';

interface BillingProps {
  organization: {
    id: number;
    name: string;
    monthly_subscription?: number;
    currency?: string;
    plan_tier?: string;
    monthly_meeting_limit?: number;
  };
  available_plans?: {
    identifier: string;
    name: string;
    monthly_meeting_limit: number;
    monthly_price: number;
  }[];
  current_plan?: {
    identifier: string;
    name: string;
    monthly_meeting_limit: number;
    monthly_price: number;
  } | null;
  billing_cycle_day?: number;
  billing_cycle_next_renewal_on?: string;
  billing_cycle_meeting_limit?: number;
  billing_cycle_meetings_count?: number;
  buying_signals_monthly_price?: number;
}

export default function Billing({
  organization,
  available_plans = [],
  current_plan,
  billing_cycle_day = 1,
  billing_cycle_next_renewal_on,
  billing_cycle_meeting_limit = 5,
  billing_cycle_meetings_count = 0,
  buying_signals_monthly_price = 999,
}: BillingProps) {
  const sidebarSections = [
    { id: 'billing', label: t('customer_settings.tabs.billing') }
  ];

  const usagePercent = Math.min((billing_cycle_meetings_count / billing_cycle_meeting_limit) * 100, 100);
  const renewalDateLabel = billing_cycle_next_renewal_on
    ? new Date(billing_cycle_next_renewal_on).toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' })
    : null;

  const selectedPlan = current_plan || available_plans.find(plan => plan.identifier === organization.plan_tier) || available_plans[0]
  const currencySymbol = organization.currency === 'USD' ? '$' : organization.currency === 'GBP' ? '£' : organization.currency === 'CHF' ? 'CHF ' : '€'
  const currentMonthlyPrice = organization.monthly_subscription ?? selectedPlan?.monthly_price ?? 0
  const enterpriseFeatures = [
    t('customer_settings.billing.enterprise_features.unlimited_appointments'),
    t('customer_settings.billing.enterprise_features.custom_integrations'),
    t('customer_settings.billing.enterprise_features.sla_guarantee'),
    t('customer_settings.billing.enterprise_features.dedicated_support_team'),
  ]
  const buyingSignalsFeatures = [
    t('customer_settings.billing.buying_signals_features.live_intent_signals'),
    t('customer_settings.billing.buying_signals_features.job_change_funding_trigger'),
    t('customer_settings.billing.buying_signals_features.tech_stack_hiring_signals'),
    t('customer_settings.billing.buying_signals_features.automatic_workflow_trigger'),
  ]

  const notifyBillingInterest = (
    actionName:
      | 'get_10_more_meetings'
      | 'upgrade_plan'
      | 'upgrade_to_annual'
      | 'upgrade_to_growth'
      | 'upgrade_to_scale'
      | 'upgrade_for_buying_signals'
      | 'contact_sales_enterprise_plan'
      | 'contact_sales'
  ) => {
    router.post('/settings/billing/notify_interest', {
      action_name: actionName,
    }, {
      preserveScroll: true,
    });
  };

  return (
    <SettingsLayout currentTab="billing" sidebarSections={sidebarSections}>
      <div className="space-y-8">
        {/* Section 1: AI Intelligence Alert Banner */}
        <div id="billing">
          <Card className="border-amber-500/30 bg-amber-500/5">
            <CardHeader>
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-3">
                  <div className="h-10 w-10 rounded-lg bg-gradient-to-br from-amber-500 to-orange-500 flex items-center justify-center">
                    <Sparkles className="h-5 w-5 text-white" />
                  </div>
                  <div className="flex items-center gap-3">
                    <div className="text-lg font-semibold text-[var(--foreground)]">{t('customer_settings.billing.ai_intelligence')}</div>
                  </div>
                </div>
                <div className="flex items-center gap-2 text-[var(--foreground-muted)]">
                  <span className="text-sm font-medium">{t('customer_settings.billing.day', { day: billing_cycle_day })}</span>
                  <Calendar className="h-4 w-4" />
                </div>
              </div>
            </CardHeader>
            <CardContent>
              <div className="space-y-4">
                <div className="bg-amber-500/10 border border-amber-500/20 rounded-lg p-3 flex items-start gap-3">
                  <AlertTriangle className="h-5 w-5 text-amber-500 shrink-0 mt-0.5" />
                  <div>
                    <div className="text-sm font-medium text-amber-500">{t('customer_settings.billing.usage_alert', { used: billing_cycle_meetings_count, limit: billing_cycle_meeting_limit })}</div>
                    <div className="text-sm text-amber-500/80">
                      {renewalDateLabel ? t('customer_settings.billing.reset_on', { date: renewalDateLabel }) : t('customer_settings.billing.reset_next_cycle')}
                    </div>
                  </div>
                </div>
                
                <div className="bg-white/[0.03] border border-[var(--border)] rounded-lg p-4 flex flex-col sm:flex-row sm:items-center justify-between gap-4">
                  <div className="flex items-center gap-3">
                    <div className="h-8 w-8 rounded-full bg-[var(--accent)]/10 flex items-center justify-center">
                      <Zap className="h-4 w-4 text-[var(--accent)]" />
                    </div>
                    <div className="text-sm font-medium text-[var(--foreground)]">{t('customer_settings.billing.need_more')}</div>
                  </div>
                  <div className="flex items-center gap-3">
                    <Button
                      variant="secondary"
                      size="sm"
                      onClick={() => notifyBillingInterest('get_10_more_meetings')}
                    >
                      {t('customer_settings.billing.get_more')}
                    </Button>
                    <Button
                      variant="secondary"
                      size="sm"
                      onClick={() => notifyBillingInterest('upgrade_plan')}
                    >
                      {t('customer_settings.billing.upgrade_plan')}
                    </Button>
                  </div>
                </div>
              </div>
            </CardContent>
          </Card>
        </div>

        {/* Section 2: Current Plan Card */}
        <Card>
          <CardHeader>
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-3">
                <div className="h-10 w-10 rounded-lg bg-[var(--accent)]/10 flex items-center justify-center">
                  <Crown className="h-5 w-5 text-[var(--accent)]" />
                </div>
                <div>
                  <div className="flex items-center gap-2">
                    <div className="text-lg font-semibold text-[var(--foreground)]">{t('customer_settings.billing.current_plan')}</div>
                    <Badge variant="success">{t('customer_settings.billing.active')}</Badge>
                  </div>
                  <div className="text-sm text-[var(--foreground-muted)]">{t('customer_settings.billing.current_plan_description')}</div>
                </div>
              </div>
            </div>
          </CardHeader>
          <CardContent>
            <div className="space-y-6">
              <div className="flex items-end justify-between">
                <div>
                  <div className="text-3xl font-bold text-[var(--foreground)]">{selectedPlan?.name || t('customer_settings.billing.plan')}</div>
                  <div className="text-sm text-[var(--foreground-muted)] mt-1">{currencySymbol}{currentMonthlyPrice}{t('customer_settings.billing.per_month')}</div>
                </div>
                <Button
                  variant="secondary"
                  size="sm"
                  onClick={() => notifyBillingInterest('upgrade_to_annual')}
                >
                  {t('customer_settings.billing.upgrade_annual')}
                </Button>
              </div>

              <div className="space-y-2">
                <div className="flex items-center justify-between text-sm">
                  <span className="text-[var(--foreground-muted)]">{t('customer_settings.billing.meetings_usage')}</span>
                  <span className="font-medium text-[var(--foreground)]">{t('customer_settings.billing.meetings_usage_count', { used: billing_cycle_meetings_count, limit: billing_cycle_meeting_limit })}</span>
                </div>
                <div className="w-full bg-[var(--secondary)] rounded-full h-2 overflow-hidden">
                  <div className="bg-[var(--accent)] h-full rounded-full" style={{ width: `${usagePercent}%` }}></div>
                </div>
                <div className="text-xs text-[var(--foreground-muted)] text-right">
                  {renewalDateLabel ? t('customer_settings.billing.renews_on', { date: renewalDateLabel }) : t('customer_settings.billing.renewal_unavailable')}
                </div>
              </div>
            </div>
          </CardContent>
        </Card>

        {/* Section 3: Update Plan */}
        <Card>
          <CardHeader>
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-3">
                <div className="h-10 w-10 rounded-lg bg-white/5 flex items-center justify-center">
                  <Crown className="h-5 w-5 text-[var(--foreground-muted)]" />
                </div>
                <div>
                  <div className="text-lg font-semibold text-[var(--foreground)]">{t('customer_settings.billing.update_plan')}</div>
                  <div className="text-sm text-[var(--foreground-muted)]">{t('customer_settings.billing.update_plan_description')}</div>
                </div>
              </div>
            </div>
          </CardHeader>
          <CardContent>
            <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-4 gap-4">
              {available_plans.map((plan) => {
                const isCurrentPlan = plan.identifier === organization.plan_tier
                const actionName = plan.identifier === 'growth'
                  ? 'upgrade_to_growth'
                  : plan.identifier === 'scale'
                    ? 'upgrade_to_scale'
                    : plan.identifier === 'enterprise'
                      ? 'contact_sales_enterprise_plan'
                      : 'upgrade_plan'
                const isEnterprisePlan = plan.identifier === 'enterprise'

                return (
                  <div key={plan.identifier} className="rounded-xl border border-[var(--border)] p-6 flex flex-col">
                    <div className="text-lg font-semibold text-[var(--foreground)]">{plan.name}</div>
                    {!isEnterprisePlan && (
                      <div className="text-2xl font-bold text-[var(--foreground)] mt-2">
                        {currencySymbol}{plan.monthly_price}
                        <span className="text-sm font-normal text-[var(--foreground-muted)]">{t('customer_settings.billing.per_month')}</span>
                      </div>
                    )}
                    {isEnterprisePlan && (
                      <div className="text-lg font-semibold text-[var(--accent)] mt-2">
                        {t('customer_settings.billing.enterprise_contact_description')}
                      </div>
                    )}
                    <div className="mt-6 space-y-3 flex-1">
                      {isEnterprisePlan ? (
                        enterpriseFeatures.map(feature => (
                          <div key={feature} className="flex items-start gap-2 text-sm text-[var(--foreground-muted)]">
                            <CheckCircle2 className="h-4 w-4 text-[var(--accent)] shrink-0 mt-0.5" />
                            <span>{feature}</span>
                          </div>
                        ))
                      ) : (
                        <div className="flex items-start gap-2 text-sm text-[var(--foreground-muted)]">
                          <CheckCircle2 className="h-4 w-4 text-[var(--accent)] shrink-0 mt-0.5" />
                          <span>{t('customer_settings.billing.plan_meetings', { count: plan.monthly_meeting_limit })}</span>
                        </div>
                      )}
                    </div>
                    <Button
                      variant={isCurrentPlan ? 'secondary' : 'primary'}
                      size="md"
                      className="w-full mt-6"
                      onClick={() => notifyBillingInterest(actionName)}
                      disabled={isCurrentPlan}
                    >
                      {isCurrentPlan
                        ? t('customer_settings.billing.current_plan')
                        : isEnterprisePlan
                          ? t('customer_settings.billing.contact_sales')
                          : t('customer_settings.billing.upgrade')}
                    </Button>
                  </div>
                )
              })}
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <div className="flex items-center gap-3">
              <div className="h-10 w-10 rounded-lg bg-[var(--accent)]/10 flex items-center justify-center">
                <Zap className="h-5 w-5 text-[var(--accent)]" />
              </div>
              <div>
                <div className="text-lg font-semibold text-[var(--foreground)]">{t('customer_settings.billing.optional_addons')}</div>
                <div className="text-sm text-[var(--foreground-muted)]">{t('customer_settings.billing.optional_addons_description')}</div>
              </div>
            </div>
          </CardHeader>
          <CardContent>
            <div className="rounded-xl border border-[var(--border)] p-6 max-w-md">
              <div className="flex items-start justify-between gap-4">
                <div>
                  <div className="text-lg font-semibold text-[var(--foreground)]">{t('customer_settings.billing.buying_signals')}</div>
                  <div className="text-sm text-[var(--foreground-muted)] mt-2">{t('customer_settings.billing.buying_signals_description')}</div>
                </div>
                <div className="text-xl font-bold text-[var(--foreground)] whitespace-nowrap">
                  €{buying_signals_monthly_price}
                  <span className="text-sm font-normal text-[var(--foreground-muted)]">{t('customer_settings.billing.per_month')}</span>
                </div>
              </div>
              <div className="mt-6 space-y-3">
                {buyingSignalsFeatures.map(feature => (
                  <div key={feature} className="flex items-start gap-2 text-sm text-[var(--foreground-muted)]">
                    <CheckCircle2 className="h-4 w-4 text-[var(--accent)] shrink-0 mt-0.5" />
                    <span>{feature}</span>
                  </div>
                ))}
              </div>
              <Button
                variant="primary"
                size="md"
                className="w-full mt-6"
                onClick={() => notifyBillingInterest('upgrade_for_buying_signals')}
              >
                {t('customer_settings.billing.activate_addon')}
              </Button>
            </div>
          </CardContent>
        </Card>

      </div>
    </SettingsLayout>
  );
}
