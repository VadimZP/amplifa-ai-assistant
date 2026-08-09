import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { router, usePage } from '@inertiajs/react'
import { PanelLeft, Sparkles } from 'lucide-react'
import AuthenticatedLayout from '../../layouts/AuthenticatedLayout'
import { ChatSidebar, ChatSidebarDrawer } from '../../components/Assistant/ChatSidebar'
import { Conversation } from '../../components/Assistant/Conversation'
import { NewChatPane } from '../../components/Assistant/NewChatPane'
import { SavedPromptsSlideOver } from '../../components/Assistant/SavedPromptsSlideOver'
import { AssistantChat, AssistantMessage, AssistantSavedPrompt } from '../../components/Assistant/types'
import { toast } from '../../components/ui/Toaster'
import { clearLastAssistantChatPath } from '../../lib/assistantLastChat'
import {
  clearSidebarState,
  pruneSidebarChat,
  readSidebarState,
  writeSidebarPagination,
} from '../../lib/assistantSidebarState'
import { t } from '../../lib/i18n'

interface Account {
  id: number
  email: string
  first_name: string
  last_name: string
  full_name: string
  role: string
  'amplifa_admin?'?: boolean
}

// WHY: `account` is an Inertia shared prop (see ApplicationController's `inertia_share`), not part of
// the page props — reading it from page props leaves it undefined and crashes AuthenticatedLayout.
interface SharedProps {
  [key: string]: unknown
  auth: {
    account: Account
    current_organization?: { id: number }
  }
  flash?: { notice?: string; alert?: string }
}

interface Props {
  chats: AssistantChat[]
  has_more_chats: boolean
  selected_chat_id: number | null
  messages: AssistantMessage[]
  has_more_messages: boolean
  user_first_name: string
  max_prompt_length: number
  saved_prompts: AssistantSavedPrompt[]
}

const csrfToken = () =>
  document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content ?? ''

function sortChats(list: AssistantChat[]): AssistantChat[] {
  return [...list].sort((left, right) => {
    if (left.pinned !== right.pinned) return left.pinned ? -1 : 1

    const leftAt = left.last_message_at ?? left.created_at
    const rightAt = right.last_message_at ?? right.created_at
    if (leftAt !== rightAt) return rightAt.localeCompare(leftAt)

    return right.id - left.id
  })
}

