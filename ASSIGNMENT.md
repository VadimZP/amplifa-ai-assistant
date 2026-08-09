# Amplifa Takehome Assignment

## Goal

Build a **user-facing AI assistant**. Add a link to it in the top-level sidebar navigation.

It's for Amplifa end users and end user admins, NOT for Amplifa admins. (See README.md file for usernames and passwords.)

The assistant should be able to take actions in the app on behalf of the current user — anything the user can do in the UI, the assistant may do for them. **Nothing more**: the assistant must be strictly scoped to the current user's organization and permissions.

## Requirements

### 1. New sidebar screen

Add an "Assistant" (or similar) entry to the customer sidebar navigation. This should be a full page, not a modal or widget.

### 2. Conversational interface

The assistant screen should have a chat-style interface where the user can type natural language requests and receive responses. The user should be able to create new chats and resume previous ones. (ChatGPT style.)

### 3. Tool-enabled actions (critical)

The assistant must be able to take real actions in the app, not just answer questions. Examples of actions it could support:

- List, search, and analyze conversations in the inbox
- Update the interest status of a conversation
- Create or reschedule a meeting
- Search for leads
- Pause or resume an agent campaign
- Look up and revise playbook details

### 4. Permission scoping

The assistant must:

- Only access data belonging to the current user's organization
- Respect the same Pundit policies that the web UI enforces
- Never return data from another organization, even if a tool argument contains a foreign ID

## Starting Points

The codebase gives you several starting points:

**Pundit policies** (`app/policies/`) — the complete catalog of what each role can do. Use these as the source of truth for what the assistant is allowed to do.

**ruby_llm** — already configured. `Chat`, `Message`, `ToolCall`, and `Model` models are set up for persistence. See the [ruby_llm docs](https://rubyllm.com) for tool-calling patterns.

**MCP starter** (`app/services/mcp/assistant_tools.rb`) — 3 example tools showing the correct scoping pattern. You can extend these, use them as reference, or build your own tool layer entirely (in-process tools via ruby_llm are fine too).

## Deliverables

1. **Working code** — the assistant screen with at least 3 meaningful tools
2. **Tests** — covering the permission scoping (cross-org denial is the key test)
3. **SOLUTION.md** — a brief document explaining:
   - Your architecture decisions (in-process tools vs MCP, tool selection, how the LLM requests run, etc.)
   - How you handle permission scoping
   - What you would do differently with more time
   - Any tradeoffs you made

## Time Expectation

~6–8 hours. We're not looking for perfection — we're looking for clean thinking and something that works.

## Evaluation Criteria

| Criterion | Weight |
|-----------|--------|
| UX of the assistant screen | High |
| SOLUTION.md clarity | High |
| Infrastructure - would it scale to 10 users? 100? | High |
| Tool design and selection | Medium |
| Permission scoping correctness | High |
| Code quality (follows existing patterns) | Medium |
| Test coverage | Medium |

## Questions?

If requirements are ambiguous, document your assumptions in SOLUTION.md and proceed. For blocking technical issues, reach out.

## ⚠️ Git History Warning

When submitting your work, create a **fresh repository** with only your changes.

Good luck!
