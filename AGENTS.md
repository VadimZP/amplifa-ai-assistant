# AGENTS.md

This file provides guidance for AI coding assistants (Claude, Cursor, etc.) when working with this codebase.

## Project Overview

Amplifa is a Rails 8.1 + Inertia + React app for outbound email lead generation. This is the takehome assignment version.

## Key Technologies

- Rails 8.1, Rodauth (auth), Pundit (authorization)
- React 19, Inertia.js, TypeScript, Tailwind CSS
- ruby_llm for LLM integration
- PostgreSQL

## Frontend

The React app lives in `app/javascript/`. Never hard-code inline SVG icons — use Lucide icons. Never hard-code strings — use `t()` from `app/javascript/lib/i18n.ts`.

After any code change (frontend or backend), run: `npm run check` — it covers the TypeScript
typecheck, ESLint, and RuboCop in one command (see `.cursor/rules/verification.mdc`).

## Backend Commands

Use `rails` directly (or `mise exec -- rails` if using mise):

```bash
rails server
rails test
rails db:seed
rails db:schema:load
```

## i18n

Source translations live in `config/locales/*.yml`. After changing locale YAML, export to frontend:

```bash
mise exec -- i18n export --config config/i18n-js.yml
```

## Testing

```bash
rails test                              # full suite
rails test test/models/some_test.rb    # single file
```

When writing integration tests for Inertia.js requests, use the `inertia_headers` helper:

```ruby
get some_path, headers: inertia_headers
```

## Authorization

All authorization goes through Pundit. Policies live in `app/policies/`. The current user is `current_account`. The current organization is `Current.organization`.

When building tools for the AI assistant, always scope queries to `Current.organization` and authorize through the relevant Pundit policy.
