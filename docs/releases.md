# Release Process

Core releases version the database contract, migration runner, fixtures,
tests, and source-controlled runtime manifests. Core does not publish an
application container image.

Development happens on `dev`; releases are published from `main`. See
[Versioning](versioning.md).

## Changelog Rules

- Put unreleased schema, security, reliability, compatibility, and operational
  changes under `## Unreleased`.
- Use plain headings such as `## v0.1.0-rc.1 - 2026-07-13`.
- Mention required application versions, extensions, environment variables,
  backup steps, and known limitations explicitly.
- Do not record every formatting or internal documentation edit.

## Release Gate

Before merging to `main`:

1. Review the complete diff and migration ordering.
2. Run `./bin/test.sh` for a clean install, idempotent second run, bridge
   contracts, ACK reliability, and grants.
3. Validate the core and local Bot API Compose manifests.
4. Test an upgrade from a current database snapshot when the release adds a
   migration.
5. Confirm compatible Vido/Searchy/bot versions and the operational rollback.
6. Scan tracked files and complete Git history for secrets, credentials,
   database dumps, Telegram data, and private runtime files.
7. Move `Unreleased` entries into the version section and keep a fresh empty
   `## Unreleased` above it.

## Publishing

1. Push the verified `dev` branch.
2. Merge `dev` into `main` with a merge commit.
3. Confirm `main` is clean and CI is green.
4. Create an annotated tag on the `main` release commit.
5. Push `main`, then push the tag.
6. Confirm the release workflow creates the matching GitHub Release and marks
   a pre-release suffix as a pre-release.

The tag, GitHub Release, changelog section, and verified commit SHA must all
match. Do not start a dependent production rollout when any of them differs.

## Release Notes

Use this shape:

```text
Core v0.1.0-rc.1

Summary:
- Why this database contract is being released.

Contracts:
- Schemas, functions, roles, or fixtures added or changed.

Operations:
- Backup, migration, environment, and compatibility requirements.

Verification:
- Disposable PostgreSQL contract test.
- Compose validation.
- Upgrade and security review status.

Known limitations:
- Forward-only or staged-rollout constraints.
```

Pushing a `v*` tag runs `.github/workflows/release.yml`. The workflow validates
the tag and changelog, reruns the database contract test, and creates or updates
the matching GitHub Release. It does not deploy production infrastructure.
