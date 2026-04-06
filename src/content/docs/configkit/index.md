---
title: configkit
description: Zero-dependency environment configuration for Go, vendoring caarlos0/env and joho/godotenv.
---

`configkit` is a small environment configuration loader for Go services. It
parses process environment variables (and optional `.env` files) into a
struct, applies a `BEAVER_` prefix by default, and exposes a single `Load`
function. It is the loader used by every other package in the Beaver
workspace, including `filekit` and `beaverkit`.

## What's inside

`configkit` is intentionally tiny. The interesting work is delegated to two
well-known libraries that are vendored directly into the module:

| Subpackage | Upstream | Version | Role |
|---|---|---|---|
| `configkit/env` | [`caarlos0/env/v11`](https://github.com/caarlos0/env) | v11.4.0 | Reflect-based env-var → struct parser |
| `configkit/dotenv` | [`joho/godotenv`](https://github.com/joho/godotenv) | v1.5.1 | `.env` file reader |

Both are MIT-licensed, both are pure stdlib, and both are copied into the
repo as plain Go source. The `go.mod` for `configkit` declares **no
external dependencies** — only a Go version:

```
module github.com/gobeaver/configkit

go 1.25.6
```

The vendored copies live under `env/CREDITS.md` and `dotenv/CREDITS.md`,
each tracking the upstream version, the date it was pulled, the reviewer,
and a note on what changed. Updates are deliberate and slow: every line of
every upstream change is reviewed by hand before it lands. Tests from the
upstream packages are excluded from the vendored tree on purpose — they
exercise reflection on internal types and pull in test-only build tags
that are easy to break under vendoring. The diff review in step 2 of the
update process is what catches regressions instead.

The wrapper itself (`config.go`, `doc.go`) is around 140 lines. It exists
to:

1. Provide a default `BEAVER_` prefix.
2. Load `.env` files automatically, but tolerate their absence.
3. Hand the result off to `env.ParseWithOptions`.

That's the whole package.

## Install

```sh
go get github.com/gobeaver/configkit
```

## Quick start

```go
package main

import (
    "fmt"

    "github.com/gobeaver/configkit"
)

type Config struct {
    Host string `env:"HOST" envDefault:"localhost"`
    Port int    `env:"PORT" envDefault:"8080"`
}

func main() {
    var cfg Config
    if err := configkit.Load(&cfg); err != nil {
        panic(err)
    }
    fmt.Printf("%+v\n", cfg)
}
```

With this `.env` next to the binary:

```sh
BEAVER_HOST=example.com
BEAVER_PORT=3000
```

`cfg` ends up as `{Host:example.com Port:3000}`. The `BEAVER_` prefix is
prepended to every `env` tag automatically.

## API

The public surface is two functions and four options.

| Symbol | Signature |
|---|---|
| `Load` | `func Load(cfg any, opts ...Option) error` |
| `MustLoad` | `func MustLoad(cfg any, opts ...Option)` |
| `WithPrefix` | `func WithPrefix(prefix string) Option` |
| `WithEnvFiles` | `func WithEnvFiles(files ...string) Option` |
| `WithoutDotEnv` | `func WithoutDotEnv() Option` |
| `WithRequired` | `func WithRequired() Option` |
| `DefaultPrefix` | `const DefaultPrefix = "BEAVER_"` |

`MustLoad` panics on error; the panic value is the same `error` `Load`
would have returned, so callers can `recover` and use `errors.Is` /
`errors.As`.

### Options

#### `WithPrefix`

Override the default `BEAVER_` prefix. Pass `""` to disable prefixing.

```go
import "github.com/gobeaver/configkit"

configkit.Load(&cfg, configkit.WithPrefix("APP_"))
configkit.Load(&cfg, configkit.WithPrefix(""))
```

#### `WithEnvFiles`

Choose which `.env` files to read. Defaults to `[".env"]`. Files are
loaded in order, **first-wins**: if both files set the same key, the
earlier one keeps its value. List your override file first:

```go
import "github.com/gobeaver/configkit"

configkit.Load(&cfg, configkit.WithEnvFiles(".env.local", ".env"))
```

#### `WithoutDotEnv`

Skip `.env` loading entirely. Useful in tests and in environments where
all configuration comes from the process env.

```go
import "github.com/gobeaver/configkit"

configkit.Load(&cfg, configkit.WithoutDotEnv())
```

#### `WithRequired`

Treat every field without an `envDefault` tag as required. Equivalent to
adding `,required` to every `env` tag manually.

```go
import "github.com/gobeaver/configkit"

configkit.Load(&cfg, configkit.WithRequired())
```

## Precedence

Highest wins:

1. Process environment variables (set by the OS, container, shell, CI).
2. Earlier entries in `WithEnvFiles`.
3. Later entries in `WithEnvFiles`.
4. `envDefault` tag values on the struct.

This matches the III. Config principle of [12-factor](https://12factor.net/config):
deployment platforms are always the source of truth, and `.env` is a
developer-ergonomics layer for local work.

A **missing** `.env` is silently ignored — projects that don't ship one
incur no cost. A **malformed** `.env` returns an error from `Load` rather
than being swallowed.

## Struct tag reference

`configkit` exposes the full tag vocabulary of the vendored
`caarlos0/env/v11`:

| Tag | Example | Meaning |
|---|---|---|
| `env` | `env:"HOST"` | Variable name (gets the prefix prepended) |
| `envDefault` | `envDefault:"8080"` | Value used when the env var is not set |
| `envPrefix` | `envPrefix:"DB_"` | Per-field prefix, used on nested structs |
| `envSeparator` | `envSeparator:","` | Separator for slice/array fields |
| `,required` | `env:"API_KEY,required"` | Fail if the variable is unset |
| `,notEmpty` | `env:"NAME,notEmpty"` | Fail if the variable is set but empty |
| `,unset` | `env:"SECRET,unset"` | Unset the variable from the process env after reading |
| `,expand` | `env:"URL,expand"` | Expand `${VAR}` references against the process env |
| `,file` | `env:"TLS_KEY,file"` | Treat the value as a file path and read its contents |
| `,init` | `env:"X,init"` | Initialize nil pointer fields even when no env value is present |
| `env:"-"` | `env:"-"` | Skip the field |

Supported field types are everything `caarlos0/env` handles: all the basic
scalars, `time.Duration`, slices and maps with `envSeparator`, pointers,
nested structs via `envPrefix`, and any type implementing
`encoding.TextUnmarshaler` or the package's own unmarshaler interfaces.

Example pulling several of these together:

```go
package config

import "time"

type Database struct {
    Host string `env:"HOST" envDefault:"localhost"`
    Port int    `env:"PORT" envDefault:"5432"`
}

type Config struct {
    APIKey   string        `env:"API_KEY,required"`
    Hosts    []string      `env:"HOSTS" envSeparator:","`
    Metadata map[string]string `env:"METADATA"`
    Timeout  time.Duration `env:"TIMEOUT" envDefault:"5s"`
    TLSKey   string        `env:"TLS_KEY,file"`
    Database Database      `envPrefix:"DB_"`
}
```

With the default prefix, `Database.Host` is read from `BEAVER_DB_HOST`.

## Multi-instance pattern

The prefix-swap pattern lets you load multiple configured instances of the
same package without YAML, profiles, or config files:

```sh
DEV_SLACK_WEBHOOK_URL=https://hooks.slack.com/dev
PROD_SLACK_WEBHOOK_URL=https://hooks.slack.com/prod

PRIMARY_DB_HOST=primary.db.example.com
REPLICA_DB_HOST=replica.db.example.com
```

```go
package main

import "github.com/gobeaver/configkit"

type SlackConfig struct {
    WebhookURL string `env:"SLACK_WEBHOOK_URL,required"`
}

func main() {
    var dev, prod SlackConfig
    configkit.MustLoad(&dev,  configkit.WithPrefix("DEV_"))
    configkit.MustLoad(&prod, configkit.WithPrefix("PROD_"))
}
```

Two fully-configured Slack clients, side by side, in 12-factor-compliant
fashion. The same trick works for primary/replica databases, blue/green
queues, anything you'd otherwise resort to YAML profiles for.

## `.env` file syntax

The vendored `joho/godotenv` parser supports the standard `.env` dialect:

```sh
# Comments start with a hash and run to end-of-line.
HOST=example.com
PORT=3000

# Single quotes are taken literally.
GREETING='hello $USER'

# Double quotes interpret \n, \r, \t and expand $VAR / ${VAR} references.
BANNER="line one\nline two"
HOME_URL="https://${HOST}/"

# `export` is allowed as a no-op prefix for shell compatibility.
export TOKEN=abc123

# Inline trailing comments after an unquoted value are stripped.
TIMEOUT=30 # seconds
```

A few details worth knowing:

- Variable expansion (`$VAR`, `${VAR}`) only happens inside double-quoted
  values, and resolves against variables already loaded into the parser's
  scope plus the process env.
- Backslash-escaped quotes inside a quoted string are honoured.
- An unterminated quoted value is a hard parse error and aborts `Load`.

## Error handling

`Load` returns a single `error`. Validation failures from the env parser
are aggregated rather than short-circuited: if three required fields are
missing, all three show up in one error. The aggregator is
`env.AggregateError`, which implements the Go 1.20 `Unwrap() []error`
contract, so `errors.Is` and `errors.As` work transparently — and so does
plain `errors.Unwrap` if you want to walk the list yourself:

```go
import (
    "errors"
    "fmt"

    "github.com/gobeaver/configkit"
    "github.com/gobeaver/configkit/env"
)

if err := configkit.Load(&cfg); err != nil {
    var agg env.AggregateError
    if errors.As(err, &agg) {
        for _, e := range agg.Errors {
            fmt.Println("config problem:", e)
        }
    }
    return err
}
```

`Load` wraps every error it returns with a `configkit:` prefix. `.env`
parse failures are wrapped further with the file name:
`configkit: loading .env.local: ...`.

## Vendoring policy

`configkit` treats its dependencies as source code, not as a graph to
resolve. The discipline is:

- **No external runtime deps.** Confirmed by the three-line `go.mod`.
- **CREDITS.md per vendor.** Records upstream version, pull date,
  reviewer, and per-version notes.
- **Manual line-by-line review on update.** No `go get -u`, no Dependabot.
  The maintainer clones the upstream repo, diffs the target tag against
  the currently vendored tag, and reads every changed line.
- **Deliberate lag.** Updates wait 3–6 months behind upstream unless
  there's a security advisory or a feature the wrapper actually needs.
- **Tests excluded from the vendored tree.** Upstream test files are not
  copied — they exercise reflection on internal types and add significant
  on-disk weight without testing anything Beaver consumes. Configkit's own
  tests cover the wrapper surface.
- **Minimal patching.** The only modification to either upstream is the
  `dotenv` package being renamed from `godotenv` to `dotenv` to match the
  directory name.

For teams that care about supply-chain hygiene, this means a `configkit`
upgrade is a normal code review, not a trust delegation.

## Status

**Stable-ish.** The surface area is small, the wrapper itself is unlikely
to change, and the vendored libraries are mature. Pin the version you
use, follow the vendor update process when bumping, and `configkit` will
stay out of your way.
