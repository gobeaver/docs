---
title: Validate and store user uploads
description: Combine filevalidator and filekit to safely accept user files.
sidebar:
  order: 2
---

Use `filevalidator` to reject untrusted files before they touch storage,
then hand the safe payload to `filekit` for persistence.

```go
ok, err := filevalidator.Validate(reader, filevalidator.Options{
    AllowedTypes: []string{"image/png", "image/jpeg"},
    MaxSize:      5 << 20,
})
if err != nil || !ok {
    return errors.New("invalid upload")
}

if _, err := fs.Write(ctx, key, payload); err != nil {
    return err
}
```
