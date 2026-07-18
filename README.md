<h1 align="center">Core</h1>

<p align="center"><strong>One shared PostgreSQL foundation for FreshLab bots.</strong><br/>Global Telegram identity, language, presence, isolated bot schemas, and durable cross-bot contracts.</p>

<p align="center">
  <a href="https://github.com/FreshLabDev/core/releases"><img src="https://img.shields.io/github/v/release/FreshLabDev/core?include_prereleases&sort=semver&style=for-the-badge&label=latest&labelColor=0f172a&color=4c8c4a" alt="latest version"></a>
  <a href="docs/versioning.md"><img src="https://img.shields.io/badge/candidate-v0.1.0--rc.2-4c8c4a?style=for-the-badge&labelColor=0f172a" alt="release candidate"></a>
  <a href="compose.yaml"><img src="https://img.shields.io/badge/postgresql-17-4169e1?style=for-the-badge&logo=postgresql&logoColor=white&labelColor=0f172a" alt="PostgreSQL 17"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache%202.0-334155?style=for-the-badge&labelColor=0f172a" alt="license"></a>
  <a href="https://github.com/FreshLabDev/core/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/FreshLabDev/core/ci.yml?branch=main&style=for-the-badge&label=ci&labelColor=0f172a" alt="CI status"></a>
</p>

<p align="center">
  <a href="#quick-start">Quick Start</a> ·
  <a href="#how-it-works">How It Works</a> ·
  <a href="#contracts">Contracts</a> ·
  <a href="#security">Security</a> ·
  <a href="#testing">Testing</a> ·
  <a href="#docs">Docs</a>
</p>

---

## The Problem

FreshLab bots share the same Telegram people and chats, but they should not
duplicate identity rules or gain broad access to one another's product data.
Core keeps the shared part small and explicit:

| Need | Core approach |
|:--|:--|
| One Telegram identity | Global `user_id` and `chat_id` keys in the `core` schema |
| Cross-bot presence | First seen, last seen, and event counts per bot and chat |
| Consistent language | Ranked observations with user- and chat-scoped resolution |
| Isolated product data | A separate schema and login role for each bot |
| Controlled writes | `SECURITY DEFINER` functions instead of direct table writes |
| Safe evolution | Ordered, advisory-locked, transaction-scoped SQL migrations |

> **Result:** bots can recognize the same person and cooperate through narrow
> database contracts without turning the shared database into a monolith.

---

## Status

| Channel | Version | Meaning |
|:--|:--|:--|
| Candidate | `v0.1.0-rc.3` | Release-title automation and documentation only; no SQL migration or contract change |
| Stable | — | `v0.1.0` follows after the candidate passes its release soak |

The schema is already used by FreshLab bots. The published `v0.1.0-rc.2` line
formalized the live contract. The `rc.3` candidate changes only release
automation/documentation and leaves the production migration ledger at 006.

---

## Quick Start

You need Docker with Compose.

```sh
# 1. Create local configuration
cp .env.example .env

# 2. Replace every example password
$EDITOR .env

# 3. Start PostgreSQL and apply pending migrations
docker compose up -d

# 4. Confirm the one-shot migrator completed
docker compose logs core-migrate
```

The database port is not published on the host. Bot stacks join the external
Docker network as `core_net` and connect with their own least-privilege role.

Re-running the migrator is safe: applied versions are recorded in
`core.schema_migrations`, and only new migration files run.

---

## How It Works

```text
Telegram bots
  ├─ vido_core
  ├─ searchy_core
  ├─ quoto_core
  ├─ branchy_core
  └─ makeitmd_core
          │
          ├─ controlled core.* functions
          │      └─ identity · chats · presence · language
          │
          └─ bot-owned schemas
                 └─ domain data and narrow cross-bot contracts
```

`core.touch` records identity and presence. Language observations are resolved
by source strength and recency. Bot-owned tables stay outside the shared
identity schema and reference global Telegram identifiers when needed.

Migrations run in filename order. Each file executes in one transaction under
an advisory lock, then receives a ledger entry. A failed file is not recorded
as applied.

See [Architecture](docs/architecture.md) for ownership and trust boundaries.

---

## Contracts

### Shared identity API

Bots use these stable entry points:

- `core.touch(...)` — upsert a person, chat, presence, and Telegram language hint.
- `core.set_language(...)` — publish a user- or chat-scoped language observation.
- `core.clear_language(...)` — remove only the calling bot's observation.
- `core.effective_language(...)` — resolve the personal or group language.
- `core.rekey_chat(...)` — preserve state after a group becomes a supergroup.

