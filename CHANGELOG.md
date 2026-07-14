# Changelog

All notable Core changes are documented here.

Core uses SemVer-style versions with pre-release tags before `v1.0.0`. Release
notes are based on the matching version section.

## Unreleased

Use this section for changes merged to `dev` but not yet released.

### Fixed

- Keep future GitHub Release titles equal to the version tag, with no project
  prefix or descriptive suffix.

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
used by FreshLab bots and prepares the repository for public development.

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
