# Contributing

Core is small infrastructure with a wide blast radius. Keep changes narrow,
forward-compatible, and easy to audit.

## Development Flow

1. Branch from `dev`.
2. Add a new ordered migration instead of rewriting an applied one.
3. Update SQL contract tests and documentation when behavior or grants change.
4. Run `./bin/test.sh` and validate both Compose manifests.
5. Open a pull request back to `dev` with migration, compatibility, and rollback
   notes.

Releases are merged from `dev` to `main` and tagged on `main`. See
[Versioning](docs/versioning.md) and [Release process](docs/releases.md).

## Migration Rules

- Never renumber, delete, or edit a migration that may have reached a shared
  environment. Add the next sequential file.
- Keep DDL bounded with `lock_timeout` and `statement_timeout` where it may wait
  on production objects.
- Make a migration safe to apply exactly once through the ledger. Use
  idempotent DDL where it also improves recovery and review.
- Keep every `SECURITY DEFINER` function on a fixed safe `search_path`, revoke
  execution from `PUBLIC`, and grant only the required roles.
- Do not add secrets, raw tokens, query text, private URLs, Telegram user data,
  or production samples to migrations, fixtures, tests, logs, or documentation.
- Describe the compatible application versions and operational rollback. Schema
  rollback is not assumed.

## Review Checklist

- Clean install succeeds.
- Re-running the migrator skips applied versions safely.
- Upgrade from the previous release succeeds.
- Least-privilege roles cannot bypass their function API.
- New indexes support queue, expiry, and lease access paths.
- Changelog and release notes call out contract or deployment changes.
