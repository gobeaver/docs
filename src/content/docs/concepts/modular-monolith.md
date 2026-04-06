---
title: Modular Monolith
description: Why GoBeaver favors modular monoliths that can be split later.
sidebar:
  order: 1
---

GoBeaver is built around the **modular monolith → microservices** pattern. You
start with one binary made of well-isolated modules and split out services
only when scale or team boundaries demand it.

## Rules

- Each module owns its tables and prefixes them (`auth_`, `org_`, `billing_`…)
- Cross-module communication is through interfaces, not direct imports
- Embedded mode = direct calls; standalone mode = HTTP/gRPC + outbox
- No module exposes ORM models; everything crosses boundaries as DTOs
