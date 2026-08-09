import { t } from './i18n'

export interface PlaybookFeedbackContext {
  tab: 'training_data' | 'samples' | 'import_leads' | 'knowledge_base'
  lead_id?: number | null
  lead_name?: string | null
  message_id?: number | null
  step_label?: string | null
  step_position?: number | null
  agent_id?: number | null
  agent_name?: string | null
}

const tabLabel = (tab: PlaybookFeedbackContext['tab']) => {
  switch (tab) {
    case 'training_data':
      return t('playbooks.tabs.training_data')
    case 'samples':
      return t('playbooks.tabs.sample_leads_messages')
    case 'import_leads':
      return t('playbooks.tabs.import_leads')
    case 'knowledge_base':
      return t('playbooks.tabs.knowledge_base')
  }
}

export const getPlaybookFeedbackContextLabel = (context?: PlaybookFeedbackContext | null) => {
  if (!context?.tab) return null

  const parts = [tabLabel(context.tab)]

  if (context.lead_name) {
    parts.push(context.lead_name)
  }

  if (context.step_label) {
    parts.push(context.step_label)
  } else if (context.step_position) {
    parts.push(`Step ${context.step_position}`)
  }

  return parts.join(' · ')
}

export const buildCustomerPlaybookFeedbackHref = (playbookId: number, context?: PlaybookFeedbackContext | null) => {
  if (!context?.tab) return null

  const path = (() => {
    switch (context.tab) {
      case 'training_data':
        return `/playbooks/${playbookId}`
      case 'samples':
        return `/playbooks/${playbookId}/samples`
      case 'import_leads':
        return `/playbooks/${playbookId}/import_leads`
      case 'knowledge_base':
        return `/playbooks/${playbookId}/knowledge-base`
    }
  })()

  const params = new URLSearchParams()

  if (context.lead_id) {
    params.set('lead_id', String(context.lead_id))
  }

  if (context.message_id) {
    params.set('message_id', String(context.message_id))
  }

  const query = params.toString()
  return query ? `${path}?${query}` : path
}

export const buildAdminPlaybookFeedbackHref = (
  organizationId: number,
  playbookId: number,
  context?: PlaybookFeedbackContext | null
) => {
  if (!context?.tab) return null

  if (context.tab === 'training_data') {
    return `/admin/organizations/${organizationId}/playbooks/${playbookId}`
  }

  if (context.tab === 'samples' && context.agent_id) {
    const params = new URLSearchParams()

    if (context.lead_id) {
      params.set('lead_id', String(context.lead_id))
    }

    if (context.message_id) {
      params.set('message_id', String(context.message_id))
    }

    const query = params.toString()
    const path = `/admin/organizations/${organizationId}/agents/${context.agent_id}/sample_messages`
    return query ? `${path}?${query}` : path
  }

  return null
}
