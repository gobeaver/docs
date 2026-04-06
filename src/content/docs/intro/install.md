---
title: Install
description: How to add GoBeaver packages and the CLI to your project.
sidebar:
  order: 2
---

Each GoBeaver package is its own Go module. Pull in only the ones you need.

## Packages

```sh
go get github.com/gobeaver/configkit
go get github.com/gobeaver/filekit
go get github.com/gobeaver/beaverkit
```

## CLI

```sh
go install github.com/gobeaver/cli/cmd/beaver@latest
beaver --help
```

> Module paths are placeholders — replace with the canonical paths once
> repositories are public.
