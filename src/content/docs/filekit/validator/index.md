---
title: filevalidator
description: Header-only file validation for Go with content checks for 60+ formats.
sidebar:
  order: 1
  label: Overview
---

`filevalidator` is filekit's validation subpackage. It can be used on its
own — see [Standalone use](/filekit/validator/standalone/) — or wired into a
filekit `FileSystem` via the
[`ValidatedFileSystem` decorator](/filekit/#validation).

## What it does

- Detects MIME types from magic bytes (more reliable than
  `http.DetectContentType` alone).
- Enforces size, extension, MIME type, and filename rules.
- Runs **content validators** that inspect the actual file structure for
  60+ formats.
- Catches archive attacks: zip bombs (compression-ratio limit), nested
  archives, path traversal (`../`, absolute paths), file-count bombs.
- Catches XML attacks: XXE via DTD, runaway depth.
- Catches image attacks: dimension bombs, decompression bombs, oversized
  SVGs.
- Reads only file headers — a 500 MB upload uses ~2 KB of RAM during MIME
  detection.

## Status

**Stable-ish.** Lives in its own Go module. Used by filekit's
`ValidatedFileSystem` and also imported directly by services that don't need
the rest of filekit.

## Quick start

```go
import "github.com/gobeaver/filekit/filevalidator"

// Build with the fluent API
v := filevalidator.NewBuilder().
    MaxSize(10 * filevalidator.MB).
    AcceptImages().
    Extensions(".jpg", ".jpeg", ".png", ".webp").
    WithContentValidation().
    Build()

// Validate a multipart upload
err := v.Validate(fileHeader) // *multipart.FileHeader

// Validate from a reader (HTTP body)
err = v.ValidateReader(req.Body, "upload.png", req.ContentLength)

// Validate a byte slice
err = v.ValidateBytes(data, "upload.png")
```

`Validate*` methods return `nil` on success or a `*ValidationError` carrying
an `ErrorType` (`ErrorTypeSize`, `ErrorTypeMIME`, `ErrorTypeExtension`,
`ErrorTypeContent`, …) and a human-readable message.

## Presets

```go
v := filevalidator.ForImages().Build()    // common image types, 10 MB max
v := filevalidator.ForDocuments().Build() // PDF, Office, txt/csv, 50 MB max
v := filevalidator.ForMedia().Build()     // images + audio + video, 500 MB
v := filevalidator.ForArchives().Build()  // zip/tar/gz/tgz, 1 GB
v := filevalidator.ForWeb().Build()       // images + documents, 25 MB
v := filevalidator.Strict().Build()       // strict MIME, required extension, required content checks
```

Presets return a `*Builder` so you can override individual constraints:

```go
v := filevalidator.ForImages().
    MaxSize(2 * filevalidator.MB).
    Extensions(".png", ".webp").
    Build()
```

## Builder reference (selected)

| Group | Methods |
|---|---|
| Size | `MaxSize`, `MinSize`, `SizeRange` |
| MIME | `Accept`, `AcceptImages`, `AcceptDocuments`, `AcceptAudio`, `AcceptVideo`, `AcceptMedia`, `AcceptAll`, `StrictMIME` |
| Extensions | `Extensions`, `BlockExtensions`, `RequireExtension`, `AllowNoExtension` |
| Filename | `MaxNameLength`, `FileNamePattern`, `FileNamePatternString`, `DangerousChars` |
| Content | `WithContentValidation`, `WithoutContentValidation`, `RequireContentValidation`, `WithRegistry`, `WithMinimalRegistry` |

By default content validation failures are non-blocking warnings. Call
`RequireContentValidation()` to make them hard errors.

## Supported formats

The validator covers 60+ formats grouped roughly as:

- **Images** — JPEG, PNG, GIF, WebP, BMP, TIFF, ICO, SVG, HEIC, AVIF.
  Image content validators check dimensions and total pixels via
  `image.DecodeConfig` (header read only).
- **Documents** — PDF (header/trailer structure check), DOCX/XLSX/PPTX
  (treated as ZIP, with macro detection). RTF, DOC, .docm/.xlsm/.pptm are
  recognised; macro-enabled Office formats are blocked by default.
- **Archives** — ZIP, TAR, GZIP, TAR.GZ. Run through the archive validator
  by default. RAR, 7z, BZIP2, XZ are recognised by magic bytes only.
- **Audio** — MP3, WAV, OGG, FLAC, AAC, M4A, MIDI.
- **Video** — MP4, WebM, MKV, AVI, MOV, FLV, 3GP, M4V.
- **Text & data** — JSON (depth limit), XML (XXE protection, depth limit),
  CSV (UTF-8 / row+col limits), HTML, plain text.
- **Executables** — EXE/DLL, ELF, Mach-O, shell scripts. Detected so you
  can block them.
- **Fonts** — TTF, OTF, WOFF, WOFF2.

The full table lives in
[`filevalidator/SUPPORTED.md`](https://github.com/gobeaver/filekit/blob/main/filevalidator/SUPPORTED.md)
in the source tree.

## Archive security

Archive validation defaults are conservative:

```go
// DefaultArchiveValidator():
// MaxCompressionRatio: 100
// MaxFiles:            1000
// MaxUncompressedSize: 1 GiB
// MaxNestedArchives:   3
```

Detects:

- **Zip bombs** — ratio of uncompressed to compressed bytes exceeds the
  limit.
- **Nested archive attacks** — archives within archives beyond the configured
  depth.
- **Path traversal** — `../` segments and absolute paths in entry names.
- **File-count bombs** — archives whose entry count exceeds the limit.

Tune them by passing your own constraints to the builder via
`WithRegistry(...)`.

## XML / XXE protection

`DefaultXMLValidator()` rejects DTDs (which is how XXE is delivered) and
limits depth to 100. JSON and CSV validators apply equivalent limits.

## Content-validation modes

- `WithoutContentValidation()` — MIME + size + extension only. Fastest.
- `WithContentValidation()` — runs the registered content validator for the
  detected MIME type. Failures are logged but not blocking.
- `RequireContentValidation()` — same as above, but failures hard-fail the
  validation.

## Integration with filekit

```go
import (
    "github.com/gobeaver/filekit"
    "github.com/gobeaver/filekit/filevalidator"
)

v := filevalidator.ForImages().MaxSize(5 * filevalidator.MB).Build()
vfs := filekit.NewValidatedFileSystem(fs, v)

// Every Write goes through v before reaching fs.
_, err := vfs.Write(ctx, "photo.jpg", reader)
```

Per-write override:

```go
_, _ = fs.Write(ctx, "doc.pdf", reader,
    filekit.WithValidator(filevalidator.ForDocuments().Build()),
)
```

See [the decorators section](/filekit/#validation) for the streaming
behaviour for non-seekable readers (filekit reads only the first 512 bytes
for header checks in that case).
