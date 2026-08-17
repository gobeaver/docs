---
title: Package layout
description: How a GoBeaver package is laid out on disk.
sidebar:
  order: 2
---

New GoBeaver packages ship as independent Go modules published under
`github.com/gobeaver/*`. There is no monorepo `go.work` and no shared root
`go.mod`. A package that can't stand on its own doesn't ship.

The exception is `beaver-kit`, a legacy umbrella module: `cache`, `captcha`,
`database`, `krypto`, `oauth`, `slack`, and `urlsigner` are plain packages
inside the single `github.com/gobeaver/beaver-kit` module, with only
`beaver-kit/config` carved out as its own module. Don't add to it — new work
gets its own module, the way `configkit` and `filekit` did.

## Single-module package

Most packages are one module, one Go package, flat files at the root. This is
the `filekit`-core shape:

```
mykit/
├── go.mod
├── doc.go              # package comment lives here, nowhere else
├── service.go          # the primary type and its interfaces
├── config.go           # Config struct + GetConfig + Init + accessor
├── options.go          # functional options, if the package has any
├── errors.go           # sentinel errors and error helpers
├── service_test.go
├── example_test.go     # godoc-rendered Example functions
├── examples/           # runnable programs, one dir each
│   └── basic/main.go
├── llm.yaml            # optional: compact machine-readable API summary
├── README.md
├── LICENSE
├── Makefile
├── .golangci.yml
└── .gitignore
```

This is the target shape, not a census of what exists today: `options.go` is
currently unique to filekit, `errors.go` appears in four packages, and several
beaver-kit packages still lack a `doc.go`. New modules are expected to hit it.

Rules that are not negotiable:

- **Flat, not nested.** No `pkg/`, no `src/`, no `internal/` unless something
  genuinely must be unimportable by callers. `filekit`'s core is 18 non-test Go
  files at the module root with zero internal packages — that is the target, not
  an accident. Sub-directories are for vendored third-party source
  (`configkit/env`, `configkit/dotenv`) and for sub-modules, not for filing your
  own package away by category.
- **One file per concern, named after the concern.** `encryption.go`,
  `mount.go`, `selector.go`, `readonly.go`. A reader should be able to guess
  the filename from the feature name.
- **`doc.go` holds the package comment.** `revive`'s `package-comments` rule is
  on, so a missing one fails lint. Keep the runnable examples in the comment in
  sync with the README.
- **Tests sit next to the code they test.** `example_test.go` is for godoc;
  `examples/` is for programs a human runs.
- **Naming follows the workspace rules.** Lowercase package names with no
  underscores (`filevalidator`, not `file_validator`), no stuttering
  (`filekit.New`, not `filekit.NewFileKit`), no `Get` prefix on accessors
  (`Client()`, not `GetClient()`). `GetConfig` is the one sanctioned exception —
  it is the convention's name for env loading and appears in every package.
  `oauth.GetService` and `oauth.GetMultiProviderService` predate the rule and
  should be renamed, not imitated.

### Application projects

The layout above is for *libraries*. Services built on top of GoBeaver follow
the module boundaries described in [Modular Monolith](/concepts/modular-monolith/)
and are scaffolded by `beaver init` — see the [CLI docs](/cli/).

## When to split into sub-modules

Split a package into multiple modules for exactly one reason: **a subset of it
drags in dependencies most callers don't want.**

`filekit` is the worked example. Its S3 driver needs the AWS SDK, its GCS
driver needs Google's, its Azure driver needs Microsoft's. Bundling all three
into one module would make `go get filekit` pull three cloud SDKs to write a
file to `/tmp`. So each driver is its own module and the core depends on no
cloud SDK at all:

```
filekit/
├── go.mod                     # github.com/gobeaver/filekit — core, no cloud SDK deps
├── .golangci.yml              # one config, applies to every module below
├── Makefile                   # fans every target out across MODULES
├── filevalidator/
│   └── go.mod                 # …/filekit/filevalidator — usable standalone
└── driver/
    ├── local/
    │   ├── go.mod             # …/filekit/driver/local
    │   ├── local.go           # the adapter: implements filekit.FileSystem
    │   ├── register.go        # init() → filekit.RegisterDriver("local", …)
    │   └── stat_darwin.go     # build-tagged platform files
    ├── memory/
    ├── s3/
    ├── gcs/
    ├── azure/
    ├── sftp/
    └── zip/
```

Nine modules in one repository. Do not reach for this shape to express "these
are different concerns" — that is what files and types are for. Splitting costs
you version skew, `replace` bookkeeping, and release choreography on every tag.

### Driver sub-module contents

A driver module contains the adapter and a registration file, nothing else:

```go
// driver/local/register.go
package local

import "github.com/gobeaver/filekit"

func init() {
	filekit.RegisterDriver("local", func(cfg *filekit.Config) (filekit.FileSystem, error) {
		return New(cfg.LocalBasePath)
	})
}
```

The core owns the registry (`RegisterDriver` / `CreateDriver`, guarded by an
`RWMutex`), and no non-test file in the core imports a driver. Importing the
driver package for its side effect is what makes it available to the
config-driven constructor, while `local.New(...)` stays available for callers
who want to skip the registry.

