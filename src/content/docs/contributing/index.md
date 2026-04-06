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
