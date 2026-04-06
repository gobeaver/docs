---
title: filekit
description: Unified Go filesystem abstraction across 7 backends with stackable decorators.
sidebar:
  order: 1
  label: Overview
---

`filekit` is a filesystem abstraction for Go. One set of interfaces, seven
backends (local, S3, GCS, Azure Blob, SFTP, in-memory, ZIP), and stackable
decorators for read-only protection, metadata caching, AES-256-GCM encryption,
and content validation.

Each driver lives in its own Go module, so importing `driver/s3` only pulls
the AWS SDK and importing `driver/gcs` only pulls Google's. The core module
has no driver dependencies.

## Status

**Stable-ish.** Core interfaces (`FileReader`, `FileWriter`, `FileSystem`) and
the 19 stable error codes are unlikely to change. All seven drivers exist and
implement the full `FileSystem` interface, but optional capabilities
(`CanSignURL`, `CanReadRange`, `CanWatch`, `ChunkedUploader`) vary per driver
— see the [capability matrix](#capability-matrix).

## Install

```sh
# Core (no driver dependencies)
go get github.com/gobeaver/filekit

# Drivers — install only what you use
go get github.com/gobeaver/filekit/driver/local
go get github.com/gobeaver/filekit/driver/s3
go get github.com/gobeaver/filekit/driver/gcs
go get github.com/gobeaver/filekit/driver/azure
go get github.com/gobeaver/filekit/driver/sftp
go get github.com/gobeaver/filekit/driver/memory
go get github.com/gobeaver/filekit/driver/zip

# Validator (separate module, also usable on its own)
go get github.com/gobeaver/filekit/filevalidator
```

## Quick start

```go
package main

import (
    "context"
    "fmt"
    "strings"

    "github.com/gobeaver/filekit/driver/local"
)

func main() {
    fs, err := local.New("./storage")
    if err != nil {
        panic(err)
    }

    ctx := context.Background()

    res, err := fs.Write(ctx, "hello.txt", strings.NewReader("hi"))
    if err != nil {
        panic(err)
    }
    fmt.Printf("wrote %d bytes, sha256=%s\n", res.BytesWritten, res.Checksum)

    data, _ := fs.ReadAll(ctx, "hello.txt")
    fmt.Println(string(data))
}
```

See the [Local driver page](/filekit/drivers/local/) and the other driver
pages under **Drivers** for backend-specific setup.

## Core interfaces

filekit uses interface segregation so callers can require exactly the access
they need.

```go
type FileReader interface {
    Read(ctx context.Context, path string) (io.ReadCloser, error)
    ReadAll(ctx context.Context, path string) ([]byte, error)
    FileExists(ctx context.Context, path string) (bool, error)
    DirExists(ctx context.Context, path string) (bool, error)
    Stat(ctx context.Context, path string) (*FileInfo, error)
    ListContents(ctx context.Context, path string, recursive bool) ([]FileInfo, error)
}

type FileWriter interface {
    Write(ctx context.Context, path string, r io.Reader, opts ...Option) (*WriteResult, error)
    Delete(ctx context.Context, path string) error
    CreateDir(ctx context.Context, path string) error
    DeleteDir(ctx context.Context, path string) error
}

type FileSystem interface {
    FileReader
    FileWriter
}
```

A function that takes `FileReader` cannot mutate the filesystem; the compiler
enforces that. Use `FileSystem` only when you actually need writes.

`Write` returns a `WriteResult` with `BytesWritten`, `Checksum` (and the
algorithm used), `ETag`, `Version`, and `ServerTimestamp` — fields are
populated on a best-effort basis depending on the backend.

## Capability interfaces

Drivers may implement optional interfaces for native operations. Detect them
with a type assertion:

```go
import "github.com/gobeaver/filekit"

if c, ok := fs.(filekit.CanCopy); ok {
    _ = c.Copy(ctx, "src.txt", "dst.txt") // native copy if available
}

if s, ok := fs.(filekit.CanSignURL); ok {
    url, _ := s.SignedURL(ctx, "report.pdf", 15*time.Minute)
}

if cs, ok := fs.(filekit.CanChecksum); ok {
    sum, _ := cs.Checksum(ctx, "file.bin", filekit.ChecksumSHA256)
    _ = sum
}

if rr, ok := fs.(filekit.CanReadRange); ok {
    // last 1 KiB of a log
    r, _ := rr.ReadRange(ctx, "app.log", -1024, 1024)
    defer r.Close()
}

if w, ok := fs.(filekit.CanWatch); ok {
    token, _ := w.Watch(ctx, "**/*.json")
    if token.HasChanged() { /* reload */ }
}
```

The full set: `CanCopy`, `CanMove`, `CanChecksum`, `CanSignURL`, `CanWatch`,
`CanReadRange`, plus `ChunkedUploader` for multipart uploads.

### Capability matrix

| Driver   | FileSystem | CanCopy | CanMove | CanSignURL | CanChecksum | CanWatch    | CanReadRange | ChunkedUploader |
|----------|:---:|:---:|:---:|:---:|:---:|:-----------:|:---:|:---:|
| `local`  | yes | yes | yes | no  | yes | yes (native fsnotify) | yes | yes |
| `s3`     | yes | yes | yes | yes | yes | yes (polling) | no  | yes |
| `gcs`    | yes | yes | yes | yes | yes | yes (polling) | no  | yes |
| `azure`  | yes | yes | yes | yes | yes | yes (polling) | no  | yes |
| `sftp`   | yes | yes | yes | no  | yes | yes (polling) | no  | yes |
| `memory` | yes | yes | yes | no  | yes | yes (native callbacks) | no | no |
| `zip`    | yes | yes | yes | no  | yes | never-changes token | no | no |

## ChangeToken (file watching)

`CanWatch` follows Microsoft's `IChangeToken` pattern. A token is single-use:
once `HasChanged()` returns true, it stays true. Re-call `Watch` for a fresh
token.

```go
type ChangeToken interface {
    HasChanged() bool
    ActiveChangeCallbacks() bool
    RegisterChangeCallback(cb func()) (unregister func())
}
```

For local and memory, callbacks fire immediately on the underlying event.
For cloud and SFTP, the token polls (default 30 s). For ZIP, the returned
token never changes — archives are static.

## Mount manager

`MountManager` lets you compose multiple backends under a single virtual path
tree. It implements `FileSystem` itself, so it slots in anywhere a regular
filesystem is expected.

```go
import (
    "github.com/gobeaver/filekit"
    "github.com/gobeaver/filekit/driver/local"
    "github.com/gobeaver/filekit/driver/memory"
)

mounts := filekit.NewMountManager()

localFS, _ := local.New("/var/uploads")
mounts.Mount("/local", localFS)
mounts.Mount("/cache", memory.New())
mounts.Mount("/cloud", s3FS) // some *s3.Adapter

// Routes by longest-prefix match
_, _ = mounts.Write(ctx, "/cache/temp.json", reader)
_, _ = mounts.Read(ctx, "/cloud/report.pdf")

// Cross-mount copy/move work transparently — uses native Copy on the
// destination if both src and dst resolve to the same backend, otherwise
// falls back to read+write.
_ = mounts.Copy(ctx, "/cache/temp.json", "/cloud/archive/temp.json")
```

`mounts.ListContents(ctx, "/", false)` returns the mount points as virtual
directories. `Unmount(prefix)` removes one. All operations are protected by
an `RWMutex`.

## File selectors

`FileSelector` is filekit's filtering API, modelled on Apache Commons VFS.

```go
import "github.com/gobeaver/filekit"

// Glob
files, _ := filekit.ListWithSelector(ctx, fs, "/images", filekit.Glob("*.jpg"), true)

// Composed: JPG files under 10 MiB
sel := filekit.And(
    filekit.Glob("*.jpg"),
    filekit.FuncSelector(func(f *filekit.FileInfo) bool {
        return f.Size < 10*1024*1024
    }),
)
files, _ = filekit.ListWithSelector(ctx, fs, "/uploads", sel, true)
```

Built-ins: `All()`, `Glob(pattern)`, `Depth(max, base)`, `And(...)`, `Or(...)`,
`Not(sel)`, `FuncSelector(fn)`, `FuncSelectorFull(match, traverse)`. The
`TraverseDescendants` method on a selector lets you prune subtrees early.

## Decorators

Decorators wrap any `FileSystem` to add orthogonal behaviour. They stack in
any order.

### Read-only

```go
ro := filekit.NewReadOnlyFileSystem(fs)
_, err := ro.Write(ctx, "x.txt", reader) // returns ErrReadOnly
if filekit.IsReadOnlyError(err) { /* ... */ }
```

Options let you punch holes for specific operations or hook write attempts:

```go
ro := filekit.NewReadOnlyFileSystem(fs,
    filekit.WithAllowCreateDir(true),
    filekit.WithAllowDelete(true),
    filekit.WithWriteAttemptHandler(func(op, path string) error {
        log.Printf("blocked %s on %s", op, path)
        return filekit.ErrReadOnly
    }),
)
```

### Caching

`CachingFileSystem` caches `FileExists`, `Stat`, and `ListContents` results.
Writes invalidate automatically. Default cache is in-memory with a 5-minute TTL.

```go
cached := filekit.NewCachingFileSystem(fs,
    filekit.WithCacheTTL(10*time.Minute),
    filekit.WithCacheExists(true),
    filekit.WithCacheFileInfo(true),
    filekit.WithCacheList(true),
    filekit.WithInvalidateOnWrite(true),
)
```

Plug in any `Cache` implementation (Redis, Memcached, BigCache, ...):

```go
type Cache interface {
    Get(key string) (interface{}, bool)
    Set(key string, value interface{}, ttl time.Duration)
    Delete(key string)
    Clear()
}

cached := filekit.NewCachingFileSystem(fs, filekit.WithCache(myRedisCache))
```

`filekit.NewMemoryCache()` exposes hit/miss/eviction stats via `Stats()`.

### Encryption (AES-256-GCM)

`EncryptedFS` transparently encrypts on `Write` and decrypts on `Read` using
AES-256-GCM in a versioned chunked format:

- 17-byte header: version (1 B) + chunk size (4 B big-endian) + base nonce (12 B).
- Chunks: length (4 B) + sequence (4 B) + GCM ciphertext.
- Per-chunk nonce derived from `base_nonce XOR sequence` to defeat reordering.
- Default chunk size 64 KiB; configurable between 1 KiB and 16 MiB.

```go
key := make([]byte, 32) // 256-bit key
_, _ = rand.Read(key)

enc, err := filekit.NewEncryptedFS(fs, key) // returns ErrInvalidKey if not 32 B
if err != nil {
    panic(err)
}

_, _ = enc.Write(ctx, "secret.txt", strings.NewReader("classified"))
plain, _ := enc.ReadAll(ctx, "secret.txt") // decrypted

raw, _ := fs.ReadAll(ctx, "secret.txt") // ciphertext
_ = raw
```

Decryption failures return `ErrDecryptionFailed`. Other sentinel errors:
`ErrInvalidKey`, `ErrInvalidFormat`, `ErrUnsupportedVersion`,
`ErrTruncatedFile`, `ErrInvalidChunkSequence`.

### Validation

`ValidatedFileSystem` runs filevalidator on every write before forwarding to
the inner filesystem. See the [Validator overview](/filekit/validator/).

```go
import (
    "github.com/gobeaver/filekit"
    "github.com/gobeaver/filekit/filevalidator"
)

v := filevalidator.NewBuilder().
    MaxSize(10 * filevalidator.MB).
    AcceptImages().
    WithContentValidation().
    Build()

vfs := filekit.NewValidatedFileSystem(fs, v)
_, err := vfs.Write(ctx, "evil.exe", reader) // rejected
```

For seekable readers (`os.File`), validation reads the header, rewinds, then
streams the write. For non-seekable readers (e.g., HTTP body), filekit reads
the first 512 B for MIME/header checks then re-stitches the stream — deep
content checks (zip structure, etc.) are skipped in that mode.

Per-write override:

```go
_, _ = fs.Write(ctx, "doc.pdf", reader,
    filekit.WithValidator(filevalidator.ForDocuments().Build()),
)
```

### Stacking

Decorators are just `FileSystem` implementations, so they compose:

```go
fs, _ := local.New("./data")
fs2, _ := filekit.NewEncryptedFS(fs, key)
var fs3 filekit.FileSystem = filekit.NewValidatedFileSystem(fs2, validator)
fs3 = filekit.NewCachingFileSystem(fs3)
fs3 = filekit.NewReadOnlyFileSystem(fs3)
```

## Write options

```go
fs.Write(ctx, "report.pdf", r,
    filekit.WithContentType("application/pdf"),
    filekit.WithMetadata(map[string]string{"author": "alice"}),
    filekit.WithVisibility(filekit.Public),         // or Private
    filekit.WithCacheControl("max-age=86400"),
    filekit.WithOverwrite(true),
    filekit.WithContentDisposition(`attachment; filename="report.pdf"`),
    filekit.WithACL("bucket-owner-full-control"),
    filekit.WithHeaders(map[string]string{"X-Trace": "abc"}),
    filekit.WithExpires(time.Now().Add(24*time.Hour)),
)
```

For large files with progress reporting:

```go
f, _ := os.Open("big.zip")
defer f.Close()
info, _ := f.Stat()

err := filekit.WriteWithProgress(ctx, fs, "big.zip", f, info.Size(), &filekit.WriteOptions{
    ContentType: "application/zip",
    ChunkSize:   5 * 1024 * 1024,
    Progress: func(done, total int64) {
        fmt.Printf("\r%.1f%%", float64(done)/float64(total)*100)
    },
})
```

## Error model

filekit defines 19 stable error codes. The values are part of the public API
contract and will not change.

```go
const (
    // Existence
    ErrCodeNotFound      ErrorCode = "FILEKIT_NOT_FOUND"
    ErrCodeAlreadyExists ErrorCode = "FILEKIT_ALREADY_EXISTS"
    ErrCodeTypeMismatch  ErrorCode = "FILEKIT_TYPE_MISMATCH"

    // Access
    ErrCodePermission ErrorCode = "FILEKIT_PERMISSION"
    ErrCodeAuth       ErrorCode = "FILEKIT_AUTH"
    ErrCodeQuota      ErrorCode = "FILEKIT_QUOTA"

    // Validation
    ErrCodeInvalidInput ErrorCode = "FILEKIT_INVALID_INPUT"
    ErrCodeValidation   ErrorCode = "FILEKIT_VALIDATION"

    // Integrity
    ErrCodeIntegrity ErrorCode = "FILEKIT_INTEGRITY"

    // Operation
    ErrCodeNotSupported ErrorCode = "FILEKIT_NOT_SUPPORTED"
    ErrCodeAborted      ErrorCode = "FILEKIT_ABORTED"
    ErrCodeTimeout      ErrorCode = "FILEKIT_TIMEOUT"
    ErrCodeClosed       ErrorCode = "FILEKIT_CLOSED"

    // Infrastructure
    ErrCodeIO        ErrorCode = "FILEKIT_IO"
    ErrCodeNetwork   ErrorCode = "FILEKIT_NETWORK"
    ErrCodeService   ErrorCode = "FILEKIT_SERVICE"
    ErrCodeRateLimit ErrorCode = "FILEKIT_RATE_LIMIT"

    // Mount
    ErrCodeMount ErrorCode = "FILEKIT_MOUNT"

    // Internal
    ErrCodeInternal ErrorCode = "FILEKIT_INTERNAL"
)
```

The primary error type is `*FileError`:

```go
type FileError struct {
    ErrCode    ErrorCode
    Message    string
    Cat        ErrorCategory
    Op         string         // operation name
    Path       string         // path involved
    Driver     string         // driver name
    Err        error          // underlying error
    Retry      bool
    RetryDelay time.Duration
    Detail     map[string]any
    Timestamp  time.Time
    RequestID  string
}
```

Inspect errors with the helpers (they also accept stdlib errors):

```go
_, err := fs.Read(ctx, "missing.txt")

switch {
case filekit.IsNotFound(err):       // also covers fs.ErrNotExist
case filekit.IsPermissionErr(err):
case filekit.IsValidationErr(err):
case filekit.IsRetryableErr(err):
    time.Sleep(filekit.GetRetryAfter(err))
}

if filekit.IsCode(err, filekit.ErrCodeQuota) {
    // ...
}

var fe *filekit.FileError
if errors.As(err, &fe) {
    http.Error(w, fe.Message, fe.HTTPStatus())
}
```

For batch operations, `MultiError` collects per-item errors:

```go
multi := filekit.NewMultiError("batch_delete")
for _, p := range paths {
    multi.Add(fs.Delete(ctx, p))
}
return multi.Err() // nil, single error, or *MultiError
```

## Configuration via env

filekit also ships a `Config` struct loadable from `FILEKIT_*` environment
variables for the simple "pick one driver" case:

```go
cfg := filekit.Config{
    Driver:   "s3",
    S3Region: "us-west-2",
    S3Bucket: "my-bucket",
    S3Prefix: "uploads/",
}
fs, err := filekit.New(cfg)
```

The full set of `FILEKIT_*` keys (LOCAL, S3, GCS, AZURE, SFTP, validation,
encryption) is documented inline on the `Config` struct in
[`config.go`](https://github.com/gobeaver/filekit/blob/main/config.go). For
non-trivial setups, prefer constructing drivers directly — the env loader
only covers single-backend deployments.
