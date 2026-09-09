# Release Process

Every Asterfield repository releases the same way. This document is identical in
all of them; only the verification section is specific to Core.

See [`versioning.md`](versioning.md) for what the numbers mean and why
pre-releases are tagged on `dev` and stable versions on `main`.

## The changelog is the release notes

`CHANGELOG.md` is the source of truth for history, and the release workflow reads
it directly — the GitHub Release body is the `## <tag>` section, copied verbatim.
There is no second place to write release notes, and no step where the two can
disagree.

Which means the changelog has to be written for somebody else to read:

- Put unreleased changes under `## Unreleased`, in the section that fits:
  `Added`, `Changed`, `Fixed`, `Removed`, `Security`, `Breaking`,
  `Known Limitations`.
- Record what matters to a user, an operator, or the next person deciding
  whether to upgrade. Not every refactor.
- Say what changed and why it mattered, concretely. "Fixed a bug" tells nobody
  anything.
- Call out anything an operator must act on — a new or renamed environment
  variable, a migration, a changed deployment assumption — explicitly, in its
  own entry.
- Exactly one `## Unreleased` section, always at the top. Two of them means the
  next release renames the wrong one.

## Publishing a pre-release

A pre-release is tagged on `dev`. Nothing merges anywhere.

1. Finish the work on `dev` and run the verification below.
2. Rename `## Unreleased` to the version, and open a fresh empty `## Unreleased`
   above it:

   ```text
   ## Unreleased

   ## v1.2.3-alpha.4 - 2026-09-09
   ```

3. Commit that on `dev` and push it.
4. Tag the pushed commit and push the tag:

   ```sh
   git tag -a v1.2.3-alpha.4 -m "v1.2.3-alpha.4"
   git push origin dev
   git push origin v1.2.3-alpha.4
   ```

The tag push runs `.github/workflows/release.yml`, which re-runs the checks,
refuses the tag if it is not on the branch its channel publishes from or has
no changelog section, and creates the GitHub Release. Core ships no image.

Then point the test bot at it. A pre-release nobody ran is a pre-release that
proved nothing.

## Publishing a stable release

A stable version is tagged on `main`, on the merge commit.

1. The version being promoted should already have been through at least one
   pre-release that actually ran somewhere. If it has not, say why in the
   changelog.
2. On `dev`, rename `## Unreleased` to the stable version and push.
3. Merge into `main` with a merge commit, so the tag has something to sit on:

   ```sh
   git checkout main
   git merge --no-ff dev
   git push origin main
   ```

4. Tag the merge commit and push the tag:

   ```sh
   git tag -a v1.2.3 -m "v1.2.3"
   git push origin v1.2.3
   ```

5. Deploy it, and check the running version says what it should.

## Rolling back

**There is no rollback here.** Core publishes no image, and a migration has no
`down`: the only way back is restoring the database from a backup taken before
it applied, which is an explicit operator action, not a version bump.

That is why the cost of a wrong migration is paid before it runs, not after.
Correct a mistake with a later migration, and never edit one that has been
applied — `bin/apply.sh` records it, and every other database that ran it is now
somewhere the edited file no longer describes.

## Deploying

Core is not a bot: deploying it means applying migrations to the database every
other stack depends on. It runs on WS04 as the `core` stack —
`/opt/stacks/core` — with `core-postgres` and a one-shot `core-migrate`.

```sh
ws04 stack ps core
ws04 compose core -- up -d core-migrate --yes
```

`bin/apply.sh` bootstraps `core.schema_migrations`, then applies numbered files
in lexical order. Each new file runs in one transaction under a
transaction-scoped advisory lock and is recorded only after it succeeds.

**Applied migrations are immutable and forward-only.** There is no `down`. A
migration that turns out to be wrong is corrected by a later migration, and the
only true rollback is restoring the database from a pre-migration backup — an
explicit operator action, never a version bump.

Because every bot's schema lives in this database, order matters both ways: a
migration that removes something a deployed bot still uses breaks that bot the
moment it applies, and a bot deployed before its migration breaks itself. Say
which order is required in the changelog entry, and stage the two accordingly.

### Checking what is applied

```sh
ws04 sql "SELECT * FROM core.schema_migrations ORDER BY applied_at DESC LIMIT 5"
ws04 sql "SELECT bot, count(*) FROM core.presence GROUP BY bot ORDER BY 2 DESC"
```

The second is the fastest proof that the bots are still reaching Core after a
migration: every bot writes presence on every update it handles.

## Verification

```sh
./bin/test.sh
docker compose --env-file .env.example config >/dev/null
```

`bin/test.sh` runs against a disposable PostgreSQL and must cover a clean
install, an idempotent re-run, the bridge contracts, ACK reliability, and role
isolation.

For `rc` and stable: apply the migration to a copy of the production database
and start each affected bot against it before promoting.
