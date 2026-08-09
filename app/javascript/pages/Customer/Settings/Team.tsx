import { useForm, usePage, router } from '@inertiajs/react'
import { Mail, UserPlus, Users2, XCircle } from 'lucide-react'
import { Badge } from '../../../components/ui/Badge'
import { Button } from '../../../components/ui/Button'
import { Card, CardContent, CardHeader } from '../../../components/ui/Card'
import { Input } from '../../../components/ui/Input'
import SettingsLayout from '../../../layouts/SettingsLayout'
import { t } from '../../../lib/i18n'

interface TeamMember {
  id: number
  first_name: string
  last_name: string
  full_name: string
  email: string
  role: string
  created_at: string
  deactivated_at: string | null
  'active?': boolean
  'customer_admin?': boolean
  'customer_user?': boolean
}

interface InvitedBy {
  id: number
  first_name: string
  last_name: string
  email: string
  full_name: string
}

interface PendingInvitation {
  id: number
  email: string
  first_name: string
  last_name: string
  role: string
  expires_at: string
  created_at: string
  invited_by: InvitedBy
}

interface TeamProps {
  team_members: TeamMember[]
  pending_invitations: PendingInvitation[]
  can_manage_team: boolean
  errors?: Record<string, string[]>
  invitation?: {
    email?: string
    first_name?: string
    last_name?: string
    role?: string
  }
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
  }
}

const roleLabel = (role: string) => {
  if (role === 'customer_admin') return t('customer_settings.team.roles.customer_admin')
  if (role === 'customer_user') return t('customer_settings.team.roles.customer_user')
  return role
}

