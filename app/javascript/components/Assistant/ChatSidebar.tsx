import { useCallback, useLayoutEffect, useRef } from 'react'
import { Link } from '@inertiajs/react'
import { MessageSquare, Pin, Plus, Trash2, X } from 'lucide-react'
import { Button } from '../ui/Button'
import { readSidebarState, writeSidebarScrollTop } from '../../lib/assistantSidebarState'
import { t } from '../../lib/i18n'
import { AssistantChat } from './types'

interface ChatSidebarProps {
  chats: AssistantChat[]
  selectedChatId: number | null
  organizationId?: number
  /** Chat currently awaiting a delete confirmation, or null. */
  pendingDeleteId: number | null
  deletingId: number | null
  pinningId: number | null
  hasMoreChats: boolean
  loadingMoreChats: boolean
  onNewChat: () => void
  onRequestDelete: (chatId: number) => void
  onCancelDelete: () => void
  onConfirmDelete: (chatId: number) => void
  onTogglePin: (chatId: number, pinned: boolean) => void
  onLoadMore: () => void
  /** Called after navigating, so the mobile drawer can close itself. */
  onNavigate?: () => void
}

export function ChatSidebar({
  chats,
  selectedChatId,
  organizationId,
  pendingDeleteId,
  deletingId,
  pinningId,
  hasMoreChats,
  loadingMoreChats,
  onNewChat,
  onRequestDelete,
  onCancelDelete,
  onConfirmDelete,
  onTogglePin,
  onLoadMore,
  onNavigate,
}: ChatSidebarProps) {
  const listRef = useRef<HTMLDivElement>(null)

  const persistScroll = useCallback(() => {
    if (!organizationId || !listRef.current) return
    writeSidebarScrollTop(organizationId, listRef.current.scrollTop)
  }, [organizationId])

  // WHY after chat list updates: Inertia remounts this page on /assistant/:id visits, which resets
  // the div's scrollTop to 0 even when pagination state is restored from the module cache.
  useLayoutEffect(() => {
    if (!organizationId || !listRef.current) return
    listRef.current.scrollTop = readSidebarState(organizationId, hasMoreChats).scrollTop
  }, [organizationId, hasMoreChats, chats.length, selectedChatId])

  const handleNavigate = useCallback(() => {
    persistScroll()
    onNavigate?.()
  }, [onNavigate, persistScroll])

  return (
    <div className="flex h-full min-h-0 flex-col">
      <div className="shrink-0 px-3 pt-3">
        <Button
          variant="secondary"
          fullWidth
          icon={<Plus className="size-4" aria-hidden />}
          onClick={onNewChat}
        >
          {t('assistant.new_chat')}
        </Button>
      </div>

      <div
        ref={listRef}
        onScroll={persistScroll}
        className="custom-scrollbar mt-3 min-h-0 flex-1 overflow-y-auto px-3 pb-3"
      >
        {chats.length === 0 ? (
          <div className="px-2 py-8 text-center">
            <MessageSquare
              className="mx-auto size-6 text-[var(--foreground-subtle)]"
              aria-hidden
            />
            <p className="mt-3 text-sm text-[var(--foreground-muted)]">{t('assistant.no_chats')}</p>
            <p className="mt-1 text-xs text-[var(--foreground-subtle)]">{t('assistant.no_chats_hint')}</p>
          </div>
        ) : (
          <ul className="flex flex-col gap-1">
            {chats.map(chat => {
              const active = chat.id === selectedChatId
              const title = chat.title || t('assistant.untitled_chat')
              const confirming = pendingDeleteId === chat.id
              const pinLabel = chat.pinned ? t('assistant.unpin_chat') : t('assistant.pin_chat')

              return (
                <li key={chat.id}>
                  {confirming ? (
                    // WHY inline confirm rather than window.confirm: the UI/UX rule requires a
                    // destructive action to name what is being deleted and stay in the page.
                    <div className="rounded-xl border border-[var(--error)]/30 bg-[var(--error-muted)] p-2.5">
                      <p className="text-xs leading-4 text-[var(--foreground)]">
                        {t('assistant.delete_chat_confirm_named', { title })}
                      </p>
                      <div className="mt-2 flex gap-2">
                        <Button
                          size="sm"
                          variant="destructive"
                          loading={deletingId === chat.id}
                          onClick={() => onConfirmDelete(chat.id)}
                        >
                          {t('common.delete')}
                        </Button>
                        <Button size="sm" variant="ghost" onClick={onCancelDelete}>
                          {t('common.cancel')}
                        </Button>
                      </div>
                    </div>
                  ) : (
                    <div
                      className={`group flex items-center gap-1 rounded-xl transition-colors ${
                        active ? 'bg-white/[0.08]' : 'hover:bg-white/[0.04]'
                      }`}
                    >
                      <Link
                        href={`/assistant/${chat.id}`}
                        preserveScroll
                        preserveState
                        onClick={handleNavigate}
                        aria-current={active ? 'page' : undefined}
                        className={`min-w-0 flex-1 truncate rounded-xl px-3 py-2.5 text-sm transition-colors ${
                          active
                            ? 'text-[var(--foreground)]'
                            : 'text-[var(--foreground-muted)] group-hover:text-[var(--foreground)]'
                        }`}
                      >
                        {title}
                      </Link>
                      <button
                        type="button"
                        aria-label={pinLabel}
                        title={pinLabel}
                        disabled={pinningId === chat.id}
                        onClick={() => onTogglePin(chat.id, !chat.pinned)}
                        data-pinned={chat.pinned ? 'true' : 'false'}
                        className="shrink-0 rounded-lg p-1.5 text-[var(--foreground-subtle)] opacity-0 transition-all hover:bg-white/[0.06] hover:text-[var(--accent)] focus-visible:opacity-100 group-hover:opacity-100 data-[pinned=true]:text-[var(--accent)] data-[pinned=true]:opacity-100 disabled:opacity-50"
                      >
                        <Pin className="size-4" aria-hidden />
                      </button>
                      <button
                        type="button"
                        aria-label={t('assistant.delete_chat')}
                        title={t('assistant.delete_chat')}
                        onClick={() => onRequestDelete(chat.id)}
                        className="mr-1.5 shrink-0 rounded-lg p-1.5 text-[var(--foreground-subtle)] opacity-0 transition-all hover:bg-white/[0.06] hover:text-[var(--error)] focus-visible:opacity-100 group-hover:opacity-100"
                      >
                        <Trash2 className="size-4" aria-hidden />
                      </button>
                    </div>
                  )}
                </li>
              )
            })}
            {hasMoreChats && (
              <li className="pt-1">
                <Button
                  variant="secondary"
                  size="sm"
                  fullWidth
                  loading={loadingMoreChats}
                  onClick={onLoadMore}
                >
                  {t('assistant.load_more_chats')}
                </Button>
              </li>
            )}
          </ul>
        )}
      </div>
    </div>
  )
}

