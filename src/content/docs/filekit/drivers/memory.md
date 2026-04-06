---
title: Memory
description: In-memory filesystem driver for filekit.
sidebar:
  order: 6
---

The `memory` driver stores files in a `map[string][]byte` guarded by a
`sync.RWMutex`. Nothing touches the disk. Ideal for unit tests, fixtures,
caches, and any place you want a real `FileSystem` without setup.

## When to use it

- Tests that need a real filekit backend without temp dirs.
- Short-lived caches that should disappear with the process.
- Fuzz harnesses and example programs in docs.

## Install

```sh
go get github.com/gobeaver/filekit/driver/memory
```

## Construct

```go
import (
    "context"
    "strings"

    "github.com/gobeaver/filekit/driver/memory"
)

fs := memory.New()

ctx := context.Background()
_, _ = fs.Write(ctx, "test.txt", strings.NewReader("hi"))
```

With a size cap (bytes):

```go
fs := memory.New(memory.Config{
    MaxSize: 100 * 1024 * 1024, // 100 MiB ceiling
})
```

### Config

```go
type Config struct {
    MaxSize int64 // 0 = unlimited
}
```

When `MaxSize` is non-zero and a write would push total stored bytes over the
limit, the write returns an error rather than evicting anything.

## Capabilities

| Interface | Implemented | Notes |
|---|---|---|
| `FileSystem` | yes | |
| `CanCopy` | yes | byte-slice copy |
| `CanMove` | yes | rename + delete |
| `CanChecksum` | yes | hashes the in-memory bytes |
| `CanWatch` | yes | native — callbacks fire synchronously on every matching write/delete |
| `CanSignURL` | no | |
| `CanReadRange` | no | |
| `ChunkedUploader` | no | |

## Quirks

- The watcher uses an internal callback list rather than polling, so
  `ActiveChangeCallbacks()` returns true. Callbacks run inline on the
  writing goroutine — keep them fast.
- `CreatedAt` is tracked internally and is always populated.
- Glob patterns for `Watch` use `github.com/gobwas/glob`, not stdlib
  `path/filepath.Match`, so `**` is supported.
