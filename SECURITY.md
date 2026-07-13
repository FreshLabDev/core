# Security Policy

## Supported Versions

Security fixes are applied to the latest released Core version. Before
`v1.0.0`, upgrading to the newest pre-release or stable tag may be required.

## Reporting A Vulnerability

Please do not open a public issue for a suspected vulnerability or include
credentials, database dumps, Telegram identifiers, source URLs, tokens, or
production logs in an issue.

Use GitHub's private vulnerability reporting for `FreshLabDev/core` when it is
available. If it is not available, contact a FreshLab maintainer privately
through an existing trusted channel and include only the minimum reproduction
details needed to investigate.

We will acknowledge a report, assess affected versions, coordinate a fix, and
publish an advisory when disclosure is safe.

## Operator Responsibilities

- Keep `.env`, PostgreSQL dumps, Telegram Bot API state, and media-cache files
  outside Git.
- Use unique strong passwords for the owner and every bot role.
- Do not publish the PostgreSQL or local Bot API ports directly to the internet.
- Back up the database before applying a release with new migrations.
- Review migration grants, `SECURITY DEFINER` ownership, and `search_path`
  whenever a database API changes.
