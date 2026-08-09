import { useCallback, useState } from 'react'
import { Composer } from './Composer'
import { WelcomeScreen } from './WelcomeScreen'
import { AssistantSavedPrompt } from './types'

interface NewChatPaneProps {
  firstName: string
  maxPromptLength: number
  savedPrompts: AssistantSavedPrompt[]
  /** Creates the chat and seeds it with the first prompt. */
  onStart: (prompt: string) => void
  onManagePrompts: () => void
  onSavePrompt: (prompt: string) => void
  creating: boolean
}

/**
 * Shown on /assistant when no chat is selected. It carries a real composer so the first prompt both
 * creates the chat and asks the question, rather than making the user type twice.
 */
export function NewChatPane({
  firstName,
  maxPromptLength,
  savedPrompts,
  onStart,
  onManagePrompts,
  onSavePrompt,
  creating,
}: NewChatPaneProps) {
  const [draft, setDraft] = useState('')
  const [focusToken, setFocusToken] = useState(0)

  const handleSuggestion = useCallback((prompt: string) => {
    setDraft(prompt)
    setFocusToken(token => token + 1)
  }, [])

  return (
    <>
      <div className="custom-scrollbar min-h-0 flex-1 overflow-y-auto">
        <WelcomeScreen
          firstName={firstName}
          savedPrompts={savedPrompts}
          onSuggestion={handleSuggestion}
          onManagePrompts={onManagePrompts}
        />
      </div>

      <Composer
        value={draft}
        onChange={setDraft}
        onSubmit={() => onStart(draft.trim())}
        onSavePrompt={() => onSavePrompt(draft.trim())}
        busy={creating}
        maxLength={maxPromptLength}
        focusToken={focusToken}
      />
    </>
  )
}

export default NewChatPane
