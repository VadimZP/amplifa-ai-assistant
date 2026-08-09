import { AssistantSavedPrompt } from '../components/Assistant/types'

const csrfToken = () =>
  document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content ?? ''

async function parseJson(response: Response) {
  return response.json() as Promise<{ error?: string; prompt?: AssistantSavedPrompt; prompts?: AssistantSavedPrompt[] }>
}

export function defaultSavedPromptTitle(prompt: string, maxLength = 80): string {
  const firstLine = prompt.trim().split(/\r?\n/, 1)[0]?.trim() ?? ''
  if (firstLine.length <= maxLength) return firstLine
  return `${firstLine.slice(0, maxLength - 1).trimEnd()}…`
}

export async function listAssistantSavedPrompts(): Promise<AssistantSavedPrompt[]> {
  const response = await fetch('/assistant/prompts', {
    headers: { Accept: 'application/json' },
  })

  const payload = await parseJson(response)
  if (!response.ok) throw new Error(payload.error)

  return payload.prompts ?? []
}

export async function createAssistantSavedPrompt(input: {
  title: string
  prompt: string
  welcome_pinned: boolean
}): Promise<AssistantSavedPrompt> {
  const response = await fetch('/assistant/prompts', {
    method: 'POST',
    headers: {
      Accept: 'application/json',
      'Content-Type': 'application/json',
      'X-CSRF-Token': csrfToken(),
    },
    body: JSON.stringify(input),
  })

  const payload = await parseJson(response)
  if (!response.ok || !payload.prompt) throw new Error(payload.error)

  return payload.prompt
}

export async function updateAssistantSavedPrompt(
  id: number,
  input: Partial<Pick<AssistantSavedPrompt, 'title' | 'prompt' | 'welcome_pinned' | 'position'>>
): Promise<AssistantSavedPrompt> {
  const response = await fetch(`/assistant/prompts/${id}`, {
    method: 'PATCH',
    headers: {
      Accept: 'application/json',
      'Content-Type': 'application/json',
      'X-CSRF-Token': csrfToken(),
    },
    body: JSON.stringify(input),
  })

  const payload = await parseJson(response)
  if (!response.ok || !payload.prompt) throw new Error(payload.error)

  return payload.prompt
}

export async function deleteAssistantSavedPrompt(id: number): Promise<void> {
  const response = await fetch(`/assistant/prompts/${id}`, {
    method: 'DELETE',
    headers: {
      Accept: 'application/json',
      'X-CSRF-Token': csrfToken(),
    },
  })

  if (response.ok) return

  const payload = await parseJson(response)
  throw new Error(payload.error)
}
