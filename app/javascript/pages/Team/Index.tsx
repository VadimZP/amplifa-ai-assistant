import AuthenticatedLayout from '../../layouts/AuthenticatedLayout'
import { usePage } from '@inertiajs/react'
import { t } from '../../lib/i18n'

interface TeamMember {
  id: number
  first_name: string
  last_name: string
  full_name: string
  email: string
  role: string
  created_at: string
  customer_admin?: boolean
  customer_user?: boolean
}

interface TeamIndexProps {
  team_members: TeamMember[]
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
  impersonating?: boolean
  impersonating_admin?: {
    id: number
    name: string
    email: string
  }
}

function getRoleBadge(member: TeamMember) {
  if (member.customer_admin) {
    return (
      <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-purple-100 text-purple-800">
        {t('customer_settings.team.roles.customer_admin')}
      </span>
    )
  } else if (member.customer_user) {
    return (
      <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-800">
        {t('customer_settings.team.roles.customer_user')}
      </span>
    )
  }
  return (
    <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-800">
      {member.role}
    </span>
  )
}

function formatDate(dateString: string) {
  const date = new Date(dateString)
  return new Intl.DateTimeFormat('en-US', {
    year: 'numeric',
    month: 'short',
    day: 'numeric'
  }).format(date)
}

export default function Index({ team_members }: TeamIndexProps) {
  const { auth, flash } = usePage<SharedProps>().props
  const { account, organization } = auth

  return (
    <AuthenticatedLayout
      title={t('customer_settings.team.title')}
      account={account}
      organization={organization}
      flash={flash}
    >
      {/* Page Header */}
      <div className="mb-6">
        <h1 className="text-3xl font-bold text-gray-900">{t('customer_settings.team.title')}</h1>
        {organization && (
          <p className="mt-1 text-sm text-gray-600">
            {t('customer_settings.team.members_of', { organization: organization.name })}
          </p>
        )}
      </div>

      {/* Team Members Table */}
      <div className="bg-white shadow overflow-hidden sm:rounded-lg">
        <table className="min-w-full divide-y divide-gray-200">
          <thead className="bg-gray-50">
            <tr>
              <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                {t('customer_settings.team.table.name')}
              </th>
              <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                {t('customer_settings.team.table.email')}
              </th>
              <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                {t('customer_settings.team.table.role')}
              </th>
              <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                {t('customer_settings.team.table.joined')}
              </th>
            </tr>
          </thead>
          <tbody className="bg-white divide-y divide-gray-200">
            {team_members.length === 0 ? (
              <tr>
                <td colSpan={4} className="px-6 py-12 text-center text-gray-500">
                  No team members found
                </td>
              </tr>
            ) : (
              team_members.map((member) => (
                <tr key={member.id} className="hover:bg-gray-50">
                  <td className="px-6 py-4 whitespace-nowrap">
                    <div className="flex items-center">
                      <div className="flex-shrink-0 h-10 w-10">
                        <div className="h-10 w-10 rounded-full bg-indigo-600 flex items-center justify-center text-white font-medium">
                          {member.first_name[0]}{member.last_name[0]}
                        </div>
                      </div>
                      <div className="ml-4">
                        <div className="text-sm font-medium text-gray-900">
                          {member.full_name}
                        </div>
                      </div>
                    </div>
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap">
                    <div className="text-sm text-gray-900">{member.email}</div>
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap">
                    {getRoleBadge(member)}
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                    {formatDate(member.created_at)}
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>

      {/* Stats Summary */}
      {team_members.length > 0 && (
        <div className="mt-6 bg-gray-50 rounded-lg p-4">
          <div className="text-sm text-gray-600">
            Total team members: <span className="font-semibold text-gray-900">{team_members.length}</span>
          </div>
        </div>
      )}
    </AuthenticatedLayout>
  )
}
