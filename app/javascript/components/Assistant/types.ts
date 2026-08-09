/**
 * Shared types for the assistant. Mirrors the JSON that AssistantController serializes
 * (`chat_json` / `message_json`) and the frames AssistantChatChannel broadcasts.
 */

export interface AssistantChat {
  id: number
  title: string | null
  streaming: boolean
  pinned: boolean
  last_message_at: string | null
  created_at: string
}

export type AssistantMessageRole = 'user' | 'assistant'

export interface AssistantMessage {
  id: number
  role: AssistantMessageRole
  content: string
  created_at: string
}

export interface AssistantSavedPrompt {
  id: number
  title: string
  prompt: string
  welcome_pinned: boolean
  position: number
  updated_at: string
}

/**
 * One tool invocation within an assistant turn, as tracked client-side from tool_start/tool_end
 * frames. Ephemeral: tool activity is not persisted, so chips disappear on reload.
 */
export interface AssistantToolEvent {
  callId: string
  tool: string
  status: 'running' | 'ok' | 'error'
}

/** Cable frames pushed by AssistantReplyService, AssistantReplyJob and AssistantTitleJob. */
export type AssistantStreamFrame =
  | { type: 'start'; message_id: number }
  | { type: 'delta'; message_id: number; content: string }
  | { type: 'done'; message_id: number; content: string }
  | { type: 'error'; error: string }
  | { type: 'title'; title: string }
  | { type: 'tool_start'; message_id: number; call_id: string; tool: string }
  | { type: 'tool_end'; message_id: number; call_id: string; tool: string; status: 'ok' | 'error' }