export default function Index({
  chats,
  has_more_chats,
  selected_chat_id,
  messages,
  has_more_messages,
  user_first_name,
  max_prompt_length,
  saved_prompts,
}: Props) {
  const { auth, flash } = usePage<SharedProps>().props
  const organizationId = auth.current_organization?.id
  const cachedSidebar = readSidebarState(organizationId, has_more_chats)

  // WHY only the titles live in state, and never the chat list itself: Inertia reuses this component
  // instance across visits to the same page, so a `useState(chats)` mirror would freeze at whatever
  // the list was on first mount. After posting the first prompt the server redirects to the new chat,
  // and the stale mirror would not contain it — `selectedChat` came back null and the page kept
  // rendering the welcome pane until a hard reload. Props are the source of truth; the override map
  // only layers on titles that arrived over the cable, which props do not know about yet.
  const [titleOverrides, setTitleOverrides] = useState<Record<number, string>>({})
  const [drawerOpen, setDrawerOpen] = useState(false)
  const [creating, setCreating] = useState(false)
  const [newChatPaneKey, setNewChatPaneKey] = useState(0)
  const [pendingDeleteId, setPendingDeleteId] = useState<number | null>(null)
  const [deletingId, setDeletingId] = useState<number | null>(null)
  const [extraChats, setExtraChats] = useState<AssistantChat[]>(
    () => cachedSidebar.pagination.extraChats
  )
  const [hasMoreChats, setHasMoreChats] = useState(
    () => cachedSidebar.pagination.hasMoreChats
  )
  const [loadingMoreChats, setLoadingMoreChats] = useState(false)
  const [pinningId, setPinningId] = useState<number | null>(null)
  const [loadedPages, setLoadedPages] = useState(() => cachedSidebar.pagination.loadedPages)
  const [pinOverrides, setPinOverrides] = useState<Record<number, boolean>>({})
  const [savedPrompts, setSavedPrompts] = useState(saved_prompts)
  const [promptsSlideOverOpen, setPromptsSlideOverOpen] = useState(false)
  const [promptDraftForSave, setPromptDraftForSave] = useState('')
  const [editingPrompt, setEditingPrompt] = useState<AssistantSavedPrompt | null>(null)

  const previousOrganizationIdRef = useRef<number | undefined>(undefined)

  useEffect(() => {
    setSavedPrompts(saved_prompts)
  }, [saved_prompts])

  // WHY org-scoped reset only: Inertia remounts this page on /assistant/:id visits, so pagination
  // must live in the module cache (see assistantSidebarState.ts) and only clear on workspace switch.
  useEffect(() => {
    if (previousOrganizationIdRef.current === undefined) {
      previousOrganizationIdRef.current = organizationId
      return
    }

    if (previousOrganizationIdRef.current === organizationId) return

    clearSidebarState(previousOrganizationIdRef.current)
    previousOrganizationIdRef.current = organizationId

    const fresh = readSidebarState(organizationId, has_more_chats)
    setExtraChats(fresh.pagination.extraChats)
    setLoadedPages(fresh.pagination.loadedPages)
    setHasMoreChats(fresh.pagination.hasMoreChats)
    setPinOverrides({})
    setSavedPrompts(saved_prompts)
  }, [organizationId, has_more_chats, saved_prompts])

  useEffect(() => {
    if (!organizationId) return
    writeSidebarPagination(organizationId, { extraChats, loadedPages, hasMoreChats })
  }, [organizationId, extraChats, loadedPages, hasMoreChats])

  useEffect(() => {
    if (loadedPages === 1) setHasMoreChats(has_more_chats)
  }, [has_more_chats, loadedPages])

  const chatList = useMemo(() => {
    const merged = new Map<number, AssistantChat>()

    for (const chat of chats) {
      merged.set(chat.id, chat)
    }
    for (const chat of extraChats) {
      if (!merged.has(chat.id)) merged.set(chat.id, chat)
    }

    const withOverrides = Array.from(merged.values()).map(chat => {
      const next: AssistantChat = { ...chat }
      if (titleOverrides[chat.id]) next.title = titleOverrides[chat.id]
      if (chat.id in pinOverrides) next.pinned = pinOverrides[chat.id]
      return next
    })

    return sortChats(withOverrides)
  }, [chats, extraChats, titleOverrides, pinOverrides])

  const selectedChat = useMemo(
    () => chatList.find(chat => chat.id === selected_chat_id) ?? null,
    [chatList, selected_chat_id]
  )

  // WHY the flash is replayed as a toast: `destroy` redirects here with a notice, but the assistant
  // suppresses the layout's inline banner (it shoves the chat UI down and never dismisses). The ref
  // guards against re-toasting the same flash when props change for an unrelated reason.
  const shownFlashRef = useRef<string | null>(null)

  useEffect(() => {
    const message = flash?.notice || flash?.alert
    if (!message || shownFlashRef.current === message) return

    shownFlashRef.current = message
    if (flash?.notice) toast.success(message)
    else toast.error(message)
  }, [flash?.notice, flash?.alert])

  const handleTitle = useCallback((chatId: number, title: string) => {
    setTitleOverrides(current => (current[chatId] === title ? current : { ...current, [chatId]: title }))
  }, [])

  // WHY navigate for "New chat" but POST only on first submit: creating a row on every button click
  // would let users spam empty chats into the database.
  const openNewChat = useCallback(() => {
    setDrawerOpen(false)
    setNewChatPaneKey(key => key + 1)
    router.visit('/assistant')
  }, [])

  const createChatWithPrompt = useCallback(
    (prompt: string) => {
      const trimmed = prompt.trim()
      if (!trimmed || creating) return

      setCreating(true)
      setDrawerOpen(false)
      router.post(
        '/assistant/chats',
        { prompt: trimmed },
        {
          onError: () => toast.error(String(t('assistant.errors.create_chat'))),
          onFinish: () => setCreating(false),
        }
      )
    },
    [creating]
  )

  const handleConfirmDelete = (chatId: number) => {
    if (deletingId) return

    setDeletingId(chatId)
    router.delete(`/assistant/chats/${chatId}`, {
      onError: () => toast.error(String(t('assistant.errors.delete_chat'))),
      onSuccess: () => {
        setExtraChats(current => current.filter(chat => chat.id !== chatId))
        if (organizationId) pruneSidebarChat(organizationId, chatId)
      },
      onFinish: () => {
        if (organizationId) {
          clearLastAssistantChatPath(auth.account.id, organizationId, chatId)
        }
        setDeletingId(null)
        setPendingDeleteId(null)
      },
    })
  }

  const handleTogglePin = useCallback(async (chatId: number, pinned: boolean) => {
    if (pinningId) return

    setPinningId(chatId)
    setPinOverrides(current => ({ ...current, [chatId]: pinned }))

    try {
      const response = await fetch(`/assistant/chats/${chatId}/pin`, {
        method: 'PATCH',
        headers: {
          Accept: 'application/json',
          'Content-Type': 'application/json',
          'X-CSRF-Token': csrfToken(),
        },
        body: JSON.stringify({ pinned }),
      })

      const payload = (await response.json()) as { chat?: AssistantChat; error?: string }

      if (!response.ok || !payload.chat) {
        throw new Error(payload.error || String(t('assistant.errors.pin_chat')))
      }

      setPinOverrides(current => ({ ...current, [chatId]: payload.chat!.pinned }))
      setExtraChats(current =>
        current.map(chat => (chat.id === chatId ? { ...chat, pinned: payload.chat!.pinned } : chat))
      )
    } catch (error) {
      setPinOverrides(current => {
        const next = { ...current }
        delete next[chatId]
        return next
      })
      toast.error(
        error instanceof Error ? error.message : String(t('assistant.errors.pin_chat'))
      )
    } finally {
      setPinningId(null)
    }
  }, [pinningId])

  const handleLoadMore = useCallback(async () => {
    if (loadingMoreChats || !hasMoreChats) return

    setLoadingMoreChats(true)
    const nextPage = loadedPages + 1

    try {
      const response = await fetch(`/assistant/chats?page=${nextPage}`, {
        headers: { Accept: 'application/json' },
      })

      const payload = (await response.json()) as {
        chats?: AssistantChat[]
        has_more?: boolean
        error?: string
      }

      if (!response.ok || !payload.chats) {
        throw new Error(payload.error || String(t('assistant.errors.load_more_chats')))
      }

      setExtraChats(current => {
        const seen = new Set([...chats, ...current].map(chat => chat.id))
        const appended = payload.chats!.filter(chat => !seen.has(chat.id))
        return [...current, ...appended]
      })
      setHasMoreChats(Boolean(payload.has_more))
      setLoadedPages(nextPage)
    } catch (error) {
      toast.error(
        error instanceof Error ? error.message : String(t('assistant.errors.load_more_chats'))
      )
    } finally {
      setLoadingMoreChats(false)
    }
  }, [chats, hasMoreChats, loadedPages, loadingMoreChats])

  const openManagePrompts = useCallback(() => {
    setEditingPrompt(null)
    setPromptDraftForSave('')
    setPromptsSlideOverOpen(true)
  }, [])

  const openSavePrompt = useCallback((prompt: string) => {
    const trimmed = prompt.trim()
    if (!trimmed) return

    setEditingPrompt(null)
    setPromptDraftForSave(trimmed)
    setPromptsSlideOverOpen(true)
  }, [])

  const sidebarProps = {
    chats: chatList,
    selectedChatId: selected_chat_id,
    organizationId,
    pendingDeleteId,
    deletingId,
    pinningId,
    hasMoreChats,
    loadingMoreChats,
    onNewChat: openNewChat,
    onRequestDelete: setPendingDeleteId,
    onCancelDelete: () => setPendingDeleteId(null),
    onConfirmDelete: handleConfirmDelete,
    onTogglePin: handleTogglePin,
    onLoadMore: handleLoadMore,
  }

  return (
    <AuthenticatedLayout
      title={t('assistant.page_title')}
      account={auth.account}
      flash={flash}
      fullBleed
      hideHeader
    >
      {/* `relative` anchors the mobile drawer overlay to the chat area rather than the viewport. */}
      <div className="relative flex min-h-0 flex-1 overflow-hidden">
        <aside className="hidden w-72 shrink-0 border-r border-white/[0.06] lg:flex lg:flex-col">
          <ChatSidebar {...sidebarProps} />
        </aside>

        <ChatSidebarDrawer {...sidebarProps} open={drawerOpen} onClose={() => setDrawerOpen(false)} />

        <section className="flex min-h-0 min-w-0 flex-1 flex-col">
          <header className="flex shrink-0 items-center gap-2 border-b border-white/[0.06] px-4 py-3 sm:px-6">
            <button
              type="button"
              aria-label={t('assistant.show_chats')}
              onClick={() => setDrawerOpen(true)}
              className="-ml-1.5 rounded-lg p-1.5 text-[var(--foreground-muted)] transition-colors hover:bg-white/[0.06] hover:text-[var(--foreground)] lg:hidden"
            >
              <PanelLeft className="size-4" aria-hidden />
            </button>
            <Sparkles className="size-4 shrink-0 text-[var(--accent)]" aria-hidden />
            <h2 className="min-w-0 truncate text-sm font-medium text-[var(--foreground)]">
              {selectedChat?.title || t('assistant.page_title')}
            </h2>
          </header>

          {selectedChat ? (
            <Conversation
              key={selectedChat.id}
              chatId={selectedChat.id}
              initialMessages={messages}
              initialHasMore={has_more_messages}
              initialStreaming={selectedChat.streaming}
              firstName={user_first_name}
              maxPromptLength={max_prompt_length}
              savedPrompts={savedPrompts}
              onTitle={handleTitle}
              onManagePrompts={openManagePrompts}
              onSavePrompt={openSavePrompt}
            />
          ) : (
            <NewChatPane
              key={newChatPaneKey}
              firstName={user_first_name}
              maxPromptLength={max_prompt_length}
              savedPrompts={savedPrompts}
              onStart={createChatWithPrompt}
              onManagePrompts={openManagePrompts}
              onSavePrompt={openSavePrompt}
              creating={creating}
            />
          )}
        </section>
      </div>

      <SavedPromptsSlideOver
        open={promptsSlideOverOpen}
        onClose={() => {
          setPromptsSlideOverOpen(false)
          setPromptDraftForSave('')
          setEditingPrompt(null)
        }}
        prompts={savedPrompts}
        maxPromptLength={max_prompt_length}
        draftPrompt={promptDraftForSave}
        editingPrompt={editingPrompt}
        onPromptsChange={setSavedPrompts}
      />
    </AuthenticatedLayout>
  )
}
