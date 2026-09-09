# Architecture

Core is the shared PostgreSQL control plane for Asterfield Telegram bots. It is
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
explicitly granted by migrations 004–008.

A per-role grant only means something once `PUBLIC` has been revoked, and the
two have to be written together. Migration 011 revoked `PUBLIC` from three
functions; migration 012 caught the three of the same class it had missed, one
of which turned out to be the only way a bot role reached `clear_language` at
all. When a function is added to `core`, revoke `PUBLIC` in the same migration
that creates it, and let `tests/` assert both halves — that the outside cannot
call it, and that the roles which must call it still can.

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
  -> Core journals the confirmed Vido download exactly once
  -> Vido removes the artifact after the last lease is released
```

Migration 008 is a strict rollout boundary. Freeze bridge intake, stop the old
Vido worker, and drain all non-terminal jobs, including `queued`, before applying
it. The migration refuses an undrained schema, and afterward a bridge job cannot
become `ready` without the normalized journal context produced by the matching
Vido code.

For a bound group card, migration 006 adds a second route: the selector keeps
the flow above, while another user can derive a personal Vido DM intent. Core
checks the original chat/message binding and copies the protected URL internally;
Searchy receives only a new owner-bound token. The source remains derivable for
at most the original card's six-hour lifetime.

Delivery state and operation state are durable. A transport timeout is
ambiguous because Telegram may have accepted the request; the bridge therefore
requires an explicit user retry instead of automatically creating a duplicate.

## Which Telegram endpoint a bot uses

Two endpoints serve the family, and which one a bot takes is a real decision
rather than a leftover.

| | Telegram's own `api.telegram.org` | The self-hosted server |
|:--|:--|:--|
| Bot API version | always the newest | whatever we pinned |
| `getFile` | capped at 20 MB | no cap |
| Upload | capped at 50 MB | 2 GB |
| Local file paths | no | yes, under `--local` |

The rule that follows: **a bot that moves files takes the self-hosted server; a
bot that only sends text takes Telegram's.** Today that means vido, searchy,
voicy and quoto on the self-hosted one, branchy and makeitMD on Telegram's.

The direction surprises people, so it is worth stating plainly: Telegram's
endpoint is the *more* capable one for API surface. Our server exists for file
privileges, not for features. makeitMD renders Bot API 10.3 rich messages
against `api.telegram.org` every day.

That also names the risk our server carries. It is pinned, so it can fall
behind — which is exactly what happened to the third-party image it replaced,
still answering Bot API 7.11 in September 2026 and returning `404 method not
found` for everything shipped since. A bot on the self-hosted server is trading
newest-API for file size, and
[FreshLabDev/telegram-bot-api](https://github.com/FreshLabDev/telegram-bot-api)
carries a weekly drift check for that reason.

A bot on the self-hosted server must also join `telegram_bot_api_net` and run
`Preflight` naming the methods it cannot work without. A server that silently
answers nothing is the failure mode this whole arrangement exists to prevent.

## Migration Model

`bin/apply.sh` bootstraps `core.schema_migrations`, then applies numbered SQL
files in lexical order. Every new file runs in one transaction under a
transaction-scoped advisory lock and is recorded only after success.

Applied migrations are immutable and forward-only. Application rollback must
remain compatible with the newer schema; database restoration is an explicit
operator action from a pre-migration backup.
