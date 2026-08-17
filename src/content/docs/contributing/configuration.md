---
title: Configuration
description: How a GoBeaver package loads its configuration with configkit.
sidebar:
  order: 3
---

Every configurable GoBeaver package loads its settings the same way: a `Config`
struct with `env` tags, loaded by [`configkit`](/configkit/), wrapped in a
fixed set of constructors. Learn it once and every package in the ecosystem
behaves identically.

Two hard rules:

- **No `os.Getenv` in package code.** Configuration is a struct, loaded in one
  place, validated in one place. `forbidigo` fails `make lint` — and therefore
  CI — on `os.Getenv` outside the config layer; see
  [Linting](/contributing/linting/).
- **No prefix in struct tags.** The prefix is applied by the loader, which is
  what makes multi-instance configuration possible.

## Which loader to import

| Module | Import path | Use it when |
|---|---|---|
| `configkit` | `github.com/gobeaver/configkit` | **New code.** Standalone, zero external deps. |
| `beaver-kit/config` | `github.com/gobeaver/beaver-kit/config` | Existing beaver-kit packages, until they migrate. |

Import `configkit` unless you are editing a beaver-kit package that already
imports the other one. The two are not interchangeable today:

- `configkit` exposes `Load`, `MustLoad`, and the `WithPrefix`, `WithEnvFiles`,
  `WithoutDotEnv`, `WithRequired` options.
- `beaver-kit/config` grew the same option API in its working tree, but the only
  **published** version (`v0.1.0`) is the older hand-rolled loader: `Load(cfg,
  ...LoadOptions)` and nothing else — no `MustLoad`, no options, no
  `envDefault` / `,required` / `envPrefix` / slice support.
- Even the unreleased beaver-kit version differs in behavior: it ignores every
  `.env` error (`_ = dotenv.Load(file)`), so a malformed file passes silently,
  and its `MustLoad` panics with a `string` rather than an `error`.

:::caution[Older API still in the wild]
`filekit` pins `beaver-kit/config v0.1.0`. It puts a package prefix inside the
tag (`env:"FILEKIT_DRIVER,default:local"`) *and* gets the loader's default
`BEAVER_` prefix on top, because its `GetConfig` calls `config.Load(cfg)` with
no options — so the variable it actually reads is `BEAVER_FILEKIT_DRIVER`. Its
`Builder` methods pass `config.Load(cfg, config.LoadOptions{Prefix: p})`, which
replaces `BEAVER_` outright.

That is the *old* shape, and the double prefix is exactly the confusion this
convention exists to prevent. Don't copy it into new packages; when filekit
moves to `configkit`, its tags become `env:"DRIVER" envDefault:"local"` with
`FILEKIT_` moved into the prefix.
:::

## The Config struct

```go
// Config is the package configuration.
//
// Tags carry no prefix: the prefix is applied by the loader so the same struct
// can back several independently-configured instances.
type Config struct {
	// Endpoint is the upstream base URL.
	Endpoint string `env:"ENDPOINT" envDefault:"http://localhost:9000"`

	// Token authenticates against Endpoint. No default: a missing token is a
	// startup failure, not a silent fallback.
	Token string `env:"TOKEN,required"`

	// Timeout bounds a single request.
	Timeout time.Duration `env:"TIMEOUT" envDefault:"5s"`
}

// Service is the thing this package hands out.
type Service struct {
	cfg Config
}
```

- Every field gets a doc comment. It is the source for the config table in the
  README.
- Every optional field gets an `envDefault`. Zero-config `Init()` must work.
- Secrets get `,required` and no default. Fail at startup, loudly.
- Group related settings in a nested struct with `envPrefix:"DB_"` rather than
  prefixing field names by hand.
