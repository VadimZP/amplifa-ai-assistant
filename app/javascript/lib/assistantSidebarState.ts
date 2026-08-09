import { AssistantChat } from '../components/Assistant/types'

export interface SidebarPagination {
  extraChats: AssistantChat[]
  loadedPages: number
  hasMoreChats: boolean
}

interface OrgSidebarState {
  pagination: SidebarPagination
  scrollTop: number
}

const stateByOrg = new Map<number, OrgSidebarState>()

function defaultPagination(hasMoreChats: boolean): SidebarPagination {
  return { extraChats: [], loadedPages: 1, hasMoreChats }
}

export function readSidebarState(
  organizationId: number | undefined,
  hasMoreChats: boolean
): OrgSidebarState {
  if (!organizationId) {
    return { pagination: defaultPagination(hasMoreChats), scrollTop: 0 }
  }

  return stateByOrg.get(organizationId) ?? {
    pagination: defaultPagination(hasMoreChats),
    scrollTop: 0,
  }
}

export function writeSidebarPagination(organizationId: number, pagination: SidebarPagination): void {
  const current = stateByOrg.get(organizationId)
  stateByOrg.set(organizationId, {
    pagination,
    scrollTop: current?.scrollTop ?? 0,
  })
}

export function writeSidebarScrollTop(organizationId: number, scrollTop: number): void {
  const current = stateByOrg.get(organizationId)
  stateByOrg.set(organizationId, {
    pagination: current?.pagination ?? defaultPagination(true),
    scrollTop,
  })
}

export function clearSidebarState(organizationId: number): void {
  stateByOrg.delete(organizationId)
}

export function pruneSidebarChat(organizationId: number, chatId: number): void {
  const current = stateByOrg.get(organizationId)
  if (!current) return

  stateByOrg.set(organizationId, {
    ...current,
    pagination: {
      ...current.pagination,
      extraChats: current.pagination.extraChats.filter(chat => chat.id !== chatId),
    },
  })
}
