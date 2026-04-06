---
title: Quickstart
description: Load configuration, write a file, and ship.
sidebar:
  order: 3
---

A minimal GoBeaver app: load config from the environment, then write a file
through the filesystem abstraction.

```go
package main

import (
	"context"
	"log"

	"github.com/gobeaver/configkit"
	"github.com/gobeaver/filekit"
	localfs "github.com/gobeaver/filekit/driver/local"
)

type Config struct {
	DataDir string `env:"DATA_DIR" envDefault:"./data"`
}

func main() {
	var cfg Config
	configkit.MustLoad(&cfg)

	fs := localfs.New(cfg.DataDir)
	if _, err := fs.Write(context.Background(), "hello.txt", []byte("hi")); err != nil {
		log.Fatal(err)
	}
}
```

That's it. Swap `localfs` for `s3`, `gcs`, or any other driver without
touching the rest of the code.