interface ChatSidebarDrawerProps extends ChatSidebarProps {
  open: boolean
  onClose: () => void
}

/**
 * Below `lg` the chat list becomes an overlay drawer, so the conversation keeps the full width on
 * phones. Rendering it unconditionally (hidden with CSS) would trap the close button in the tab
 * order, so it is mounted only while open.
 */
export function ChatSidebarDrawer({ open, onClose, ...sidebarProps }: ChatSidebarDrawerProps) {
  if (!open) return null

  return (
    <div className="absolute inset-0 z-30 flex lg:hidden">
      <button
        type="button"
        aria-label={t('common.close')}
        className="absolute inset-0 bg-black/60"
        onClick={onClose}
      />
      <div className="relative z-10 flex h-full w-[85%] max-w-xs flex-col border-r border-white/[0.06] bg-[var(--background-elevated)]">
        <div className="flex shrink-0 items-center justify-between px-4 pt-4">
          <span className="text-sm font-medium text-[var(--foreground)]">{t('assistant.chats')}</span>
          <button
            type="button"
            aria-label={t('assistant.hide_chats')}
            onClick={onClose}
            className="rounded-lg p-1.5 text-[var(--foreground-muted)] transition-colors hover:bg-white/[0.06] hover:text-[var(--foreground)]"
          >
            <X className="size-4" aria-hidden />
          </button>
        </div>
        <div className="min-h-0 flex-1">
          <ChatSidebar {...sidebarProps} onNavigate={onClose} />
        </div>
      </div>
    </div>
  )
}

export default ChatSidebar
