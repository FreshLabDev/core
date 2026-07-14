# Versioning

Core uses SemVer-style versions with pre-release tags before `v1.0.0`.

## Branches

Core has two long-lived branches:

- **`dev`** — development. Changes land here and `## Unreleased` tracks work
  that has not been published.
- **`main`** — publication. Every pre-release and stable release is merged from
  `dev`, tagged on `main`, and verified before publication.

`main` always reflects the latest published release. Release work renames the
changelog section, merges `dev` into `main`, and tags the exact merge commit.

## Version Line

The repository begins with the contract already running across the bot family:

```text
v0.1.0-rc.1     first documented and verified public release candidate
v0.1.0-rc.2     owner-bound Vido DM derivation for shared Searchy cards
v0.1.0-rc.N     candidate-only fixes if the soak finds blockers
v0.1.0          first stable public contract
```

After `v0.1.0`:

```text
v0.1.1          compatible bug, security, or migration-runner fixes
v0.2.0          notable compatible schema or operational improvements
v1.0.0          mature production contract with explicit compatibility policy
```

## Rules

- Use `rc` when the release is intended to become stable and only fixes are
  expected.
- Use patch versions for fixes that preserve SQL signatures, grants, migration
  order, and deployment assumptions.
- Use minor versions for compatible new schemas, functions, roles, or
  operational capabilities.
- Do not reuse, move, or retag a published version.
- Do not release from `dev`; merge the verified state to `main` first.
- Mark `alpha`, `beta`, and `rc` GitHub Releases as pre-releases.
- Do not publish `v1.0.0` until the database APIs and operator contract have
  substantial production history.

## Breaking-Sensitive Surface

Before `v1.0.0`, changes may still evolve quickly, but release notes must call
out any impact to:

- function names, arguments, return rows, or security mode;
- role grants, schema ownership, or required PostgreSQL extensions;
- migration order, ledger behavior, or backup requirements;
- Compose networks, volumes, environment variables, or runtime paths;
- `DeliveryPlan` versions and Vido × Searchy queue semantics;
- application versions required before or after a migration.

Applied migrations remain forward-only. A breaking migration requires a staged
application rollout and an explicit recovery plan even before `v1.0.0`.
