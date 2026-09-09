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

- Work on `dev`. Pre-releases (`-alpha.N`, `-beta.N`, `-rc.N`) are tagged on
  `dev`; stable versions are tagged on `main`, on the merge commit from `dev`.
  The test bot runs `dev`, the production bot runs `main`.
- Use plain changelog headings such as `## v0.1.0-rc.1 - 2026-07-13`.
- Mark alpha, beta, and RC GitHub Releases as pre-releases.
- The visible GitHub Release title must equal the tag exactly.
- Follow `docs/versioning.md` and `docs/releases.md`.

## Verification

Run:

```sh
./bin/test.sh
docker compose --env-file .env.example config >/dev/null
```

The test must cover a clean install, idempotent re-run, bridge contracts, ACK
reliability, and role isolation.

## Deploying

Do not invent a deploy. [`docs/releases.md`](docs/releases.md) has a **Deploying**
section describing this stack exactly: which host directory it lives in, which
env file names the image, which networks it needs, and how to roll back. Read it
before touching anything on the host.

Two rules that hold everywhere and are easy to get wrong:

- **Nothing is built on the host.** A production stack pulls the image the
  release workflow published. A `build:` section in a production manifest is a
  bug.
- **Pin the digest, not the tag.** A tag moves; a digest names one build that was
  tested, and a rollback becomes one line with nothing to rebuild.
