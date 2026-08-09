/**
 * Campaign Status Card Component
 * Shows campaign launch status, requirements, and real-time statistics
 */
import { router } from '@inertiajs/react'
import { Play, Pause, CheckCircle, XCircle, Clock, Send, Users, UserPlus, Inbox } from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from './ui/Card'
import { Badge } from './ui/Badge'
import { Button } from './ui/Button'
import { t } from '../lib/i18n'

interface CampaignStatus {
  launched: boolean
  launched_at: string | null
  paused: boolean
  paused_at: string | null
  can_launch: boolean
  can_pause: boolean
  can_resume: boolean
  ready_to_launch: boolean
  scheduled_sends_today: number
  available_capacity: number
  leads_in_sequence: number
  leads_not_yet_contacted: number
  leads_pending_today: number
  leads_sent_today: number
}

interface SampleStatus {
  samples_approved: boolean
}

interface CampaignStatusCardProps {
  agentId: number
  campaignStatus: CampaignStatus
  sampleStatus: SampleStatus
  hasLeads: boolean
  hasMailboxes: boolean
  hasApprovedPlaybook: boolean
}

export default function CampaignStatusCard({
  agentId,
  campaignStatus,
  sampleStatus,
  hasLeads,
  hasMailboxes,
  hasApprovedPlaybook,
}: CampaignStatusCardProps) {
  const formatDate = (dateString: string) => {
    return new Date(dateString).toLocaleDateString('en-US', {
      year: 'numeric',
      month: 'short',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit'
    })
  }

  const handleLaunch = () => {
    if (confirm(t('admin.agents.show.campaign_status.confirm_launch'))) {
      router.post(`/admin/agents/${agentId}/launch_campaign`)
    }
  }

  const handlePause = () => {
    if (confirm(t('admin.agents.show.campaign_status.confirm_pause'))) {
      router.post(`/admin/agents/${agentId}/pause_campaign`)
    }
  }

  const handleResume = () => {
    if (confirm(t('admin.agents.show.campaign_status.confirm_resume'))) {
      router.post(`/admin/agents/${agentId}/resume_campaign`)
    }
  }

  // Requirements for launching - messages are generated JIT, so we only need samples approved
  const requirements = [
    { key: 'leads', met: hasLeads, label: t('admin.agents.show.campaign_status.requirement_leads') },
    { key: 'mailboxes', met: hasMailboxes, label: t('admin.agents.show.campaign_status.requirement_mailboxes') },
    { key: 'samples', met: sampleStatus.samples_approved, label: t('admin.agents.show.campaign_status.requirement_samples') },
    { key: 'playbook', met: hasApprovedPlaybook, label: t('admin.agents.show.campaign_status.requirement_playbook') },
  ]

  const allRequirementsMet = requirements.every(r => r.met)

  return (
    <Card>
      <CardHeader className="flex-row items-center justify-between">
        <div className="flex items-center gap-2">
          <Play className="w-5 h-5 text-[var(--foreground-muted)]" />
          <CardTitle className="mb-0">
            {t('admin.agents.show.campaign_status.title')}
          </CardTitle>
        </div>
        {campaignStatus.launched ? (
          campaignStatus.paused ? (
            <Badge variant="warning" className="gap-1">
              <Pause className="w-3.5 h-3.5" />
              {t('admin.agents.show.campaign_status.paused')}
            </Badge>
          ) : (
            <Badge variant="success" className="gap-1">
              <CheckCircle className="w-3.5 h-3.5" />
              {t('admin.agents.show.campaign_status.active')}
            </Badge>
          )
        ) : (
          <Badge variant="draft">
            {t('admin.agents.show.campaign_status.not_launched')}
          </Badge>
        )}
      </CardHeader>
      <CardContent className="space-y-6">
        {/* Launch status and button */}
        {campaignStatus.launched ? (
          <>
            {/* Launch/Pause status info */}
            <div className="space-y-1">
              {campaignStatus.launched_at && (
                <p className="text-sm text-[var(--foreground-muted)]">
                  {t('admin.agents.show.campaign_status.launched_at', { date: formatDate(campaignStatus.launched_at) })}
                </p>
              )}
              {campaignStatus.paused && campaignStatus.paused_at && (
                <p className="text-sm text-amber-400">
                  {t('admin.agents.show.campaign_status.paused_at', { date: formatDate(campaignStatus.paused_at) })}
                </p>
              )}
            </div>

            {/* Campaign Statistics */}
            <div className="grid grid-cols-2 gap-4">
              <div className="bg-[var(--card-hover)] rounded-lg p-4">
                <div className="flex items-center gap-2 mb-2">
                  <Users className="w-4 h-4 text-blue-400" />
                  <span className="text-xs font-medium text-[var(--foreground-muted)] uppercase">
                    {t('admin.agents.show.campaign_status.in_sequence')}
                  </span>
                </div>
                <p className="text-2xl font-bold text-[var(--foreground)]">
                  {campaignStatus.leads_in_sequence}
                </p>
              </div>

              <div className="bg-[var(--card-hover)] rounded-lg p-4">
                <div className="flex items-center gap-2 mb-2">
                  <UserPlus className="w-4 h-4 text-gray-400" />
                  <span className="text-xs font-medium text-[var(--foreground-muted)] uppercase">
                    {t('admin.agents.show.campaign_status.not_yet_contacted')}
                  </span>
                </div>
                <p className="text-2xl font-bold text-[var(--foreground)]">
                  {campaignStatus.leads_not_yet_contacted}
                </p>
              </div>

              <div className="bg-[var(--card-hover)] rounded-lg p-4">
                <div className="flex items-center gap-2 mb-2">
                  <Inbox className="w-4 h-4 text-purple-400" />
                  <span className="text-xs font-medium text-[var(--foreground-muted)] uppercase">
                    {t('admin.agents.show.campaign_status.available_capacity')}
                  </span>
                </div>
                <p className="text-2xl font-bold text-[var(--foreground)]">
                  {campaignStatus.available_capacity}
                </p>
              </div>

              <div className="bg-[var(--card-hover)] rounded-lg p-4">
                <div className="flex items-center gap-2 mb-2">
                  <Clock className="w-4 h-4 text-amber-400" />
                  <span className="text-xs font-medium text-[var(--foreground-muted)] uppercase">
                    {t('admin.agents.show.campaign_status.scheduled_today')}
                  </span>
                </div>
                <p className="text-2xl font-bold text-[var(--foreground)]">
                  {campaignStatus.scheduled_sends_today}
                </p>
              </div>

              <div className="bg-green-500/10 rounded-lg p-4">
                <div className="flex items-center gap-2 mb-2">
                  <Send className="w-4 h-4 text-green-400" />
                  <span className="text-xs font-medium text-green-400 uppercase">
                    {t('admin.agents.show.campaign_status.sent_today')}
                  </span>
                </div>
                <p className="text-2xl font-bold text-green-400">
                  {campaignStatus.leads_sent_today}
                </p>
              </div>
            </div>

            {/* Pause/Resume buttons */}
            <div className="pt-2 border-t border-[var(--border)]">
              {campaignStatus.can_pause && (
                <Button
                  onClick={handlePause}
                  variant="secondary"
                  icon={<Pause className="w-4 h-4" />}
                  className="bg-amber-600/20 hover:bg-amber-600/30 text-amber-400 border-amber-600/50"
                >
                  {t('admin.agents.show.campaign_status.pause_button')}
                </Button>
              )}
              {campaignStatus.can_resume && (
                <Button
                  onClick={handleResume}
                  icon={<Play className="w-4 h-4" />}
                  className="bg-green-600 hover:bg-green-700"
                >
                  {t('admin.agents.show.campaign_status.resume_button')}
                </Button>
              )}
            </div>
          </>
        ) : (
          <>
            {/* Launch Requirements */}
            <div>
              <h4 className="text-sm font-medium text-[var(--foreground)] mb-3">
                {t('admin.agents.show.campaign_status.launch_requirements')}
              </h4>
              <ul className="space-y-2">
                {requirements.map((req) => (
                  <li key={req.key} className="flex items-center gap-2">
                    {req.met ? (
                      <CheckCircle className="w-4 h-4 text-green-400" />
                    ) : (
                      <XCircle className="w-4 h-4 text-red-400" />
                    )}
                    <span className={`text-sm ${req.met ? 'text-[var(--foreground)]' : 'text-[var(--foreground-muted)]'}`}>
                      {req.label}
                    </span>
                  </li>
                ))}
              </ul>
            </div>

            {/* Launch Button */}
            <div className="pt-2">
              <Button
                onClick={handleLaunch}
                disabled={!allRequirementsMet}
                icon={<Play className="w-4 h-4" />}
                className={allRequirementsMet ? 'bg-green-600 hover:bg-green-700' : ''}
              >
                {t('admin.agents.show.campaign_status.launch_button')}
              </Button>
            </div>
          </>
        )}
      </CardContent>
    </Card>
  )
}
