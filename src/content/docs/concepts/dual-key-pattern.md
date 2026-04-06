---
title: Dual-Key Pattern
description: Why every GoBeaver table has both an internal id and a public uuid.
sidebar:
  order: 2
---

Every table in a GoBeaver app has **two identifiers**:

```sql
id   BIGINT AUTO_INCREMENT PRIMARY KEY,  -- internal joins, FKs, indexes
uuid CHAR(36) NOT NULL UNIQUE,           -- public API identifier
```

## Why

- `id` is fast and compact — perfect for foreign keys and internal joins.
- `uuid` is opaque — safe to expose in URLs and APIs without leaking row
  counts or enabling enumeration attacks.

**Never expose `id` in API responses.** Always serialize `uuid`.
