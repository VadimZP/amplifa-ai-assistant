import { Link, router, useForm } from '@inertiajs/react'
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
  role: string
  status: string
  organization_id: number | null
  deactivated_at: string | null
  organization: Organization | null
}

interface AdminAccountEditProps {
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
  account: Account
  organizations: Organization[]
  roles: string[]
  statuses: string[]
  flash?: {
    notice?: string
    alert?: string
  }
}

export default function Edit({ auth, account, organizations, roles, statuses, flash }: AdminAccountEditProps) {
  const currentAccount = auth.account

  const { data, setData, put, processing, errors } = useForm({
    email: account.email,
    first_name: account.first_name,
    last_name: account.last_name,
    role: account.role,
    organization_id: account.organization_id || '',
    status: account.status
  })

  const formatRoleName = (role: string) => {
    switch (role) {
      case 'amplifa_admin':
        return t('admin.roles.amplifa_admin')
      case 'customer_admin':
        return t('admin.roles.customer_admin')
      case 'customer_user':
        return t('admin.roles.customer_user')
      default:
        return role.split('_').map(word => word.charAt(0).toUpperCase() + word.slice(1)).join(' ')
    }
  }

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    put(`/admin/accounts/${account.id}`)
  }

  const handleDeactivate = () => {
    if (confirm(t('admin.accounts.edit.deactivate_confirm'))) {
      router.delete(`/admin/accounts/${account.id}`)
    }
  }

  return (
    <AuthenticatedLayout
      title={t('admin.accounts.edit.title', { name: `${account.first_name} ${account.last_name}` })}
      account={currentAccount}
      flash={flash}
    >
      {/* Header */}
      <div className="py-8">
        <div className="sm:flex sm:items-center sm:justify-between">
          <div className="sm:flex-auto">
            <h2 className="text-4xl font-bold text-gray-900">
              {t('admin.accounts.edit.heading')}
            </h2>
            <p className="mt-2 text-base text-gray-600">
              {t('admin.accounts.edit.subtitle')}
            </p>
          </div>
          <div className="mt-4 sm:mt-0 sm:ml-16 sm:flex-none">
            <Link
              href="/admin/accounts"
              className="inline-flex items-center justify-center rounded-lg border border-gray-300 bg-white px-5 py-2.5 text-sm font-semibold text-gray-700 shadow-sm hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2 transition-colors sm:w-auto"
            >
              {t('admin.accounts.edit.back_button')}
            </Link>
          </div>
        </div>
      </div>

      {/* Form */}
      <div className="mt-8">
        <div className="bg-white shadow-lg rounded-xl border border-gray-100 overflow-hidden">
          <form onSubmit={handleSubmit}>
            <div className="px-8 py-8 space-y-8">
              {/* Email */}
              <div>
                <label htmlFor="email" className="block text-sm font-semibold text-gray-700">
                  {t('admin.common.email')}
                </label>
                <input
                  type="email"
                  id="email"
                  value={data.email}
                  onChange={(e) => setData('email', e.target.value)}
                  className="mt-2 block w-full rounded-lg border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm"
                  required
                />
                {errors.email && (
                  <p className="mt-2 text-sm text-red-600">{errors.email}</p>
                )}
              </div>

              {/* First Name */}
              <div>
                <label htmlFor="first_name" className="block text-sm font-semibold text-gray-700">
                  {t('admin.common.first_name')}
                </label>
                <input
                  type="text"
                  id="first_name"
                  value={data.first_name}
                  onChange={(e) => setData('first_name', e.target.value)}
                  className="mt-2 block w-full rounded-lg border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm"
                  required
                />
                {errors.first_name && (
                  <p className="mt-2 text-sm text-red-600">{errors.first_name}</p>
                )}
              </div>

              {/* Last Name */}
              <div>
                <label htmlFor="last_name" className="block text-sm font-semibold text-gray-700">
                  {t('admin.common.last_name')}
                </label>
                <input
                  type="text"
                  id="last_name"
                  value={data.last_name}
                  onChange={(e) => setData('last_name', e.target.value)}
                  className="mt-2 block w-full rounded-lg border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm"
                  required
                />
                {errors.last_name && (
                  <p className="mt-2 text-sm text-red-600">{errors.last_name}</p>
                )}
              </div>

              {/* Role */}
              <div>
                <label htmlFor="role" className="block text-sm font-semibold text-gray-700">
                  {t('admin.common.role')}
                </label>
                <select
                  id="role"
                  value={data.role}
                  onChange={(e) => setData('role', e.target.value)}
                  className="mt-2 block w-full rounded-lg border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm"
                  required
                >
                  {roles.map((role) => (
                    <option key={role} value={role}>
                      {formatRoleName(role)}
                    </option>
                  ))}
                </select>
                {errors.role && (
                  <p className="mt-2 text-sm text-red-600">{errors.role}</p>
                )}
              </div>

              {/* Organization */}
              {data.role !== 'amplifa_admin' && (
                <div>
                  <label htmlFor="organization_id" className="block text-sm font-semibold text-gray-700">
                    {t('admin.common.organization')} {data.role !== 'amplifa_admin' && <span className="text-red-500">*</span>}
                  </label>
                  <select
                    id="organization_id"
                    value={data.organization_id}
                    onChange={(e) => setData('organization_id', e.target.value)}
                    className="mt-2 block w-full rounded-lg border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm"
                    required={data.role !== 'amplifa_admin'}
                  >
                    <option value="">{t('admin.accounts.edit.select_organization')}</option>
                    {organizations.map((org) => (
                      <option key={org.id} value={org.id}>
                        {org.name}
                      </option>
                    ))}
                  </select>
                  {errors.organization_id && (
                    <p className="mt-2 text-sm text-red-600">{errors.organization_id}</p>
                  )}
                </div>
              )}

              {/* Status */}
              <div>
                <label htmlFor="status" className="block text-sm font-semibold text-gray-700">
                  {t('admin.common.status')}
                </label>
                <select
                  id="status"
                  value={data.status}
                  onChange={(e) => setData('status', e.target.value)}
                  className="mt-2 block w-full rounded-lg border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm"
                  required
                >
                  {statuses.map((status) => (
                    <option key={status} value={status}>
                      {status.charAt(0).toUpperCase() + status.slice(1)}
                    </option>
                  ))}
                </select>
                {errors.status && (
                  <p className="mt-2 text-sm text-red-600">{errors.status}</p>
                )}
              </div>
            </div>

            {/* Actions */}
            <div className="bg-gray-50 px-8 py-5 flex justify-between items-center border-t border-gray-100">
              <div>
                {!account.deactivated_at && (
                  <button
                    type="button"
                    onClick={handleDeactivate}
                    className="inline-flex items-center justify-center rounded-lg border border-red-300 bg-white px-5 py-2.5 text-sm font-semibold text-red-700 shadow-sm hover:bg-red-50 focus:outline-none focus:ring-2 focus:ring-red-500 focus:ring-offset-2 transition-colors"
                  >
                    {t('admin.accounts.edit.deactivate_button')}
                  </button>
                )}
              </div>
              <div className="flex gap-3">
                <Link
                  href="/admin/accounts"
                  className="inline-flex items-center justify-center rounded-lg border border-gray-300 bg-white px-5 py-2.5 text-sm font-semibold text-gray-700 shadow-sm hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2 transition-colors"
                >
                  {t('admin.common.cancel')}
                </Link>
                <button
                  type="submit"
                  disabled={processing}
                  className="inline-flex items-center justify-center rounded-lg border border-transparent bg-indigo-600 px-5 py-2.5 text-sm font-semibold text-white shadow-md hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2 transition-colors disabled:opacity-50"
                >
                  {processing ? t('admin.common.saving') : t('admin.common.save_changes')}
                </button>
              </div>
            </div>
          </form>
        </div>
      </div>
    </AuthenticatedLayout>
  )
}
