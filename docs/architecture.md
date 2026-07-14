# Architecture

Core is the shared PostgreSQL control plane for FreshLab Telegram bots. It is
not a general application backend and it does not own bot-specific product
behavior.

## Ownership

| Area | Owner | Examples |
|:--|:--|:--|
| Global identity | `core` | person, chat, name history |
| Cross-bot signals | `core` | presence, language observations, resolved language |
| Bot domain data | individual bot schema | settings, analytics, subscriptions, jobs |
| Vido × Searchy bridge | `vido` | intents, artifacts, delivery plans, Telegram ACKs |
| Runtime secrets and files | operator | `.env`, database volume, Bot API state, media cache |

## Trust Boundaries

Each bot connects with a dedicated PostgreSQL login role. Shared identity writes
are exposed as functions so the database can validate the bot identity and
preserve one resolution algorithm.

Bot roles can read shared identity data needed by the existing integrations and
hold `REFERENCES` privileges for domain foreign keys. They do not receive raw
write privileges on `core.*` tables.

The Vido × Searchy bridge is stricter: Vido owns the bridge tables while
Searchy has no table or sequence access. Searchy can only call the functions
explicitly granted by migrations 004–006.

## Shared Identity Flow

```text
Telegram update
  -> bot calls core.touch(bot, user, chat, language hint)
  -> core upserts person and chat
  -> core records per-bot presence
  -> core records the language observation
  -> core resolves the winning language
```

Language sources rank `manual` above `auto`, `client`, and `default`. Ties are
resolved by observation time and the defined bot rank. Personal screens should
prefer the user scope; messages intended for a whole group may prefer chat
scope.

## Vido × Searchy Delivery Flow

```text
Searchy creates an owner-bound intent
  -> Vido claims and processes the job
  -> Vido writes a shared temporary artifact
  -> Vido produces DeliveryPlan v1
  -> Searchy sends through its own Telegram token
  -> Searchy ACKs each operation and stores its bot-specific file_id
  -> Vido removes the artifact after the last lease is released
```

For a bound group card, migration 006 adds a second route: the selector keeps
the flow above, while another user can derive a personal Vido DM intent. Core
checks the original chat/message binding and copies the protected URL internally;
Searchy receives only a new owner-bound token. The source remains derivable for
at most the original card's six-hour lifetime.

Delivery state and operation state are durable. A transport timeout is
ambiguous because Telegram may have accepted the request; the bridge therefore
requires an explicit user retry instead of automatically creating a duplicate.

## Migration Model

`bin/apply.sh` bootstraps `core.schema_migrations`, then applies numbered SQL
files in lexical order. Every new file runs in one transaction under a
transaction-scoped advisory lock and is recorded only after success.

Applied migrations are immutable and forward-only. Application rollback must
remain compatible with the newer schema; database restoration is an explicit
operator action from a pre-migration backup.
