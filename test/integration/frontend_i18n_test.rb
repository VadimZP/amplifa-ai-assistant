require 'test_helper'

class FrontendI18nTest < ActionDispatch::IntegrationTest
  # WHY: Test that frontend i18n is properly configured and that translations
  # are exported correctly for React components to use

  setup do
    @amplifa_admin = accounts(:amplifa_admin)
    @customer_admin = accounts(:customer_admin)
    @customer_user = accounts(:customer_user)
    @organization = organizations(:acme)
  end

  test 'HTML lang attribute reflects current locale for English user' do
    # WHY: Frontend i18n reads document.documentElement.lang to determine locale
    # The Rails layout must set this correctly based on I18n.locale

    login_as(@customer_admin)
    get dashboard_path

    assert_response :success
    assert_match(/html lang="en"/, response.body)
  end

  test 'HTML lang attribute reflects current locale for German user' do
    # WHY: When user switches to German, HTML lang should update so frontend i18n
    # displays German translations

    login_as(@customer_admin)
    @customer_admin.update!(locale: 'de')

    get dashboard_path

    assert_response :success
    assert_match(/html lang="de"/, response.body)
  end

  test 'login page includes locale for unauthenticated language selector' do
    post locale_path, params: { locale: 'de' }
    assert_response :success

    get login_path

    assert_response :success
    assert_match(/html lang="de"/, response.body)
    assert_match(/("|&quot;)locale("|&quot;):("|&quot;)de("|&quot;)/, response.body)
  end

  test 'per-locale translation JSON files are generated and contain expected keys' do
    locale_files = %w[en de es pt-BR fr pl cs it]

    locale_files.each do |locale|
      locale_file = Rails.root.join('app', 'javascript', 'locales', "#{locale}.json")
      assert File.exist?(locale_file), "Locale JSON file should exist at #{locale_file}"

      translations = JSON.parse(File.read(locale_file))

      assert translations[locale].present?, "#{locale} translations should be present"
      assert translations[locale]['navigation'].present?, "#{locale} navigation translations should exist"
      assert translations[locale]['navigation']['dashboard'].present?,
             "#{locale} dashboard translation should be present"
    end

    english_translations = JSON.parse(File.read(Rails.root.join('app', 'javascript', 'locales', 'en.json')))
    assert_equal 'Dashboard', english_translations['en']['navigation']['dashboard']
  end

  test 'i18n helper file exists and is properly configured' do
    # WHY: Frontend components import from '@/lib/i18n', verify the file exists

    i18n_helper = Rails.root.join('app', 'javascript', 'lib', 'i18n.ts')
    assert File.exist?(i18n_helper), "Frontend i18n helper should exist at #{i18n_helper}"

    content = File.read(i18n_helper)
    assert_match(/import.*i18n-js/, content, 'Should import i18n-js library')
    assert_match(/import\.meta\.glob/, content, 'Should lazy-load locale JSON files with import.meta.glob')
    assert_match(/initializeI18n/, content, 'Should expose async i18n initialization')
    assert_match(/document\.documentElement\.lang/, content, 'Should read locale from HTML lang attribute')
  end

  test 'locale controller allows users to switch language' do
    # WHY: Verify that locale switching endpoint works and updates user's locale

    login_as(@customer_admin)

    # Switch to German
    post locale_path, params: { locale: 'de' }

    assert_response :success
    json_response = JSON.parse(response.body)
    assert json_response['success']
    assert_equal 'de', json_response['locale']

    @customer_admin.reload
    assert_equal 'de', @customer_admin.locale
  end

  test 'frontend components have been updated to use i18n' do
    # WHY: Verify that key frontend components import and use the i18n helper
    # Updated to check for new pattern: import { t } from '...' and t() calls

    components_to_check = [
      'app/javascript/pages/Customer/Home/Index.tsx',
      'app/javascript/components/OnboardingChecklist.tsx',
      'app/javascript/components/TimelineRoadmap.tsx',
      'app/javascript/components/LanguageSelector.tsx',
      'app/javascript/layouts/AuthenticatedLayout.tsx',
      'app/javascript/layouts/AuthSplitLayout.tsx',
      'app/javascript/pages/Auth/Login.tsx'
    ]

    components_to_check.each do |component_path|
      full_path = Rails.root.join(component_path)
      assert File.exist?(full_path), "Component should exist: #{component_path}"

      content = File.read(full_path)
      # WHY: New pattern uses named import: import { t } from '...'
      assert_match(/import.*\{.*t.*\}.*from.*i18n/, content, "#{component_path} should import { t } from i18n helper")
      # WHY: Components now use t() directly instead of i18n.t()
      assert_match(/\bt\(/, content, "#{component_path} should use t() for translations")
    end
  end

  private

  def login_as(account)
    password = account.amplifa_admin? ? 'password123' : 'password'

    post login_path, params: {
      email: account.email,
      password: password
    }
    assert_response :redirect
    follow_redirect!
  end
end
