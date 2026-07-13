# Changelog

All notable Core changes are documented here.

Core uses SemVer-style versions with pre-release tags before `v1.0.0`. Release
notes are based on the matching version section.

## Unreleased

Use this section for changes merged to `dev` but not yet released.

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
