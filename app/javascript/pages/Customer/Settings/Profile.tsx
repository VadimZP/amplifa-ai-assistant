import React from 'react';
import { useForm, usePage } from '@inertiajs/react';
import { Card, CardHeader, CardContent } from '../../../components/ui/Card';
import { Button } from '../../../components/ui/Button';
import { Input } from '../../../components/ui/Input';
import SettingsLayout from '../../../layouts/SettingsLayout';
import { toast } from '../../../components/ui/Toaster';
import { User, Shield } from 'lucide-react';
import { t } from '../../../lib/i18n';

interface ProfileProps {
  account: {
    id: number;
    email: string;
    first_name: string;
    last_name: string;
    full_name: string;
    timezone: string;
    locale: string;
  };
  organization: {
    id: number;
    name: string;
  };
  locale_options: string[];
  errors?: Record<string, string[]>;
  password_errors?: Record<string, string[]>;
}

export default function Profile({ account, organization: _organization, locale_options, errors, password_errors }: ProfileProps) {
  const { flash } = usePage<{ flash?: { notice?: string; alert?: string } }>().props;

  React.useEffect(() => {
    if (flash?.notice) toast.success(flash.notice);
    if (flash?.alert) toast.error(flash.alert);
  }, [flash?.notice, flash?.alert]);

  const sidebarSections = [
    { id: 'personal', label: t('customer_settings.profile.sections.personal') },
    { id: 'security', label: t('customer_settings.profile.sections.security') }
  ];

  const { data, setData, patch, processing, isDirty } = useForm({
    first_name: account?.first_name || '',
    last_name: account?.last_name || '',
    timezone: account?.timezone || 'Europe/Berlin',
    locale: account?.locale || 'en',
  });

  const {
    data: passwordData,
    setData: setPasswordData,
    patch: patchPassword,
    processing: passwordProcessing,
    isDirty: isPasswordDirty,
    reset: resetPasswordForm,
  } = useForm({
    current_password: '',
    new_password: '',
    new_password_confirmation: '',
  });

  const submitProfile = (e: React.FormEvent) => {
    e.preventDefault();
    patch('/settings/profile');
  };

  const submitPassword = (e: React.FormEvent) => {
    e.preventDefault();
    patchPassword('/settings/profile/password', {
      onSuccess: () => {
        resetPasswordForm('current_password', 'new_password', 'new_password_confirmation');
      },
    });
  };

  return (
    <SettingsLayout currentTab="profile" sidebarSections={sidebarSections}>
      <div className="space-y-8">
        {/* Section 1: Personal Info */}
        <div id="personal">
          <Card>
            <CardHeader>
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-3">
                  <div className="h-10 w-10 rounded-lg bg-white/5 flex items-center justify-center">
                    <User className="h-5 w-5 text-[var(--foreground-muted)]" />
                  </div>
                  <div>
                    <div className="text-lg font-semibold text-[var(--foreground)]">{t('customer_settings.profile.personal.title')}</div>
                    <div className="text-sm text-[var(--foreground-muted)]">{t('customer_settings.profile.personal.description')}</div>
                  </div>
                </div>
              </div>
            </CardHeader>
            <CardContent>
              <form onSubmit={submitProfile} className="space-y-6">
                <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                  <Input
                    label={t('customer_settings.profile.personal.first_name')}
                    value={data.first_name}
                    onChange={(e) => setData('first_name', e.target.value)}
                    error={errors?.first_name?.[0]}
                  />
                  <Input
                    label={t('customer_settings.profile.personal.last_name')}
                    value={data.last_name}
                    onChange={(e) => setData('last_name', e.target.value)}
                    error={errors?.last_name?.[0]}
                  />
                  <Input
                    label={t('customer_settings.profile.personal.email')}
                    value={account?.email || ''}
                    disabled
                    onChange={() => {}}
                  />
                  <div className="space-y-2">
                    <label htmlFor="profile-timezone" className="block text-sm font-medium text-[var(--foreground)]">
                      {t('customer_settings.profile.personal.timezone')}
                    </label>
                    <select
                      id="profile-timezone"
                      value={data.timezone}
                      onChange={(e) => setData('timezone', e.target.value)}
                      className="bg-[var(--input)] border border-[var(--input-border)] rounded-lg h-9 px-3 text-sm text-[var(--foreground)] w-full focus:outline-none focus:ring-2 focus:ring-[var(--accent)]"
                    >
                      <option value="Europe/Berlin">Europe/Berlin</option>
                      <option value="Europe/London">Europe/London</option>
                      <option value="America/New_York">America/New_York</option>
                      <option value="America/Los_Angeles">America/Los_Angeles</option>
                      <option value="Asia/Tokyo">Asia/Tokyo</option>
                    </select>
                    {errors?.timezone && (
                      <p className="text-sm text-[var(--error)]">{errors.timezone[0]}</p>
                    )}
                  </div>

                  <div className="space-y-2">
                    <label htmlFor="profile-locale" className="block text-sm font-medium text-[var(--foreground)]">
                      {t('customer_settings.profile.personal.language')}
                    </label>
                    <select
                      id="profile-locale"
                      value={data.locale}
                      onChange={(e) => setData('locale', e.target.value)}
                      className="bg-[var(--input)] border border-[var(--input-border)] rounded-lg h-9 px-3 text-sm text-[var(--foreground)] w-full focus:outline-none focus:ring-2 focus:ring-[var(--accent)]"
                    >
                      {locale_options.map((locale) => (
                        <option key={locale} value={locale}>{t(`languages.${locale}`)}</option>
                      ))}
                    </select>
                    {errors?.locale && (
                      <p className="text-sm text-[var(--error)]">{errors.locale[0]}</p>
                    )}
                  </div>
                </div>

                <div className="flex justify-end">
                  <Button type="submit" variant="primary" disabled={!isDirty || processing}>
                    {t('customer_settings.profile.personal.save')}
                  </Button>
                </div>
              </form>
            </CardContent>
          </Card>
        </div>

        <div id="security">
          <Card>
            <CardHeader>
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-3">
                  <div className="h-10 w-10 rounded-lg bg-white/5 flex items-center justify-center">
                    <Shield className="h-5 w-5 text-[var(--foreground-muted)]" />
                  </div>
                  <div>
                    <div className="text-lg font-semibold text-[var(--foreground)]">{t('customer_settings.profile.security.title')}</div>
                    <div className="text-sm text-[var(--foreground-muted)]">{t('customer_settings.profile.security.description')}</div>
                  </div>
                </div>
              </div>
            </CardHeader>
            <CardContent>
              <form onSubmit={submitPassword} className="space-y-6">
                <div className="space-y-4">
                  <div className="text-sm font-medium text-[var(--foreground)]">{t('customer_settings.profile.security.change_password')}</div>
                  <Input
                    type="password"
                      label={t('customer_settings.profile.security.old_password')}
                    value={passwordData.current_password}
                    onChange={(e) => setPasswordData('current_password', e.target.value)}
                    error={password_errors?.current_password?.[0]}
                  />
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                    <Input
                      type="password"
                      label={t('customer_settings.profile.security.new_password')}
                      value={passwordData.new_password}
                      onChange={(e) => setPasswordData('new_password', e.target.value)}
                      error={password_errors?.new_password?.[0]}
                    />
                    <Input
                      type="password"
                      label={t('customer_settings.profile.security.confirm_new_password')}
                      value={passwordData.new_password_confirmation}
                      onChange={(e) => setPasswordData('new_password_confirmation', e.target.value)}
                      error={password_errors?.new_password_confirmation?.[0]}
                    />
                  </div>
                  <p className="text-xs text-[var(--foreground-muted)]">{t('customer_settings.profile.security.password_help')}</p>
                  <div className="flex justify-end">
                    <Button
                      type="submit"
                      variant="secondary"
                      disabled={!isPasswordDirty || passwordProcessing}
                    >
                      {t('customer_settings.profile.security.update_password')}
                    </Button>
                  </div>
                </div>
              </form>
            </CardContent>
          </Card>
        </div>
      </div>
    </SettingsLayout>
  );
}
