---
title: Contributing
description: How to contribute to GoBeaver.
sidebar:
  order: 1
  label: Overview
---

GoBeaver is early alpha. Issues, RFCs, and PRs are welcome — but expect the
APIs to move under your feet for a while yet.

## Ground rules

- One concern per PR. Refactors and features in separate commits.
- Follow the Go conventions in `CLAUDE.md` (no stuttering, lowercase
  packages, RFC 9457 responses, etc.).
- New packages need at least: a `doc.go`, a `README.md`, and a unit test for
  the happy path.
- `go mod tidy` in **both** modules whenever you touch a package another
  module consumes through a `replace` directive.

## Guidelines

Three conventions hold the workspace together. Any new package is expected to
follow all three; anything that diverges needs a comment saying why.

| Guide | Covers |
|---|---|
| [Package layout](/contributing/package-layout/) | Directory structure, when to split into sub-modules, multi-module releases, the Makefile |
| [Configuration](/contributing/configuration/) | Loading config with `configkit` — the `Config` / `New` / `Init` / accessor pattern |
| [Linting](/contributing/linting/) | The canonical `.golangci.yml`, what each linter buys you, the CI gate |

New package? Start from the
[checklist](/contributing/package-layout/#checklist-for-a-new-package).
