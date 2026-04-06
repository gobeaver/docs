---
title: What is GoBeaver?
description: A high-level tour of the GoBeaver project and its goals.
slug: intro/what-is-gobeaver
sidebar:
  order: 1
---

GoBeaver is a set of composable Go packages and a CLI for building production
services. It is organized as a **modular monolith** that can be split into
microservices later without rewriting business logic.

## The pieces

- **configkit** — env-first configuration, zero runtime dependencies.
- **filekit** — unified filesystem API across 7 backends, with optional
  caching, encryption, and validation decorators.
- **beaverkit** — the broader toolkit: database, crypto, OAuth, cache, Slack,
  CAPTCHA, signed URLs, and more on the way.
- **GoBeaver CLI** — scaffolds new projects and manages GoBeaver-flavored apps.

## Naming

The project's brand and product name is **GoBeaver**. The GitHub
organization is also `gobeaver`. Individual package names — `beaverkit`,
`configkit`, `filekit` — drop the `go` prefix to follow Go conventions
(no stuttering, no `go-` prefixes on packages).

## Maturity

| Package    | Status      | Notes |
|------------|-------------|-------|
| configkit  | stable-ish  | Vendored deps, small surface area, ready for real use |
| filekit    | stable-ish  | All seven drivers implemented; APIs unlikely to break |
| beaverkit  | alpha       | Several services solid; others still on the TODO list |
| CLI        | alpha       | Early — expect rough edges |

> GoBeaver is **early alpha** as a whole. Pin versions and expect changes.
