---
title: Azure Blob Storage
description: Azure Blob Storage driver for filekit.
sidebar:
  order: 4
  label: Azure
---

The `azure` driver wraps
`github.com/Azure/azure-sdk-for-go/sdk/storage/azblob`'s `*azblob.Client`. It
targets the Blob storage service (not Files / Queues / Tables).

## When to use it

- Object storage on Microsoft Azure.
- You need SAS pre-signed URLs and block-blob multipart uploads.

## Install

```sh
go get github.com/gobeaver/filekit/driver/azure
go get github.com/Azure/azure-sdk-for-go/sdk/storage/azblob
```

## Construct

```go
import (
    "context"
    "fmt"

    "github.com/Azure/azure-sdk-for-go/sdk/storage/azblob"
    "github.com/gobeaver/filekit/driver/azure"
)

ctx := context.Background()

accountName := "myaccount"
accountKey := "..." // base64 storage account key

cred, err := azblob.NewSharedKeyCredential(accountName, accountKey)
if err != nil {
    panic(err)
}

serviceURL := fmt.Sprintf("https://%s.blob.core.windows.net/", accountName)
client, err := azblob.NewClientWithSharedKeyCredential(serviceURL, cred, nil)
if err != nil {
    panic(err)
}

fs := azure.New(client, "my-container", accountName, accountKey,
    azure.WithPrefix("uploads/"),
)

_, _ = fs.Write(ctx, "report.pdf", reader)
```

### Constructor signature

```go
func New(
    client *azblob.Client,
    containerName string,
    accountName string,
    accountKey string,
    options ...AdapterOption,
) *Adapter
```

The account name and key are required separately because the driver uses them
to sign SAS URLs for `SignedURL` / `SignedUploadURL` — the `*azblob.Client`
itself doesn't expose the credential after construction.

If you authenticate via Azure AD / managed identity instead of a shared key,
pass empty strings for `accountName`/`accountKey` and accept that signed URLs
won't work; everything else still does.

### Options

- `azure.WithPrefix(prefix string)` — prepended to every blob name.

## Capabilities

| Interface | Implemented | Notes |
|---|---|---|
| `FileSystem` | yes | |
| `CanCopy` | yes | server-side `StartCopyFromURL` |
| `CanMove` | yes | copy + delete |
| `CanSignURL` | yes | service SAS via shared key |
| `CanChecksum` | yes | computes SHA-256 client-side on `Write` |
| `CanWatch` | yes | polling-based (default 30 s) |
| `ChunkedUploader` | yes | block-blob `StageBlock` / `CommitBlockList` |
| `CanReadRange` | no | not implemented in this driver yet |

## Quirks

- `Write` reads the entire reader into memory before calling `UploadBuffer` —
  for large uploads use the `ChunkedUploader` API instead.
- The driver always computes a SHA-256 checksum client-side and returns it
  in `WriteResult.Checksum`.
- Azure metadata keys must be valid C# identifiers; the driver does not
  rewrite them, so passing keys with hyphens via `WithMetadata` will be
  rejected by Azure at request time.
