# Amplifa

Amplifa is an outbound lead generation platform for sales teams. This repository is a Rails + React application where customer users manage email campaigns, inbox conversations, playbooks, meetings, and an AI assistant that can take actions on their behalf.

## Tech stack

| Layer | Technologies |
|-------|--------------|
| Backend | Rails 8.1, PostgreSQL, Rodauth, Pundit |
| Frontend | React 19, Inertia.js, TypeScript, Tailwind CSS v4, Vite |
| AI | [ruby_llm](https://github.com/crmne/ruby_llm) via OpenRouter |
| Realtime | ActionCable (Solid Cable) |

## Prerequisites

Install these before setting up the project:

| Tool | Version | Notes |
|------|---------|-------|
| Ruby | **3.4.7** | See `.ruby-version` |
| Node.js | **22+** | See `package.json` engines |
| npm | **10+** | Bundled with Node 22 |
| PostgreSQL | **14+** | Required for all environments |
| Process manager | Optional | `overmind`, `hivemind`, or `foreman` for `bin/dev` |

Recommended version managers:

- **Ruby**: [mise](https://mise.jdx.dev/), [rbenv](https://github.com/rbenv/rbenv), or [asdf](https://asdf-vm.com/)
- **Node.js**: mise, [nvm](https://github.com/nvm-sh/nvm), or asdf

### Install PostgreSQL

**macOS (Homebrew)**

```bash
brew install postgresql@16
brew services start postgresql@16
```

**Ubuntu / Debian**

```bash
sudo apt update
sudo apt install postgresql postgresql-contrib
sudo systemctl start postgresql
```

**Verify PostgreSQL is running**

```bash
psql -d postgres -c "SELECT 1"
```

If that fails, start the PostgreSQL service for your OS and try again.

---

## Step-by-step setup

### 1. Clone the repository

```bash
git clone <repository-url>
cd amplifa-takehome
```

### 2. Install Ruby and Node

Use your version manager to install the pinned versions:

```bash
# Example with mise
mise install

# Or manually
ruby -v   # should print 3.4.7
node -v   # should print v22.x or newer
npm -v    # should print 10.x or newer
```

### 3. Configure PostgreSQL access

The app connects as the PostgreSQL role `amplifa` (see `config/database.yml`).

`bin/setup` will try to create this role automatically if it can connect as an admin user (`$PGUSER`, your OS username, or `postgres`). You can also create it yourself:

```bash
createuser -s amplifa
```

If your PostgreSQL installation requires a password, configure passwordless local access or set `PGPASSWORD` before running setup.

**Custom host or port**

```bash
export PGHOST=localhost
export PGPORT=5432
```

### 4. Run the setup script

From the project root:

```bash
bin/setup
```

This script is idempotent — safe to run more than once. It will:

1. Verify PostgreSQL is reachable
2. Ensure the `amplifa` role exists
3. Create development databases:
   - `amplifa_takehome_development`
   - `amplifa_takehome_development_cache`
   - `amplifa_takehome_development_cable`
4. Run `bundle install`
5. Run `npm install`
6. Run `bin/rails db:prepare` (load schema / migrate)
7. Run `bin/rails db:seed` (sample organizations, users, and demo data)

When seeding finishes, the script prints a table of login credentials (all seeded users share the same password).

### 5. Configure the LLM API key (optional for boot, required for AI features)

The app boots, seeds, and runs tests **without** an API key. You only need one when using the AI assistant or other LLM-powered features.

**Option A — environment variable (recommended for local dev)**

```bash
export OPENROUTER_API_KEY=sk-or-v1-...
```

Add that line to your shell profile (`~/.zshrc`, `~/.bashrc`, etc.) to persist it.

**Option B — Rails credentials**

Development credentials are already encrypted in the repo (`config/credentials/development.key` is included for local use):

```bash
EDITOR="code --wait" bin/rails credentials:edit --environment development
```

Add:

```yaml
openrouter:
  api_key: sk-or-v1-...
```

Get an API key at [openrouter.ai](https://openrouter.ai/).

The default model is `deepseek/deepseek-v4-flash`.

### 6. Start the development server

The app runs two processes: Rails (port 3000) and the Vite dev server for frontend assets.

**Recommended — single command**

```bash
bin/dev
```

`bin/dev` uses `overmind`, `hivemind`, or `foreman` (installed automatically if missing) to start both processes from `Procfile.dev`.

**Alternative — two terminals**

```bash
# Terminal 1
PORT=3000 bin/rails server

# Terminal 2
bin/vite dev
```

### 7. Open the app

Visit [http://localhost:3000](http://localhost:3000) and sign in with one of the seeded accounts below.

---

## Login credentials

All seeded users use the password **`password123!`**.

| Role | Email |
|------|-------|
| Amplifa Admin | `admin@amplifa.com` |
| Customer Admin (Northwind Robotics) | `nina@northwind-robotics.example` |
| Customer User (Northwind Robotics) | `noah@northwind-robotics.example` |
| Customer Admin (Sunrise Analytics) | `sam@sunrise-analytics.example` |
| Dual-Membership User | `dana@consultants.example` |

**Customer surface** — sign in as `nina` or `noah` to explore inbox, agents, playbooks, meetings, ROI, and the assistant.

**Admin surface** — sign in as `admin@amplifa.com` for organization management, user management, and impersonation.

---

## Development workflow

### Common commands

```bash
bin/dev                    # Start Rails + Vite
bin/rails server           # Rails only
bin/vite dev               # Frontend dev server only
bin/rails console          # Rails console
bin/rails db:seed          # Re-seed demo data (idempotent)
bin/rails test             # Backend test suite
npm run check              # TypeScript + ESLint + RuboCop
```

### Static checks

After any code change, run:

```bash
npm run check
```

This runs, in order:

1. `npm run typecheck` — TypeScript
2. `npm run lint` — ESLint on `app/javascript`
3. `npm run lint:ruby` — RuboCop

### i18n

Translations live in `config/locales/*.yml`. After editing locale files, export them for the frontend:

```bash
bundle exec i18n export --config config/i18n-js.yml
```

Frontend code uses `t()` from `app/javascript/lib/i18n.ts` — never hard-code user-facing strings.

### Project layout

```
app/
  controllers/     # Rails controllers (Inertia + JSON endpoints)
  javascript/      # React pages and components (Inertia)
  models/          # ActiveRecord models
  policies/        # Pundit authorization
  services/        # Business logic
  tools/           # AI assistant tool implementations
  jobs/            # Background jobs (Solid Queue)
config/
  database.yml     # PostgreSQL connection settings
  locales/         # i18n source files
db/
  schema.rb        # Database schema
  seeds.rb         # Demo data
test/              # Minitest suite
```

---

## Environment variables

| Variable | Required | Default | Purpose |
|----------|----------|---------|---------|
| `OPENROUTER_API_KEY` | For AI features | — | OpenRouter API key |
| `PORT` | No | `3000` | Rails server port |
| `PGHOST` | No | `localhost` | PostgreSQL host |
| `PGPORT` | No | `5432` | PostgreSQL port |
| `PGUSER` | No | — | Admin role used by `bin/setup` to create `amplifa` |
| `PGPASSWORD` | No | — | PostgreSQL password if required |
| `MCP_OAUTH_ISSUER` | No | `http://localhost:3000` | MCP OAuth issuer URL |
| `APP_HOST` | No | `localhost:3000` | Public host for URLs and MCP |

---

## Testing

```bash
# Full backend suite
bin/rails test

# Single file
bin/rails test test/models/account_test.rb

# Static analysis (TypeScript, ESLint, RuboCop)
npm run check
```

Integration tests for Inertia pages use the `inertia_headers` helper from `test/test_helper.rb`. Outbound HTTP is blocked in tests — stub LLM calls with WebMock when needed.

---

## MCP server

The app includes a Model Context Protocol (MCP) server at `/mcp` with OAuth 2.1 PKCE authentication. It exposes example tools (`conversation_list`, `meeting_create`, `lead_search`) scoped to the current user's organization through Pundit.

Local defaults work out of the box. Override with `MCP_OAUTH_ISSUER` and `APP_HOST` if needed.

> **Note:** Dynamic client registration is enabled for local development. Restrict this in production.

---

## Troubleshooting

### `bin/setup` cannot connect to PostgreSQL

1. Confirm PostgreSQL is running: `psql -d postgres -c "SELECT 1"`
2. Create the role manually: `createuser -s amplifa`
3. Set `PGHOST`, `PGPORT`, or `PGPASSWORD` if your install is non-default

### `db:schema:load` fails on `CREATE EXTENSION`

The schema requires `citext` and `pg_trgm`. As a PostgreSQL superuser:

```sql
CREATE EXTENSION IF NOT EXISTS citext;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
```

Or grant schema creation to the app role:

```sql
GRANT CREATE ON SCHEMA public TO amplifa;
```

### Vite assets not loading

Make sure **both** processes are running — Rails alone is not enough. Use `bin/dev` or start `bin/vite dev` in a second terminal.

### AI assistant returns errors

1. Confirm `OPENROUTER_API_KEY` is set (or stored in development credentials)
2. Restart the Rails server after changing env vars
3. Check `log/development.log` for `[AssistantReplyJob]` or `[RubyLLM]` entries

### Port 3000 already in use

```bash
PORT=3001 bin/dev
```

Then visit [http://localhost:3001](http://localhost:3001).

---

## Assignment

This repository is based on the Amplifa takehome assignment. See [ASSIGNMENT.md](ASSIGNMENT.md) for the original brief.

## License

Private / takehome use. Do not distribute without permission.
