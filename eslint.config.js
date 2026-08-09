import eslint from '@eslint/js'
import reactHooks from 'eslint-plugin-react-hooks'
import globals from 'globals'
import tseslint from 'typescript-eslint'

export default tseslint.config(
  {
    ignores: ['app/javascript/locales/**', 'public/**', 'node_modules/**'],
  },
  {
    files: ['app/javascript/**/*.{ts,tsx}'],
    extends: [eslint.configs.recommended, tseslint.configs.recommended],
    plugins: {
      'react-hooks': reactHooks,
    },
    languageOptions: {
      globals: globals.browser,
    },
    rules: {
      'react-hooks/rules-of-hooks': 'error',
      'react-hooks/exhaustive-deps': 'warn',
      // `catch (e) {}` with an unused binding is fine; flagging every one adds noise, not safety.
      '@typescript-eslint/no-unused-vars': ['error', { caughtErrors: 'none', argsIgnorePattern: '^_' }],
    },
  },
  {
    // Legacy admin inbox pages type deep server payloads (lead, mailbox, sender) as `any`.
    // Retyping them is a standalone refactor; don't let it block the lint gate meanwhile.
    files: ['app/javascript/pages/Admin/Organizations/Replies/*.tsx'],
    rules: {
      '@typescript-eslint/no-explicit-any': 'off',
    },
  },
)
