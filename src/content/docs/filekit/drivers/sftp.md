---
title: SFTP
description: SFTP driver for filekit.
sidebar:
  order: 5
---

The `sftp` driver wraps `github.com/pkg/sftp` over `golang.org/x/crypto/ssh`.
It connects on construction and reconnects automatically if the underlying
SSH session drops.

## When to use it

- Talking to a remote box that only exposes SFTP.
- Legacy file drops, third-party EDI feeds, vendor exports.

## Install

```sh
go get github.com/gobeaver/filekit/driver/sftp
```

(The driver pulls `pkg/sftp` and `golang.org/x/crypto` transitively.)

## Construct

```go
import (
    "context"
    "os"

    "github.com/gobeaver/filekit/driver/sftp"
)

ctx := context.Background()

keyBytes, err := os.ReadFile("/home/me/.ssh/id_ed25519")
if err != nil {
    panic(err)
}

fs, err := sftp.New(sftp.Config{
    Host:       "sftp.example.com",
    Port:       22,
    Username:   "alice",
    PrivateKey: keyBytes, // PEM-encoded key bytes
    BasePath:   "/uploads",
})
if err != nil {
    panic(err)
}
defer fs.Close()

_, _ = fs.Write(ctx, "report.csv", reader)
```

Password auth:

```go
fs, _ := sftp.New(sftp.Config{
    Host:     "sftp.example.com",
    Port:     22,
    Username: "alice",
    Password: "hunter2",
    BasePath: "/uploads",
})
```

You can supply both — `pkg/sftp` will try them in order.

### Config

```go
type Config struct {
    Host       string
    Port       int    // defaults to 22 if zero
    Username   string
    Password   string
    PrivateKey []byte // PEM-encoded; not a file path
    BasePath   string
}
```

`PrivateKey` takes the key **bytes**, not a path — load the file yourself
with `os.ReadFile`. The top-level `filekit.Config.SFTPPrivateKey` env binding
treats the value as a path because `filekit.New` reads it for you, but the
driver constructor does not.

## Capabilities

| Interface | Implemented | Notes |
|---|---|---|
| `FileSystem` | yes | |
| `CanCopy` | yes | reads then writes via the same SFTP session |
| `CanMove` | yes | native `Rename` |
| `CanChecksum` | yes | streams the file and hashes it client-side |
| `CanWatch` | yes | polling-based |
| `ChunkedUploader` | yes | parts buffered and concatenated server-side |
| `CanSignURL` | no | SFTP has no URL semantics |
| `CanReadRange` | no | not implemented in this driver yet |

## Quirks

:::caution
The driver currently uses `ssh.InsecureIgnoreHostKey()` for host-key
verification. This is fine for trusted networks but **must not** be used
across the public internet without first verifying known hosts. The source
has a `// TODO` to fix this.
:::

- The connection is established eagerly inside `sftp.New`. If the host is
  unreachable, construction fails.
- `Close()` is required when you're done — it closes both the SFTP and SSH
  sessions. The driver also recovers from dropped connections automatically
  on the next call.
- `Owner` in `FileInfo` returns the numeric UID from the SSH `FileStat`;
  `CreatedAt` is always `nil` because SFTP doesn't expose creation time.
