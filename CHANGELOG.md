# Changelog

All notable Core changes are documented here.

The `## <tag>` section of this file *is* the GitHub Release body: the release
workflow copies it verbatim and refuses a tag that has no section. Write it
for whoever has to decide whether to upgrade.

See [`docs/versioning.md`](docs/versioning.md) for what the numbers mean and
[`docs/releases.md`](docs/releases.md) for how a release is published.

## Unreleased

### Changed

- One versioning and release document for the whole family. `docs/versioning.md`
  and `docs/releases.md` are now byte-identical across every Asterfield
  repository apart from two clearly marked sections: this repository's own
  version line, and the surface where a change here breaks something. They spell
  out what each of the three numbers means, what the `-alpha.N` suffix counts,
  when alpha becomes beta and when it is legitimate to skip to rc or run a
  pre-release in production.
- **Pre-releases are now tagged on `dev`, not `main`.** Only stable versions are
  tagged on `main`, on the merge commit from `dev`, so `main` answers exactly one
  question: what is in production. The test bot runs `dev`, the production bot
  runs `main`. `release.yml` enforces this and refuses a tag on the wrong branch.
  Earlier pre-releases in this repository were tagged on `main` under the
  previous rule; they are left as they are.

### Removed

- `deploy/telegram-bot-api/`. It pinned `aiogram/telegram-bot-api` by digest --
  the Bot API 7.11 server that answered `404 method not found` to everything
  shipped since, and that no bot has used since the move to
  `telegram-bot-api-next`. Nothing on the host was started from this manifest
  again, yet CI and the release workflow kept validating it, which is how a dead
  pin reads as a maintained one. The server the bots actually run is built and
  deployed from
  [FreshLabDev/telegram-bot-api](https://github.com/FreshLabDev/telegram-bot-api).

## v0.2.0-alpha.2 - 2026-08-22

### Added

- `docs/releases.md` gained a **Deploying** section, and `AGENTS.md` points at it.
  Releasing was documented; deploying was not, in any repository in the family —
  the process stopped at "deploy it" and never said how. That gap mattered more
  after the stacks moved from building on the host to pulling a published image,
  because the procedure changed on the same day. The section names this stack's
  host directory, its env file, the variable that selects the image, the networks
  it needs, and what a rollback actually is.

- Migrations 009 and 010 register the initial Voicy domain and language rank.
- Migration 011 completes the canonical `voicy` bot key, schema, and role
  rename while preserving identity, presence, language, and preference rows.
- SQL coverage verifies the renamed objects, language API round trip, database
  search path, and least-privilege grants.

### Security

- `voicy_core` no longer reads every shared Core table or executes every Core
  function. It has FK references plus execute access only to `core.touch`,
  `core.set_language`, and `core.effective_language`.
- `core.effective_language` now runs as `SECURITY DEFINER` with a fixed search
  path, allowing callers to read the result without raw table access.
- Removed `PUBLIC` execution from the three Voicy-facing Core API functions;
  existing bot roles retain their explicit grants.

### Operations

- Replace the old Voicy password variable with `VOICY_CORE_PASSWORD`.
- The migration renames the existing role, so its SCRAM password remains valid
  during the production transition.

## v0.2.0-alpha.1 - 2026-08-09

### Added

- Migration 007 adds a durable, least-privilege Vido incident-notification
  outbox with delivery leases, retry state, exact localized message snapshots,
  and Telegram delivery evidence.
- Migration 008 adds an idempotent confirmed-delivery journal for Vido and
  Searchy bridge jobs without granting Searchy direct table access.

### Changed

- Searchy bridge completion now records Vido download statistics atomically
  before protected job payloads are cleared.

### Fixed

- Clear retained bridge URLs, settings, and delivery plans on terminal failure
  while preserving the context required for an explicit uncertain-send retry.
- Make confirmed Searchy finalization idempotent and reject migration or runtime
  transitions that could mix old unkeyed and new confirmed statistics.

### Operations

- Freeze bridge intake and drain every non-terminal job before migration 008,
  then deploy Vido `v2.3.7-alpha.5` and Searchy `v0.2.0-alpha.3` before bridge
  processing resumes.

## v0.1.0 - 2026-07-19

First stable Core release: the shared data and delivery foundation for Asterfield
bots.

### Highlights

- Keep Telegram identity, language, chat presence, and bot-specific data in one
  PostgreSQL deployment with isolated schemas and least-privilege roles.
- Provide the durable Searchy and Vido bridge for personal downloads, shared
  temporary artifacts, operation acknowledgements, and Telegram file reuse.
- Ship ordered, idempotent migrations and a source-controlled local Telegram
  Bot API stack for the bot family.

### Reliability and security

- Bind download intents to the user and original card without exposing source
  URLs to Searchy.
- Prevent automatic duplicate sends after an uncertain Telegram response and
  require an explicit owner-bound retry.
- Keep application writes behind controlled database functions and preserve
  forward-compatible rollback of bot versions after migrations are applied.

### Operations

- Move GitHub Actions checkout to its Node 24 runtime major, removing the
  Node 20 deprecation warning without changing Core SQL or production state.

## v0.1.0-rc.3 - 2026-07-18

### Fixed

- Keep future GitHub Release titles equal to the version tag, with no project
  prefix or descriptive suffix.

### Operations

- This candidate changes no SQL migration, grant,
  function signature, Compose contract, or production database state.

## v0.1.0-rc.2 - 2026-07-14

### Added

- Migration 006 adds a least-privilege function that derives a personal Vido
  DM intent when a non-owner presses Download on a bound Searchy group card.
  The selector's original Searchy-chat flow remains unchanged.

### Security

- Derived intents are owner-bound to the clicking user and require the exact
  original `chat_id` and `message_id`; copied callback data is rejected.
- Searchy receives only the new random token, never the protected source URL.
  A shareable card source survives owner consumption only until the original
  six-hour expiry and is then cleared by Vido's record sweeper.

### Operations

- Deploy migration 006 before Searchy `v0.1.0-beta.2`; Vido
  `v2.3.5-beta.3` performs the matching expiry cleanup.

## v0.1.0-rc.1 - 2026-07-13

First release candidate. It formalizes the shared PostgreSQL contract already
used by Asterfield bots and prepares the repository for public development.

### Added

- Shared Telegram identity, chat, cross-bot presence, and ranked language
  resolution in the `core` schema.
- Dedicated least-privilege roles and isolated schemas for Vido, Searchy,
  Quoto, Branchy, and makeitMD.
- Durable Vido × Searchy delivery bridge with owner-bound intents, job leases,
  shared artifact coordination, operation ACKs, bot-specific Telegram `file_id`
  references, and explicit retry after an uncertain send.
- Transport-neutral `DeliveryPlan v1` fixture shared by Go and Python tests.
- Independent local Telegram Bot API Compose manifest for Vido and Searchy.
- Disposable PostgreSQL contract test, GitHub Actions CI, and automated
  pre-release publication from version tags.

### Reliability

- Migrations are applied in filename order, once per ledger version, inside
  per-file transactions protected by an advisory lock.
- Delivered Telegram operations are monotonic and cannot be downgraded by a
  stale failure after an ACK response is lost.
- Expired sending leases become `delivery_unknown` and are never automatically
  replayed; retry is an explicit owner-bound operation.

### Security

- Shared writes run through controlled functions; bot roles do not receive raw
  write access to `core.*` tables.
- Searchy has no direct access to Vido bridge tables or sequences and receives
  only the explicitly granted `SECURITY DEFINER` API.
- Intent tokens are stored as hashes, delivery-plan button tokens are redacted
  from reusable Telegram file references, and terminal job payloads are cleaned.
- Added Apache-2.0 licensing, a vulnerability disclosure policy, public
  documentation, and a release-time history scan requirement.

### Known Limitations

- Migrations are forward-only; rollback means deploying compatible application
  code while retaining the applied schema.
- The shared local Telegram Bot API stack is optional operational
  infrastructure and requires operator-provided Telegram API credentials.
