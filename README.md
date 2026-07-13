# core — shared cross-bot identity / presence / language

A small dedicated PostgreSQL that consolidates the data common to all the
Telegram bots (**vido**, **searchy**, **quoto**, **branchy**, **makeitMD**): who a person is,
which bots/chats they've appeared in ("who was where"), and their language
preference — keyed on the **global** Telegram `user_id` / `chat_id`.

Each bot owns an isolated schema in the shared database and reaches common
identity through `SECURITY DEFINER` API functions. Domain tables stay in the
bot's schema and reference the global Telegram identifiers in `core`.

Design rationale, migration plan, and the 6 locked decisions live in the
proposal doc kept alongside the project notes.

## Layout

```
compose.yaml              core-postgres (:5432, not host-published) + core-migrate (one-shot)
bin/apply.sh              versioned migration runner (advisory-locked, per-file txn)
migrations/001_core.sql   schema + API functions + who_was_where view
migrations/002_roles_grants.sql   initial least-privilege bot roles + grants
migrations/003_makeitmd.sql       makeitMD registration, role, and isolated schema
migrations/004_vido_searchy_bridge.sql   durable Vido/Searchy queue + shared artifacts
migrations/005_vido_searchy_bridge_reliability.sql   monotonic ACKs, leases, notifications, retry
.env.example              copy to .env, fill secrets
```

Bot roles receive `SELECT` on shared identity, `REFERENCES` on `core.person`
and `core.chat` for domain foreign keys, and `EXECUTE` on the controlled core
API. They do not receive direct write privileges on `core.*` tables.

## What core owns

- `person` (+ `person_name_history`) — identity keyed on `telegram_user_id`.
- `chat` (+ `chat_alias`) — chat directory; `rekey_chat` handles group→supergroup.
- `presence` — `(person × bot × chat)` with first/last seen and event count.
- `language_observation` → `language_pref` — each bot's claim + the resolved
  winner. Priority: `manual > auto > client(TG hint) > default`, tie → newer,
  then bot rank `quoto > searchy > vido > branchy`.
- `pref` — stub for future shared prefs (timezone/premium/agreement); unused for now.

## API (bots call these)

- `core.touch(bot, user_id, username, first_name, last_name, tg_lang, chat_id, chat_type, chat_title, chat_uname, is_bot, at)`
  — call once per interaction. Upserts person/name-history/chat/presence and
  captures the Telegram language hint. Pass `chat_id = NULL` for DM/private
  (presence rolls up under `chat_id = 0`).
- `core.set_language(bot, scope, subject_id, lang, source)` — `scope` is `'user'`
  or `'chat'`; `source` is `'manual'|'auto'|'client'|'default'`.
- `core.clear_language(bot, scope, subject_id)` — removes only this bot's claim.
- `core.effective_language(user_id, chat_id, prefer)` — read path. Use
  `prefer='user'` for personal screens (settings/stats/DM — personal language
  wins even inside a group) and `prefer='chat'` for group-broadcast content
  (e.g. quoto's published quote).
- `core.rekey_chat(old_chat_id, new_chat_id)` — call on group→supergroup promotion.

## Vido/Searchy bridge API

The `vido` domain schema is created by migrations 004/005. Searchy has `USAGE`
on the schema but no table or sequence grants; it can only call the explicitly
granted SECURITY DEFINER functions. Migration 005 records every Telegram
operation as `sending` before transport, makes delivered ACKs monotonic, renews
delivery leases, exposes a durable terminal-notification claim/ACK pair, and
uses owner/chat/message-bound hashed retry intents for uncertain sends.

An expired lease containing `sending` becomes `delivery_unknown` and is never
automatically replayed. The user must choose the explicit retry action because
Telegram may already have accepted the original message.

## Provision (on ws04, when ready — NOT yet deployed)

```sh
cp .env.example .env      # then fill in strong passwords
docker compose up -d      # starts core-postgres, runs core-migrate once
docker compose logs core-migrate    # verify "core-migrate: done."
```

Re-running `docker compose up` re-applies only new migration files and refreshes
role passwords from `.env`. Bot stacks join the network with:

```yaml
networks:
  core_net:
    external: true
    name: core_net
```

## Who-was-where / same-users queries

```sql
-- same users across bots
SELECT telegram_user_id, username, bots, bot_count
FROM core.who_was_where WHERE bot_count > 1 ORDER BY bot_count DESC;

-- where has this person been
SELECT bot, chat_id, first_seen_at, last_seen_at, event_count
FROM core.presence WHERE telegram_user_id = $1 ORDER BY last_seen_at DESC;

-- pairwise bot overlap matrix
SELECT a.bot AS bot_a, b.bot AS bot_b, count(*) AS shared_users
FROM (SELECT DISTINCT telegram_user_id, bot FROM core.presence) a
JOIN (SELECT DISTINCT telegram_user_id, bot FROM core.presence) b
  ON a.telegram_user_id = b.telegram_user_id AND a.bot < b.bot
GROUP BY a.bot, b.bot ORDER BY shared_users DESC;

-- language conflict audit for a user (who claimed what, who won)
SELECT source_bot, language, source, observed_at, core.lang_rank(source) AS rank
FROM core.language_observation WHERE scope='user' AND subject_id=$1 ORDER BY rank DESC;
SELECT * FROM core.language_pref WHERE scope='user' AND subject_id=$1;
```
