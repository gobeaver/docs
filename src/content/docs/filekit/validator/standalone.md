---
title: Using it standalone
description: Importing filevalidator without the rest of filekit.
sidebar:
  order: 2
---

`filevalidator` lives in its own Go module. You can import it without
pulling in the filekit core or any storage drivers:

```sh
go get github.com/gobeaver/filekit/filevalidator
```

## Validate an HTTP upload

```go
package main

import (
    "net/http"

    "github.com/gobeaver/filekit/filevalidator"
)

var uploads = filevalidator.NewBuilder().
    MaxSize(10 * filevalidator.MB).
    AcceptImages().
    Extensions(".jpg", ".jpeg", ".png", ".webp").
    WithContentValidation().
    Build()

func handleUpload(w http.ResponseWriter, r *http.Request) {
    if err := r.ParseMultipartForm(32 << 20); err != nil {
        http.Error(w, err.Error(), http.StatusBadRequest)
        return
    }
    fh := r.MultipartForm.File["file"][0]

    if err := uploads.Validate(fh); err != nil {
        http.Error(w, err.Error(), http.StatusUnprocessableEntity)
        return
    }

    // safe to persist
}
```

## Validate a stream you already have

```go
import (
    "context"
    "io"

    "github.com/gobeaver/filekit/filevalidator"
)

func ingest(ctx context.Context, name string, size int64, body io.Reader) error {
    v := filevalidator.ForDocuments().Build()
    return v.ValidateReader(body, name, size)
}
```

`ValidateReader` reads the first ~512 bytes for MIME detection and runs the
configured content validator. The reader is consumed only as far as the
validator needs.

## Validate a byte slice

```go
v := filevalidator.NewBuilder().
    MaxSize(1 * filevalidator.MB).
    Accept("application/json").
    WithContentValidation().
    Build()

err := v.ValidateBytes(data, "config.json")
```

## Validate a local file

```go
err := filevalidator.ValidateLocalFile(v, "/tmp/upload.png")
```

## Cancellation

All `Validate*` methods have a `WithContext` variant for cancellation:

```go
err := v.ValidateWithContext(ctx, fh)
```

## What you avoid by going standalone

Importing only `filevalidator` does not pull `github.com/gobeaver/filekit`,
so you skip every driver dependency (AWS SDK, GCS SDK, Azure SDK, pkg/sftp,
fsnotify, gobwas/glob, …). The validator module itself depends only on the
Go standard library.