The core's own `go.mod` does require `driver/local` and `driver/memory` — but
only because its `example_test.go` and `examples/` use them. Keep that
dependency confined to test and example code; the moment a production file in
the core imports a driver, the dependency isolation the split bought you is
gone.

### go.mod wiring

Each sub-module requires the core at a **real published version** and carries a
`replace` for local development:

```
// driver/s3/go.mod
require github.com/gobeaver/filekit v0.0.4

replace github.com/gobeaver/filekit => ../..
replace github.com/gobeaver/filekit/filevalidator => ../../filevalidator
```

The parent does the mirror image for the sub-modules it depends on:

```
// go.mod
require (
	github.com/gobeaver/filekit/driver/local v0.0.4
	github.com/gobeaver/filekit/driver/memory v0.0.4
	github.com/gobeaver/filekit/filevalidator v0.0.4
)

replace (
	github.com/gobeaver/filekit/driver/local  => ./driver/local
	github.com/gobeaver/filekit/driver/memory => ./driver/memory
	github.com/gobeaver/filekit/filevalidator => ./filevalidator
)
```

filekit's `go.mod` also carries an `exclude` block for every published
`github.com/gobeaver/beaver-kit` version. That is not boilerplate: because
`beaver-kit/config` is a module nested inside `beaver-kit`, both can supply the
same import path, and excluding the parent versions is what keeps the import
unambiguous. Any repo that consumes a nested module pair needs the same
treatment.

:::caution[The bug this prevents]
`replace` directives mask the version in `require` for local builds — so a
`go.mod` requiring a sibling at `v0.0.0` or at a pseudo-version builds
perfectly on your machine and is **unimportable once published**. That is
exactly what broke filekit v0.0.1 through v0.0.3.

`make verify-release-mods` greps every `go.mod` for both patterns and fails the
build. It runs inside `make check`, and `make release` re-runs it by invoking
`make check`. Never weaken it.

**`beaver-kit` currently ships this bug**: its `go.mod` requires
`github.com/gobeaver/beaver-kit/config` at
`v0.0.0-00010101000000-000000000000`, masked by a `replace ./config`. Its
Makefile has no `verify-release-mods` target, and filekit's gate only greps
`github.com/gobeaver/filekit*` paths, so nothing catches it. Fix the require
before beaver-kit is tagged again.
:::

When you change a package that another module consumes through `replace`, run
`go mod tidy` in **both** modules. This applies to `beaver-kit` and
`beaver-kit/config` too.

## Releasing a multi-module package

All modules are tagged at the same commit with the same version. Go derives a
sub-module's tag from its directory: `driver/s3/v0.0.5` is what
`github.com/gobeaver/filekit/driver/s3@v0.0.5` resolves to.

1. Bump every `go.mod` that requires a sibling to the version you're about to
   tag (e.g. `v0.0.5`). Local builds keep working via `replace`.
2. Build and test everything: `make check`.
3. Commit the bumps.
4. `make release` — it refuses to run on a dirty tree, off `main`, with
   placeholder versions, with failing checks, or if any proposed tag already
   exists. Then it tags all nine modules and pushes them.

## Makefile

One Makefile at the repo root, with an explicit module list so every target
fans out instead of silently testing only the core:

```make
MODULES = . filevalidator driver/local driver/memory driver/s3 \
          driver/gcs driver/azure driver/sftp driver/zip

test:
	@set -e; for d in $(MODULES); do (cd "$$d" && go test ./...); done
```

Targets a new module is expected to have: `test`, `test-race`,
`test-coverage`, `lint`, `fmt`, `vet`, `tidy`, `check`, `ci`. Multi-module repos
add `verify-release-mods`; any repo that publishes tags adds `release`
(`configkit` has one despite being a single module). The existing Makefiles
aren't uniform — configkit names its coverage target `cover` and has no `bench`
or `ci` — so copy filekit's, which is the most complete.

Security tools are pinned by version and invoked with `go run` so contributors
don't have to install them (filekit and configkit do this; `beaver-kit` has no
`gosec`, `vuln`, or `sec` target yet):

```make
GOSEC_VERSION = v2.21.4

gosec:
	@set -e; for d in $(MODULES); do \
		(cd "$$d" && go run github.com/securego/gosec/v2/cmd/gosec@$(GOSEC_VERSION) -quiet ./...); \
	done
```

## Checklist for a new package

- [ ] `go.mod` with the `github.com/gobeaver/<name>` path and a current Go version
- [ ] `doc.go` with a package comment that includes a usage example
- [ ] `config.go` following the [configuration convention](/contributing/configuration/)
- [ ] `errors.go` with sentinel errors
- [ ] Unit test for the happy path, plus `Reset()` used in any test that calls `Init`
- [ ] `README.md`: purpose, install, usage for each init style, config table
- [ ] `Makefile` with the standard targets
- [ ] `.golangci.yml` — see [Linting](/contributing/linting/) — passing with zero issues
- [ ] `examples/` with at least one runnable program
