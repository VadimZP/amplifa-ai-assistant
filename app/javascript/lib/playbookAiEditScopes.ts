import { t } from './i18n'

export type PlaybookAiEditScope =
  | 'entire_playbook'
  | 'product_description'
  | 'value_proposition'
  | 'personae'
  | 'use_cases'
  | 'references'
  | 'proof_points'

export const playbookAiEditScopeOptions: Array<{ value: PlaybookAiEditScope; labelKey: string }> = [
  { value: 'entire_playbook', labelKey: 'admin.playbooks.ai_edit.scopes.entire_playbook' },
  { value: 'product_description', labelKey: 'admin.playbooks.ai_edit.scopes.product_description' },
  { value: 'value_proposition', labelKey: 'admin.playbooks.ai_edit.scopes.value_proposition' },
  { value: 'personae', labelKey: 'admin.playbooks.ai_edit.scopes.personae' },
  { value: 'use_cases', labelKey: 'admin.playbooks.ai_edit.scopes.use_cases' },
  { value: 'references', labelKey: 'admin.playbooks.ai_edit.scopes.references' },
  { value: 'proof_points', labelKey: 'admin.playbooks.ai_edit.scopes.proof_points' }
]

export const playbookAiEditScopeLabel = (scope: PlaybookAiEditScope) => {
  const option = playbookAiEditScopeOptions.find((entry) => entry.value === scope)
  return t(option?.labelKey || 'admin.playbooks.ai_edit.scopes.entire_playbook')
}