### Vido × Searchy bridge

The `vido` schema owns download intents, jobs, artifacts, leases, Telegram
delivery operations, and bot-specific `file_id` references. Searchy cannot read
these tables directly; it can only execute the explicitly granted bridge
functions.

A timed-out Telegram send becomes `delivery_unknown` and is never replayed
automatically. The user must explicitly retry because Telegram may have accepted
the first message.

A bound Searchy group card remains deliverable by its selector in the original
chat. Another group member can derive a new owner-bound Vido DM intent through a
SECURITY DEFINER function that validates the exact card message; Searchy never
reads the copied source URL.

### Shared local Bot API

`deploy/telegram-bot-api/` contains the optional independent local Telegram Bot
API stack used by Vido and Searchy. Its data directory and credentials are
runtime state and are never part of this repository.

---

## Repository Layout

```text
migrations/                    ordered database migrations
tests/                         SQL contract and reliability checks
fixtures/                      transport-neutral shared fixtures
bin/apply.sh                   production migration runner
bin/test.sh                    disposable PostgreSQL verification
compose.yaml                   core-postgres + one-shot migrator
deploy/telegram-bot-api/       optional shared local Bot API manifest
docs/                          architecture, versioning, and releases
```

---

## Configuration

| Variable | Required | Default | Purpose |
|:--|:--:|:--|:--|
| `CORE_POSTGRES_USER` | no | `core` | Migration owner and database user |
| `CORE_POSTGRES_DB` | no | `core` | Database name |
| `CORE_POSTGRES_PASSWORD` | yes | — | Owner password |
| `VIDO_CORE_PASSWORD` | deploy | — | `vido_core` login password |
| `SEARCHY_CORE_PASSWORD` | deploy | — | `searchy_core` login password |
| `QUOTO_CORE_PASSWORD` | deploy | — | `quoto_core` login password |
| `BRANCHY_CORE_PASSWORD` | deploy | — | `branchy_core` login password |
| `MAKEITMD_CORE_PASSWORD` | deploy | — | `makeitmd_core` login password |

An empty bot password leaves that role unable to log in. Use a different strong
password for every role.

---

## Security

- PostgreSQL is reachable only through the Docker network by default.
- Each bot has a dedicated login role; raw writes to shared identity tables are
  not granted.
- Cross-bot bridge functions revoke execution from `PUBLIC`, pin a safe
  `search_path`, and validate owner/chat bindings.
- Download and retry tokens are stored as hashes; terminal payload cleanup
  removes source URLs and delivery plans.
- `.env`, database dumps, Bot API state, and media-cache contents are ignored and
  must never be committed.
- Migration history is forward-only. Back up the database before every release
  that adds or changes schema.

Please report vulnerabilities through the process in [SECURITY.md](SECURITY.md).

---

## Testing

Run the same disposable PostgreSQL checks used by CI:

```sh
./bin/test.sh
```

Validate both Compose manifests without starting services:

```sh
docker compose --env-file .env.example config >/dev/null
cp deploy/telegram-bot-api/.env.example deploy/telegram-bot-api/.env
TELEGRAM_API_ID=1 TELEGRAM_API_HASH=test \
  docker compose -f deploy/telegram-bot-api/compose.yaml config >/dev/null
```

The migration test covers a clean install, a second idempotent run, the
Vido/Searchy delivery contract, retry safety, and least-privilege boundaries.

---

## Docs

| Document | Purpose |
|:--|:--|
| [Architecture](docs/architecture.md) | Data ownership, APIs, and trust boundaries |
| [Versioning](docs/versioning.md) | `dev`/`main`, RC, stable, and compatibility rules |
| [Release process](docs/releases.md) | Verification, tagging, and GitHub Releases |
| [Contributing](CONTRIBUTING.md) | Safe migration and review workflow |
| [Shared Bot API](deploy/telegram-bot-api/README.md) | Optional local Telegram API runtime |

---

<p align="center">
  <a href="https://github.com/FreshLabDev/core/releases">Releases</a> ·
  <a href="CHANGELOG.md">Changelog</a> ·
  <a href="LICENSE">Apache-2.0</a> ·
  <a href="NOTICE">NOTICE</a>
</p>

<p align="center">
  Core is open source software by FreshLab.<br/>
  Copyright 2026 FreshLab.
</p>