export default function Team({ team_members, pending_invitations, can_manage_team, errors, invitation }: TeamProps) {
  const { auth } = usePage<SharedProps>().props

  const { data, setData, post, processing } = useForm({
    invitation: {
      email: invitation?.email || '',
      first_name: invitation?.first_name || '',
      last_name: invitation?.last_name || '',
      role: invitation?.role || 'customer_user'
    }
  })

  const submitInvitation = (event: React.FormEvent) => {
    event.preventDefault()
    post('/settings/team/invitations', {
      preserveScroll: true
    })
  }

  const deactivateMember = (member: TeamMember) => {
    if (!confirm(t('customer_settings.team.deactivate_confirm', { name: member.full_name }))) return

    router.patch(`/settings/team/members/${member.id}/deactivate`, {}, {
      preserveScroll: true
    })
  }

  const cancelInvitation = (invitation: PendingInvitation) => {
    if (!confirm(t('customer_settings.team.cancel_invitation_confirm', { email: invitation.email }))) return

    router.delete(`/settings/team/invitations/${invitation.id}`, {
      preserveScroll: true
    })
  }

  return (
    <SettingsLayout
      currentTab="team"
      sidebarSections={[
        { id: 'members', label: t('customer_settings.team.sections.members') },
        { id: 'invitations', label: t('customer_settings.team.sections.invitations') }
      ]}
    >
      <div className="space-y-8 max-w-5xl">
        <div id="members" className="scroll-mt-8">
          <Card>
            <CardHeader>
              <div className="flex items-center justify-between gap-4">
                <div className="flex items-center gap-3">
                  <div className="h-10 w-10 rounded-lg bg-[var(--accent)]/10 flex items-center justify-center">
                    <Users2 className="h-5 w-5 text-[var(--accent)]" />
                  </div>
                  <div>
                    <div className="text-lg font-semibold text-[var(--foreground)]">{t('customer_settings.team.title')}</div>
                    <div className="text-sm text-[var(--foreground-muted)]">{t('customer_settings.team.description')}</div>
                  </div>
                </div>
                {can_manage_team
                  ? <Badge variant="success">{t('customer_settings.team.can_manage')}</Badge>
                  : <Badge variant="default">{t('customer_settings.team.read_only')}</Badge>}
              </div>
            </CardHeader>
            <CardContent>
              {team_members.length === 0 ? (
                <div className="text-sm text-[var(--foreground-muted)]">{t('customer_settings.team.empty')}</div>
              ) : (
                <div className="space-y-2">
                  {team_members.map((member) => {
                    const isSelf = auth.account.id === member.id
                    const canDeactivate = can_manage_team && !isSelf && member.role !== 'customer_admin' && member['active?']

                    return (
                      <div
                        key={member.id}
                        className="rounded-lg border border-[var(--border)] p-3 flex items-center justify-between gap-4"
                      >
                        <div>
                          <div className="text-sm font-medium text-[var(--foreground)]">{member.full_name}</div>
                          <div className="text-xs text-[var(--foreground-muted)]">{member.email}</div>
                        </div>

                        <div className="flex items-center gap-2">
                          <Badge variant={member.role === 'customer_admin' ? 'info' : 'default'}>
                            {roleLabel(member.role)}
                          </Badge>

                          {member['active?']
                            ? <Badge variant="success">{t('customer_settings.team.statuses.active')}</Badge>
                            : <Badge variant="warning">{t('customer_settings.team.statuses.deactivated')}</Badge>}

                          {canDeactivate && (
                            <Button
                              type="button"
                              size="sm"
                              variant="secondary"
                              onClick={() => deactivateMember(member)}
                            >
                              {t('customer_settings.team.deactivate')}
                            </Button>
                          )}
                        </div>
                      </div>
                    )
                  })}
                </div>
              )}
            </CardContent>
          </Card>
        </div>

        <div id="invitations" className="scroll-mt-8">
          <Card>
            <CardHeader>
              <div className="flex items-center gap-3">
                <div className="h-10 w-10 rounded-lg bg-[var(--accent)]/10 flex items-center justify-center">
                  <UserPlus className="h-5 w-5 text-[var(--accent)]" />
                </div>
                <div>
                  <div className="text-lg font-semibold text-[var(--foreground)]">{t('customer_settings.team.invite.title')}</div>
                  <div className="text-sm text-[var(--foreground-muted)]">{t('customer_settings.team.invite.description')}</div>
                </div>
              </div>
            </CardHeader>
            <CardContent className="space-y-6">
              {can_manage_team ? (
                <form onSubmit={submitInvitation} className="space-y-4">
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                    <Input
                      label={t('customer_settings.team.invite.first_name')}
                      value={data.invitation.first_name}
                      onChange={(event) => setData('invitation', { ...data.invitation, first_name: event.target.value })}
                      error={errors?.first_name?.[0]}
                      required
                    />

                    <Input
                      label={t('customer_settings.team.invite.last_name')}
                      value={data.invitation.last_name}
                      onChange={(event) => setData('invitation', { ...data.invitation, last_name: event.target.value })}
                      error={errors?.last_name?.[0]}
                      required
                    />

                    <Input
                      label={t('customer_settings.team.invite.email')}
                      type="email"
                      icon={<Mail className="h-4 w-4" />}
                      value={data.invitation.email}
                      onChange={(event) => setData('invitation', { ...data.invitation, email: event.target.value })}
                      error={errors?.email?.[0]}
                      required
                    />

                    <div className="space-y-2">
                      <label htmlFor="invite-role" className="block text-sm font-medium text-[var(--foreground)]">
                        {t('customer_settings.team.invite.role')}
                      </label>
                      <select
                        id="invite-role"
                        value={data.invitation.role}
                        onChange={(event) => setData('invitation', { ...data.invitation, role: event.target.value })}
                        className="block w-full px-3 py-2.5 bg-[var(--input)] border border-[var(--input-border)] rounded-lg text-[var(--foreground)] text-sm focus:outline-none focus:ring-2 focus:ring-[var(--ring)]"
                      >
                        <option value="customer_user">{t('customer_settings.team.roles.customer_user')}</option>
                        <option value="customer_admin">{t('customer_settings.team.roles.customer_admin')}</option>
                      </select>
                      {errors?.role && <p className="text-sm text-[var(--error)]">{errors.role[0]}</p>}
                    </div>
                  </div>

                  <div className="flex justify-end">
                    <Button type="submit" loading={processing}>
                      {t('customer_settings.team.invite.submit')}
                    </Button>
                  </div>
                </form>
              ) : (
                <div className="text-sm text-[var(--foreground-muted)]">
                  {t('customer_settings.team.invite.admin_only')}
                </div>
              )}

              <div className="space-y-2">
                <div className="text-sm font-medium text-[var(--foreground)]">{t('customer_settings.team.pending.title')}</div>

                {pending_invitations.length === 0 ? (
                  <div className="text-sm text-[var(--foreground-muted)]">{t('customer_settings.team.pending.empty')}</div>
                ) : (
                  pending_invitations.map((pending) => (
                    <div key={pending.id} className="rounded-lg border border-[var(--border)] p-3 flex items-center justify-between gap-3">
                      <div>
                        <div className="text-sm text-[var(--foreground)]">
                          {pending.first_name} {pending.last_name} · {pending.email}
                        </div>
                        <div className="text-xs text-[var(--foreground-muted)]">
                          {t('customer_settings.team.pending.meta', { inviter: pending.invited_by.full_name, date: new Date(pending.expires_at).toLocaleDateString(document.documentElement.lang || undefined) })}
                        </div>
                      </div>
                      <div className="flex items-center gap-2">
                        <Badge variant="warning">{roleLabel(pending.role)}</Badge>
                        {can_manage_team && (
                          <Button
                            type="button"
                            size="sm"
                            variant="secondary"
                            onClick={() => cancelInvitation(pending)}
                          >
                            <XCircle className="h-4 w-4" />
                            {t('common.cancel')}
                          </Button>
                        )}
                      </div>
                    </div>
                  ))
                )}
              </div>
            </CardContent>
          </Card>
        </div>
      </div>
    </SettingsLayout>
  )
}
