---
title: Local
description: Local on-disk filesystem driver for filekit.
sidebar:
  order: 1
---

The `local` driver maps filekit operations onto a directory on the local
filesystem. It is the most fully-featured driver — it implements every
optional capability filekit defines.

## When to use it

- Development, tests, single-node deployments.
- The default backend behind any filekit recipe.
- Anywhere you need real `fsnotify`-based file watching.

## Install

```sh
go get github.com/gobeaver/filekit/driver/local
```

## Construct

```go
import (
    "context"
    "strings"

    "github.com/gobeaver/filekit/driver/local"
)

fs, err := local.New("/var/uploads")
if err != nil {
    panic(err)
}

ctx := context.Background()
_, _ = fs.Write(ctx, "hello.txt", strings.NewReader("hi"))
```

`local.New` resolves the path to an absolute path and calls `os.MkdirAll` on
it with mode `0755`, so passing a non-existent root is fine — the directory
is created on demand.

All paths passed to subsequent calls are interpreted relative to that root.
Path-traversal attempts (`../../etc/passwd`) are rejected with a wrapped
`ErrNotAllowed`.

## Capabilities

| Interface | Implemented | Notes |
|---|---|---|
| `FileSystem` | yes | full read+write |
| `CanCopy` | yes | uses `io.Copy` between files |
| `CanMove` | yes | tries `os.Rename`, falls back to copy+delete across filesystems |
| `CanChecksum` | yes | MD5, SHA-1, SHA-256, SHA-512, CRC32, CRC32C, xxHash |
| `CanReadRange` | yes | supports negative offsets (read from end) |
| `CanWatch` | yes | native via `fsnotify` |
| `CanSignURL` | no | local files have no URL semantics |
| `ChunkedUploader` | yes | parts staged in a temp dir, finalised on `CompleteUpload` |

The Adapter declares its capabilities at the bottom of `local.go` via
`var _ filekit.CanReadRange = (*Adapter)(nil)` etc.

## Visibility and permissions

`filekit.WithVisibility` translates to chmod after the file is written:

- `filekit.Public`  → `0644`
- `filekit.Private` → `0600`
- unset             → whatever `os.Create` produced (umask-dependent)

## Watching

```go
import "github.com/gobeaver/filekit"

watcher, _ := fs.(filekit.CanWatch)
token, err := watcher.Watch(ctx, "**/*.json")
if err != nil { panic(err) }

if token.ActiveChangeCallbacks() {
    unregister := token.RegisterChangeCallback(func() {
        // fsnotify event matched the pattern
    })
    defer unregister()
} else {
    if token.HasChanged() { /* poll fallback */ }
}
```

The local watcher is "Native" — it uses `fsnotify` under the hood and
forwards matching events to the token's callback.

## Quirks

- `CreatedAt` in `FileInfo` depends on the OS: macOS and Windows expose it,
  Linux returns `nil` (the kernel `Stat_t` lacks birth time without `statx`).
- `Owner` is populated with the numeric UID on Unix and is `nil` on Windows.
- `ListContents` returns entries in lexicographic order.
- The driver does not store custom `Metadata` — that field is only meaningful
  on cloud backends.
