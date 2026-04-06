---
title: ZIP
description: ZIP archive driver for filekit.
sidebar:
  order: 7
---

The `zip` driver exposes a ZIP archive on disk as a `FileSystem`. You can
read an existing archive, build a new one, or open one for in-place editing.

## When to use it

- Bundling generated assets into a downloadable export.
- Reading uploaded archives without extracting them to disk.
- Treating a content pack as a virtual filesystem at runtime.

## Install

```sh
go get github.com/gobeaver/filekit/driver/zip
```

## Construct

There are three constructors corresponding to three modes:

```go
import (
    "context"
    "strings"

    "github.com/gobeaver/filekit/driver/zip"
)

ctx := context.Background()

// Read-only — opens an existing archive
ro, err := zip.Open("/path/to/archive.zip")
if err != nil { panic(err) }
defer ro.Close()

files, _ := ro.ListContents(ctx, "/", true)
_ = files

// Write-only — creates a fresh archive
w, err := zip.Create("/path/to/new.zip")
if err != nil { panic(err) }
_, _ = w.Write(ctx, "readme.txt", strings.NewReader("hello"))
_ = w.CreateDir(ctx, "images")
_ = w.Close() // finalises the central directory

// Read-write — load existing then mutate
rw, err := zip.OpenOrCreate("/path/to/archive.zip")
if err != nil { panic(err) }
_, _ = rw.Write(ctx, "new.txt", strings.NewReader("..."))
_ = rw.Delete(ctx, "old.txt")
_ = rw.Close() // rewrites the file with the changes
```

`Close()` is mandatory in write and read-write modes — that's when the ZIP
central directory is actually written to disk. Failing to call `Close()`
leaves a truncated archive.

## Modes

```go
const (
    ModeRead      Mode = iota // archive opened for reading
    ModeWrite                 // new archive being constructed
    ModeReadWrite             // existing archive loaded into memory
)
```

`OpenOrCreate` reads the entire archive into memory on open so it can later
rewrite it. For very large archives this is expensive — prefer `Open` (read)
or `Create` (write) when you don't need both.

## Capabilities

| Interface | Implemented | Notes |
|---|---|---|
| `FileSystem` | yes | mode determines which methods succeed |
| `CanCopy` | yes | in-memory entry duplication |
| `CanMove` | yes | copy + delete |
| `CanChecksum` | yes | hashes the entry's stored bytes |
| `CanWatch` | yes (sort of) | returns a `NeverChangeToken` — archives are static |
| `CanSignURL` | no | |
| `CanReadRange` | no | |
| `ChunkedUploader` | no | |

## Quirks

:::caution
ZIP archives in `ModeReadWrite` are loaded entirely into memory and rewritten
from scratch on every `Close()` that observed a mutation. This is fine for a
few hundred megabytes; it is not a good fit for multi-gigabyte archives.
:::

- Writing to a `ModeRead` adapter or reading from a `ModeWrite` adapter
  before `Close()` returns an error.
- The watcher's `ChangeToken` is `NeverChangeToken` — `HasChanged()` will
  always return false. This is deliberate: a static archive cannot change.
- `Stat()` returns the ZIP entry's `Modified` time as `ModTime`; `CreatedAt`
  is `nil`.
