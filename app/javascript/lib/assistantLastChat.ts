const STORAGE_PREFIX = 'amplifa:assistant:last_chat'

const CHAT_PATH = /^\/assistant\/(\d+)$/

function storageKey(accountId: number, organizationId: number): string {
  return `${STORAGE_PREFIX}:${accountId}:${organizationId}`
}

export function getLastAssistantChatPath(
  accountId: number,
  organizationId: number
): string | null {
  if (typeof window === 'undefined') return null

  try {
    const value = sessionStorage.getItem(storageKey(accountId, organizationId))
    if (!value || !CHAT_PATH.test(value)) return null
    return value
  } catch {
    return null
  }
}

export function setLastAssistantChatPath(
  accountId: number,
  organizationId: number,
  chatId: number
): void {
  if (typeof window === 'undefined') return

  try {
    sessionStorage.setItem(storageKey(accountId, organizationId), `/assistant/${chatId}`)
  } catch {
    // Private mode or quota — navigation still works, just without recall.
  }
}

export function clearLastAssistantChatPath(
  accountId: number,
  organizationId: number,
  chatId: number
): void {
  if (getLastAssistantChatPath(accountId, organizationId) === `/assistant/${chatId}`) {
    if (typeof window === 'undefined') return

    try {
      sessionStorage.removeItem(storageKey(accountId, organizationId))
    } catch {
      // ignore
    }
  }
}

export function parseAssistantChatId(path: string): number | null {
  const match = path.match(CHAT_PATH)
  return match ? Number(match[1]) : null
}
