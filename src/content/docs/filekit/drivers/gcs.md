---
title: Google Cloud Storage
description: GCS driver for filekit.
sidebar:
  order: 3
  label: GCS
---

The `gcs` driver wraps `cloud.google.com/go/storage`'s `*storage.Client`.

## When to use it

- Object storage on Google Cloud.
- You want native pre-signed URLs and resumable uploads.

## Install

```sh
go get github.com/gobeaver/filekit/driver/gcs
go get cloud.google.com/go/storage
```

## Construct

```go
import (
    "context"
    "time"

    "cloud.google.com/go/storage"
    "github.com/gobeaver/filekit/driver/gcs"
)

ctx := context.Background()

client, err := storage.NewClient(ctx) // uses GOOGLE_APPLICATION_CREDENTIALS
if err != nil {
    panic(err)
}
defer client.Close()

fs := gcs.New(client, "my-bucket",
    gcs.WithPrefix("uploads/"),
)

_, _ = fs.Write(ctx, "doc.pdf", reader)

url, _ := fs.SignedURL(ctx, "doc.pdf", 30*time.Minute)
_ = url
```

### Options

- `gcs.WithPrefix(prefix string)` — prepended to every object name. A
  trailing `/` is added if missing.

### Credentials

Credentials are handled by the GCS SDK, not filekit. Standard mechanisms work:
`GOOGLE_APPLICATION_CREDENTIALS` pointing at a service-account JSON, workload
identity, `gcloud auth application-default login`, or
`option.WithCredentialsFile(...)` passed to `storage.NewClient`.

For pre-signed URLs to work, the client needs credentials that include a
private key — that means a service-account JSON, not metadata-server-only
auth, unless you configure `iamcredentials.signBlob`.

## Capabilities

| Interface | Implemented | Notes |
|---|---|---|
| `FileSystem` | yes | |
| `CanCopy` | yes | native `CopierFrom` |
| `CanMove` | yes | copy + delete |
| `CanSignURL` | yes | `SignedURL`, `SignedUploadURL` |
| `CanChecksum` | yes | uses object MD5/CRC32C from GCS metadata when available |
| `CanWatch` | yes | polling-based (default 30 s) |
| `ChunkedUploader` | yes | maps to GCS resumable uploads |
| `CanReadRange` | no | not implemented in this driver yet |

## Quirks

- `WriteResult.Checksum` after a write is GCS's MD5 (hex-encoded), with
  `ChecksumAlgorithm = ChecksumMD5`. GCS does not return SHA-256.
- `WithOverwrite(false)` (the default) issues an extra `Object.Attrs` call
  before uploading; this costs one round trip.
- Directory existence is checked by listing with a prefix.
