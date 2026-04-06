---
title: Multi-Tenancy
description: How GoBeaver enforces tenant isolation at the repository layer.
sidebar:
  order: 3
---

Every query in a GoBeaver service must filter by `org_id`. The tenant is
extracted from the JWT by middleware and stored on the request context;
repositories read it from there and refuse to run queries without it.

This keeps tenant isolation enforceable in one place — the repository — and
prevents accidental cross-tenant reads from leaking out of business logic.
