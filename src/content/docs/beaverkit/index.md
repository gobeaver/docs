---
title: beaverkit
description: The wider GoBeaver toolkit — database, crypto, oauth, cache, and more.
sidebar:
  order: 1
  label: Overview
---

`beaverkit` is the broader Go toolkit underneath the GoBeaver Framework and
CLI. It bundles the building blocks most services need, with a consistent
shape across every package:

- **Init / Service / Reset / Health** lifecycle functions
- Builder pattern via `WithPrefix(...)` for multi-instance setups
- Environment-first configuration (defaults to the `BEAVER_` prefix)

## Packages

| Area               | Packages |
|--------------------|----------|
| Infrastructure     | `config`, `database`, `cache` |
| Security & crypto  | `krypto`, `oauth` |
| Notifications      | `slack` |
| Anti-abuse         | `captcha` |
| URLs               | `urlsigner` |

More services are on the roadmap (email, logger, queue, metrics, sessions,
rate limiter, …) — see the project's `TODO.md`.

## Status

**Alpha.** Several packages (krypto, oauth, slack) are mature and battle-tested
internally; others are still being shaped. Expect breaking changes between
versions until we tag a beta.
