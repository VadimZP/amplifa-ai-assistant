import { Link, router } from '@inertiajs/react'
import AuthenticatedLayout from '../../../layouts/AuthenticatedLayout'
// WHY: Import i18n for multilingual support, enabling translation of all UI text
import { t } from '../../../lib/i18n'

interface Organization {
  id: number
  name: string
}

interface Account {
  id: number
  email: string
  first_name: string
  last_name: string
  full_name: string
  role: string
  status: string
  deactivated_at: string | null
  created_at: string
  'active?': boolean
  organization: Organization | null
}

interface AdminAccountsIndexProps {
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
  accounts: Account[]
  flash?: {
    notice?: string
    alert?: string
  }
}

export default function Index({ auth, accounts, flash }: AdminAccountsIndexProps) {
  const account = auth.account

  const formatDate = (dateString: string) => {
    return new Date(dateString).toLocaleDateString('en-US', {
      year: 'numeric',
      month: 'short',
      day: 'numeric'
    })
  }

  const handleLoginAs = (accountId: number) => {
    if (confirm(t('admin.accounts.impersonate_confirm'))) {
      router.post(`/admin/accounts/${accountId}/impersonate`)
    }
  }

  const getStatusBadge = (status: string, deactivatedAt: string | null) => {
    if (deactivatedAt) {
      return (
        <span className="inline-flex items-center rounded-full bg-red-100 px-3 py-1 text-xs font-semibold text-red-800">
          {t('admin.statuses.deactivated')}
        </span>
      )
    }

    switch (status) {
      case 'verified':
        return (
          <span className="inline-flex items-center rounded-full bg-green-100 px-3 py-1 text-xs font-semibold text-green-800">
            {t('admin.statuses.verified')}
          </span>
        )
      case 'unverified':
        return (
          <span className="inline-flex items-center rounded-full bg-yellow-100 px-3 py-1 text-xs font-semibold text-yellow-800">
            {t('admin.statuses.unverified')}
          </span>
        )
      case 'closed':
        return (
          <span className="inline-flex items-center rounded-full bg-gray-100 px-3 py-1 text-xs font-semibold text-gray-800">
            {t('admin.statuses.closed')}
          </span>
        )
      default:
        return (
          <span className="inline-flex items-center rounded-full bg-gray-100 px-3 py-1 text-xs font-semibold text-gray-800">
            {status}
          </span>
        )
    }
  }

  const getRoleBadge = (role: string) => {
    switch (role) {
      case 'amplifa_admin':
        return (
          <span className="inline-flex items-center rounded-full bg-purple-100 px-3 py-1 text-xs font-semibold text-purple-800">
            {t('admin.roles.amplifa_admin')}
          </span>
        )
      case 'customer_admin':
        return (
          <span className="inline-flex items-center rounded-full bg-blue-100 px-3 py-1 text-xs font-semibold text-blue-800">
            {t('admin.roles.customer_admin')}
          </span>
        )
      case 'customer_user':
        return (
          <span className="inline-flex items-center rounded-full bg-gray-100 px-3 py-1 text-xs font-semibold text-gray-800">
            {t('admin.roles.customer_user')}
          </span>
        )
      default:
        return (
          <span className="inline-flex items-center rounded-full bg-gray-100 px-3 py-1 text-xs font-semibold text-gray-800">
            {role}
          </span>
        )
    }
  }

  return (
    <AuthenticatedLayout
      title={t('admin.accounts.title')}
      account={account}
      flash={flash}
    >
      {/* Header */}
      <div className="py-8">
        <div className="sm:flex sm:items-center sm:justify-between">
          <div className="sm:flex-auto">
            <h2 className="text-4xl font-bold text-gray-900">
              {t('admin.accounts.title')}
            </h2>
            <p className="mt-2 text-base text-gray-600">
              {t('admin.accounts.subtitle')}
            </p>
          </div>
          <div className="mt-4 sm:mt-0 sm:ml-16 sm:flex-none">
            <Link
              href="/admin/dashboard"
              className="inline-flex items-center justify-center rounded-lg border border-gray-300 bg-white px-5 py-2.5 text-sm font-semibold text-gray-700 shadow-sm hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2 transition-colors sm:w-auto"
            >
              {t('admin.accounts.back_button')}
            </Link>
          </div>
        </div>
      </div>

      {/* Accounts Table */}
      <div className="mt-8 flex flex-col">
        <div className="-my-2 -mx-4 overflow-x-auto sm:-mx-6 lg:-mx-8">
          <div className="inline-block min-w-full py-2 align-middle md:px-6 lg:px-8">
            <div className="overflow-hidden shadow-lg ring-1 ring-black ring-opacity-5 rounded-xl border border-gray-100">
              <table className="min-w-full divide-y divide-gray-200">
                <thead className="bg-gray-50">
                  <tr>
                    <th scope="col" className="py-4 pl-6 pr-3 text-left text-xs font-semibold text-gray-600 uppercase tracking-wider">
                      {t('admin.common.name')}
                    </th>
                    <th scope="col" className="px-3 py-4 text-left text-xs font-semibold text-gray-600 uppercase tracking-wider">
                      {t('admin.common.email')}
                    </th>
                    <th scope="col" className="px-3 py-4 text-left text-xs font-semibold text-gray-600 uppercase tracking-wider">
                      {t('admin.common.organization')}
                    </th>
                    <th scope="col" className="px-3 py-4 text-left text-xs font-semibold text-gray-600 uppercase tracking-wider">
                      {t('admin.common.role')}
                    </th>
                    <th scope="col" className="px-3 py-4 text-left text-xs font-semibold text-gray-600 uppercase tracking-wider">
                      {t('admin.common.status')}
                    </th>
                    <th scope="col" className="px-3 py-4 text-left text-xs font-semibold text-gray-600 uppercase tracking-wider">
                      {t('admin.common.created')}
                    </th>
                    <th scope="col" className="relative py-4 pl-3 pr-6">
                      <span className="sr-only">{t('admin.common.actions')}</span>
                    </th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-200 bg-white">
                  {accounts.length === 0 ? (
                    <tr>
                      <td colSpan={7} className="py-12 text-center text-sm text-gray-500">
                        {t('admin.accounts.empty')}
                      </td>
                    </tr>
                  ) : (
                    accounts.map((acc) => (
                      <tr key={acc.id} className="hover:bg-gray-50 transition-colors">
                        <td className="whitespace-nowrap py-5 pl-6 pr-3 text-sm font-semibold text-gray-900">
                          {acc.full_name}
                        </td>
                        <td className="whitespace-nowrap px-3 py-5 text-sm text-gray-600">
                          {acc.email}
                        </td>
                        <td className="whitespace-nowrap px-3 py-5 text-sm text-gray-600">
                          {acc.organization?.name || 'N/A'}
                        </td>
                        <td className="whitespace-nowrap px-3 py-5 text-sm">
                          {getRoleBadge(acc.role)}
                        </td>
                        <td className="whitespace-nowrap px-3 py-5 text-sm">
                          {getStatusBadge(acc.status, acc.deactivated_at)}
                        </td>
                        <td className="whitespace-nowrap px-3 py-5 text-sm text-gray-600">
                          {formatDate(acc.created_at)}
                        </td>
                        <td className="relative whitespace-nowrap py-5 pl-3 pr-6 text-right text-sm font-medium space-x-4">
                          <Link
                            href={`/admin/accounts/${acc.id}/edit`}
                            className="text-indigo-600 hover:text-indigo-900 font-semibold transition-colors"
                          >
                            {t('admin.common.edit')}
                          </Link>
                          {(acc.role === 'customer_admin' || acc.role === 'customer_user') && acc['active?'] && (
                            <button
                              onClick={() => handleLoginAs(acc.id)}
                              className="text-purple-600 hover:text-purple-900 font-semibold transition-colors"
                            >
                              {t('admin.accounts.table.login_as')}
                            </button>
                          )}
                        </td>
                      </tr>
                    ))
                  )}
                </tbody>
              </table>
            </div>
          </div>
        </div>
      </div>
    </AuthenticatedLayout>
  )
}
