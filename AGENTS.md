# AGENTS.md

This file is for coding agents working on Core. Keep the shared database small,
least-privilege, forward-compatible, and safe to run in production.

## Project Shape

- Core is PostgreSQL 17 plus ordered SQL migrations and source-controlled
  Compose manifests.
- `core` owns global Telegram identity, chat, presence, and language resolution.
- Each bot owns its domain schema and uses a dedicated login role.
- `bin/apply.sh` is the production migration runner; migrations are recorded in
  `core.schema_migrations`.

## Hard Boundaries

- Do not turn Core into an application service or put bot product behavior in
  the shared identity schema.
- Do not recreate identity tables inside bot schemas.
- Do not edit, renumber, or remove an applied migration. Add the next sequential
  migration.
- Do not assume schema rollback. Preserve compatibility with the previous
  application version or document a staged rollout.
- Do not commit `.env`, dumps, runtime volumes, Telegram state, media files,
  source URLs, user data, or real tokens.

## Security

- Shared writes go through narrow functions; bot roles do not receive raw write
  privileges on `core.*`.
- Every `SECURITY DEFINER` function must use a fixed safe `search_path`, revoke
  `PUBLIC`, validate caller-owned data, and receive explicit grants.
- Searchy must not receive direct access to Vido bridge tables or sequences.
- Keep database and local Bot API ports internal-only in Compose.

## Style

- Keep SQL explicit and readable.
- Bound DDL waits with `lock_timeout` and `statement_timeout` where relevant.
- Add comments only for non-obvious security, concurrency, or compatibility
  behavior.
- Update architecture, versioning, release docs, and changelog for contract or
  operational changes.

## Versioning

- Develop on `dev`; publish every pre-release and stable release from `main`.
- Use plain changelog headings such as `## v0.1.0-rc.1 - 2026-07-13`.
- Mark alpha, beta, and RC GitHub Releases as pre-releases.
- Follow `docs/versioning.md` and `docs/releases.md`.

## Verification

Run:

```sh
./bin/test.sh
docker compose --env-file .env.example config >/dev/null
cp deploy/telegram-bot-api/.env.example deploy/telegram-bot-api/.env
TELEGRAM_API_ID=1 TELEGRAM_API_HASH=test \
  docker compose -f deploy/telegram-bot-api/compose.yaml config >/dev/null
```

The test must cover a clean install, idempotent re-run, bridge contracts, ACK
reliability, and role isolation.