- The full tag vocabulary (`envSeparator`, `,notEmpty`, `,file`, `,expand`, …)
  is on the [configkit page](/configkit/#struct-tag-reference).

## The pattern

These six blocks are a complete, working package. Assembled in this order —

1. block 1 (the `package` clause and imports),
2. the `Config` and `Service` types from the section above,
3. blocks 2 through 6

— the result builds, vets, passes the tests further down, and reports zero
issues under the [canonical lint config](/contributing/linting/). In a real
package, split it into `config.go` and `service.go` as described in
[Package layout](/contributing/package-layout/#single-module-package).

Two import notes: `time` comes in with the `Config` struct, and `context` comes
in with block 6 — if your package holds no resources you drop both block 6 and
the `context` import.

### 1. Prefix and sentinel errors

```go
// Package mykit is a template service module: Config + New + Init + accessor.
package mykit

import (
	"context"
	"errors"
	"fmt"
	"sync"
	"time"

	"github.com/gobeaver/configkit"
)

// EnvPrefix is the default environment prefix for this package.
const EnvPrefix = configkit.DefaultPrefix + "MYKIT_"

// Sentinel errors. Wrap these — never return a bare errors.New from validation.
var (
	ErrInvalidConfig  = errors.New("mykit: invalid config")
	ErrNotInitialized = errors.New("mykit: not initialized")
)
```

`configkit.DefaultPrefix` is `"BEAVER_"`, so this package reads
`BEAVER_MYKIT_ENDPOINT`, `BEAVER_MYKIT_TOKEN`, `BEAVER_MYKIT_TIMEOUT`.

### 2. GetConfig

```go
// GetConfig loads Config from the environment.
//
// With no options it uses EnvPrefix. Passing any option replaces that default,
// so callers who want a different prefix pass configkit.WithPrefix themselves.
func GetConfig(opts ...configkit.Option) (*Config, error) {
	if len(opts) == 0 {
		opts = []configkit.Option{configkit.WithPrefix(EnvPrefix)}
	}

	cfg := &Config{}
	if err := configkit.Load(cfg, opts...); err != nil {
		return nil, fmt.Errorf("mykit: load config: %w", err)
	}
	return cfg, nil
}
```

### 3. New — the only place validation lives

```go
// New validates cfg and builds a Service. All validation lives here.
func New(cfg Config) (*Service, error) {
	if cfg.Endpoint == "" {
		return nil, fmt.Errorf("%w: endpoint is required", ErrInvalidConfig)
	}
	if cfg.Timeout <= 0 {
		return nil, fmt.Errorf("%w: timeout must be positive", ErrInvalidConfig)
	}
	return &Service{cfg: cfg}, nil
}
```

Validate in `New`, not in `Init` and not in `GetConfig` — every construction
path funnels through it. Always wrap a sentinel with `%w` so callers can use
`errors.Is`.

### 4. Singleton, accessor, Reset

```go
var (
	defaultService *Service
	defaultOnce    sync.Once
	defaultErr     error
)

// Init initializes the package singleton. Zero-config Init() — no arguments,
// everything from the environment — must work.
//
// Init runs at most once per process: a second call is a no-op even with a
// different config. Use New for additional instances.
func Init(configs ...Config) error {
	defaultOnce.Do(func() {
		var cfg *Config
		if len(configs) > 0 {
			cfg = &configs[0]
		} else {
			cfg, defaultErr = GetConfig()
			if defaultErr != nil {
				return
			}
		}
		defaultService, defaultErr = New(*cfg)
	})
	return defaultErr
}

// Client is the package accessor: the entry point most callers use.
func Client() *Service {
	if defaultService == nil {
		_ = Init()
	}
	return defaultService
}

// Default is the error-returning form of Client. Prefer it at startup: a failed
// Init is sticky, and Client would hand back nil.
func Default() (*Service, error) {
	if defaultService == nil {
		if err := Init(); err != nil {
			return nil, err
		}
	}
	return defaultService, nil
}

// Health reports whether the singleton is usable. Packages holding a connection
// extend this to a real ping.
func Health() error {
	if defaultService == nil {
		return ErrNotInitialized
	}
	return nil
}

// Reset clears the singleton. Tests only — always `defer mykit.Reset()`.
func Reset() {
	defaultService = nil
	defaultOnce = sync.Once{}
	defaultErr = nil
}
```

Name the accessor after the thing it returns — `DB()`, `FS()`, `Client()`,
`Service()` — never `GetX()`. It swallows the initialization error by design so
the common path stays a one-liner.

:::caution[A failed Init is sticky]
`sync.Once` fires even when initialization fails. After one failed `Init()`,
every later `Init(validConfig)` returns that same original error, and `Client()`
hands back a **nil** pointer that the caller dereferences on first use. Only
`Reset()` re-arms the `Once`, and `Reset` is for tests.

So: call `Default()` (or check `Init`'s error) once at startup and fail fast
there. `Client()` is for code that runs after startup has already succeeded.
:::

Global state is exactly three variables: the instance, the `sync.Once`, and the
error. Nothing else.

### 5. Builder for extra instances

```go
// Builder creates instances bound to a custom environment prefix.
type Builder struct {
	prefix string
}

// WithPrefix returns a Builder that reads <prefix>ENDPOINT, <prefix>TOKEN, ...
// The prefix replaces EnvPrefix entirely; it is not appended to it.
func WithPrefix(prefix string) *Builder {
	return &Builder{prefix: prefix}
}

// New builds an instance from the builder's prefix.
func (b *Builder) New() (*Service, error) {
	cfg, err := GetConfig(configkit.WithPrefix(b.prefix))
	if err != nil {
		return nil, err
	}
	return New(*cfg)
}

// Init initializes the singleton from the builder's prefix.
func (b *Builder) Init() error {
	cfg, err := GetConfig(configkit.WithPrefix(b.prefix))
	if err != nil {
		return err
	}
	return Init(*cfg)
}
```

This is how multi-tenant and primary/replica setups work, without YAML:

```sh
REPLICA_ENDPOINT=http://replica.internal
REPLICA_TOKEN=…
```

```go
replica, err := mykit.WithPrefix("REPLICA_").New()
```

The builder prefix is used **verbatim** — `WithPrefix("REPLICA_")` reads
`REPLICA_TOKEN`, not `BEAVER_REPLICA_TOKEN`.

`Builder.New()` is what creates extra instances. `Builder.Init()` does **not** —
it feeds the same singleton through the same `sync.Once`, so it is silently
discarded if `Init` has already run. Use it as the first initialization of a
process that wants a non-default prefix, and use `Builder.New()` for everything
else.

### 6. Shutdown — only if you hold resources

```go
// Close releases resources held by this instance.
func (s *Service) Close(_ context.Context) error { return nil }

// Shutdown closes the singleton and clears it, so a stale Service is never
// handed out afterwards. It is terminal: sync.Once has already fired, so Init
// will not rebuild. Only packages that hold resources get one.
func Shutdown(ctx context.Context) error {
	if defaultService == nil {
		return nil
	}
	err := defaultService.Close(ctx)
	defaultService = nil
	return err
}
```

| Ship `Shutdown` | Don't ship `Shutdown` |
|---|---|
| DB and cache connections, message queues, network listeners, background workers, open file handles | Crypto and validators, pure computation, config parsers, stateless HTTP helpers |

Clearing `defaultService` matters: without it, `Client()` keeps handing out a
closed instance for the rest of the process.

## Context

`Init` and `New` are deliberately context-free — most packages don't need one
to construct, and keeping the signature bare keeps the zero-config path a
single call. Add `InitWithContext` / `NewWithContext` only when construction
makes a network call or could hang. Operations always take a context.

## Testing

```go
func TestInitFromEnv(t *testing.T) {
	defer mykit.Reset()

	t.Setenv("BEAVER_MYKIT_TOKEN", "s3cret")
	t.Setenv("BEAVER_MYKIT_TIMEOUT", "2s")

	if err := mykit.Init(); err != nil {
		t.Fatalf("Init: %v", err)
	}
}

func TestMissingRequiredFieldFails(t *testing.T) {
	defer mykit.Reset()

	if err := mykit.Init(); err == nil {
		t.Fatal("expected an error when BEAVER_MYKIT_TOKEN is unset")
	}
}
```

- `defer pkg.Reset()` in **every** test that calls `Init`. Without it the
  `sync.Once` leaks into the next test and you get order-dependent failures.
- `t.Setenv` handles cleanup and forbids `t.Parallel` in that test — which is
  what you want for singleton tests.
- To keep a developer's local `.env` out of a test, load explicitly and pass
  **both** options — any option replaces the default, so omitting `WithPrefix`
  silently drops back to a bare `BEAVER_` prefix:

  ```go
  cfg, err := mykit.GetConfig(
      configkit.WithPrefix(mykit.EnvPrefix),
      configkit.WithoutDotEnv(),
  )
  if err != nil {
      t.Fatal(err)
  }
  if err := mykit.Init(*cfg); err != nil {
      t.Fatal(err)
  }
  ```

  There is no way to thread an option through `Init()` itself — that is the
  point of `GetConfig` being exported.
- Test `New` directly for the multi-instance cases; it has no global state.

## Environment variable reference

| Rule | Example |
|---|---|
| Default prefix | `BEAVER_` |
| Package prefix | `BEAVER_<PKG>_` — `BEAVER_MYKIT_TOKEN` |
| Nested struct | `envPrefix:"DB_"` → `BEAVER_MYKIT_DB_HOST` |
| Custom instance | `WithPrefix("REPLICA_")` → `REPLICA_TOKEN` |
| Precedence | process env > earlier `.env` file > later `.env` file > `envDefault` |

A missing `.env` is ignored; a malformed one is an error. Details on the
[configkit page](/configkit/#precedence).

## Non-service packages

Packages with no configuration and no global state — validators, pure
functions, encoders — skip all of this and just export functions. The pattern
applies to service modules only; don't add a `Config` struct to a package that
has nothing to configure.
