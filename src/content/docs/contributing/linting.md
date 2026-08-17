---
title: Linting
description: The canonical .golangci.yml for GoBeaver modules.
sidebar:
  order: 4
---

Every GoBeaver repository ships one `.golangci.yml` at its root and is expected
to lint clean. The config below is the canonical one — copy it verbatim into a
new package and only diverge with a comment explaining why.

## golangci-lint v2 is required

The config schema changed in golangci-lint v2. A v1 config fails hard on a v2
binary — it does not degrade, it refuses to start:

```
Error: can't load config: unsupported version of the configuration: "" See https://golangci-lint.run/docs/product/migration-guide for migration instructions
```

So the first line of every config is the schema version:

```yaml
version: "2"
```

What moved in v2, and what it means for a config you're copying from older code:

| v1 | v2 |
|---|---|
| `linters-settings:` | `linters.settings:` |
| `issues.exclude-rules:` / `exclude-dirs:` | `linters.exclusions.rules:` / `.paths:` |
| `gofmt`, `goimports` under `linters` | top-level `formatters:` block |
| `gosimple` listed explicitly | folded into `staticcheck` |
| `typecheck` listed explicitly | not a linter; compilation errors are always reported |
| `errcheck`, `govet`, `ineffassign`, `staticcheck`, `unused` in `enable` | on by default via `linters.default: standard` |
| `run.timeout` | still valid, but the default is now "no timeout"; `migrate` drops the key |

To convert an existing file, don't do it by hand:

```sh
golangci-lint migrate            # rewrites .golangci.yml, backs up to .golangci.bck.yml
golangci-lint config verify      # exits 0 when the schema is valid
```

`migrate` does not carry your comments over — re-add the section headers
afterwards.

:::note[Current state of the workspace]
Both `filekit/.golangci.yml` and `beaver-kit/.golangci.yml` are still v1, so
`make lint` fails on a current golangci-lint (v2.12.2 at the time of writing).
Migrating them is a mechanical change; filekit's root module reports 5 issues
under the canonical config below — 2 `gocyclo`, 2 `nestif`, and 1 `gocritic`
that lands in `examples/`.
:::

## The canonical config

```yaml
# Canonical GoBeaver lint config (golangci-lint v2 schema).
version: "2"

run:
  modules-download-mode: readonly

linters:
  # standard = errcheck, govet, ineffassign, staticcheck, unused (always on in v2)
  default: standard
  enable:
    # Bug prevention & security
    - bidichk
    - bodyclose
    - errorlint
    - gosec
    - nilerr
    - noctx
    - sqlclosecheck

    # Style & conventions
    - gocritic
    - predeclared
    - revive

    # Code quality
    - nakedret
    - nolintlint
    - unconvert
    - unparam

    # Complexity
    - gocyclo
    - nestif

    # Project rules
    - forbidigo

  settings:
    errorlint:
      errorf: true
      asserts: true
      comparison: true

    forbidigo:
      forbid:
        - pattern: ^os\.Getenv$
          msg: use configkit.Load into a Config struct instead of os.Getenv

    gocritic:
      enabled-tags:
        - diagnostic
        - style
        - performance
      disabled-checks:
        - commentedOutCode
        - whyNoLint
        - unnamedResult

    gocyclo:
      min-complexity: 15

    nestif:
      min-complexity: 5

    nakedret:
      max-func-lines: 30

    nolintlint:
      require-explanation: true
      require-specific: true
      allow-unused: false

    revive:
      rules:
        - name: exported
          severity: warning
        - name: package-comments
          severity: warning
        - name: var-naming
          severity: warning

    unparam:
      check-exported: false

  exclusions:
    generated: lax
    presets:
      - comments
      - common-false-positives
      - legacy
      - std-error-handling
    # paths entries are Go regexes, not globs. Uncomment per repo:
    # paths:
    #   - database/sqlc
    #   - .*\.pb\.go$
    rules:
      - path: _test\.go
        linters:
          - bodyclose
          - gocyclo
          - gosec
          - noctx
          - unparam

      - path: examples/
        linters:
          - errcheck
          - gosec

      - path: config/
        linters:
          - forbidigo
        text: os\.Getenv

issues:
  max-issues-per-linter: 0
  max-same-issues: 0

formatters:
  enable:
    - gofmt
    - goimports
```

## Why each linter is on

These are not stylistic preferences; each one maps to a class of bug that has
actually shipped in Go libraries.

| Linter | Catches |
|---|---|
| `errcheck`\* | Unchecked errors — silent data loss |
| `govet`\* | Suspicious constructs the compiler allows |
| `staticcheck`\* | The broad correctness suite (absorbed both `gosimple` and `stylecheck` in v2) |
| `unused`\*, `ineffassign`\* | Dead code and assignments that go nowhere |
| `errorlint` | `err == ErrFoo` instead of `errors.Is` — breaks on wrapped errors |
| `bodyclose` | Leaked HTTP response bodies |
| `sqlclosecheck` | Leaked `sql.Rows` / statements |
| `noctx` | HTTP requests built without a context — unkillable requests |
| `nilerr` | `if err != nil { return nil }` — swallowed failures |
| `gosec` | Hardcoded credentials, weak crypto, path traversal, unsafe permissions |
| `bidichk` | Bidirectional-unicode trojan-source attacks |
| `revive` | Exported symbols without doc comments, missing package comments, naming |
| `gocritic` | Mixed receivers, needless copies, performance foot-guns |
| `predeclared` | Shadowing `len`, `cap`, `new`, … |
| `unconvert`, `unparam`, `nakedret` | Noise: redundant conversions, dead parameters, naked returns in long functions |
| `gocyclo`, `nestif` | Functions and branches that have outgrown their design |
| `nolintlint` | `//nolint` without a reason, or unused suppressions |
| `forbidigo` | `os.Getenv` outside the config layer |

\* on by default in v2 — do not list them under `enable`.

The two complexity linters are the ones people are tempted to disable
(beaver-kit has them commented out today). Don't. A function over complexity 15
is a refactor waiting to happen; if a specific one is genuinely irreducible,
exclude that function by name rather than turning the linter off for the whole
repo:

```yaml
      - linters:
          - gocyclo
        text: "GetFileExtensionForMIME.*is high"
```

## Exclusions policy

Relax rules in exactly three places, and nowhere else:

- **`_test.go`** — resource-leak and complexity checks add noise to tests
  without catching real bugs there.
- **`examples/`** — example programs elide error handling for readability.
- **Generated code** — `generated: lax`, plus a `paths:` entry for any
  generated directory. Those entries are **Go regexes, not globs**: `*.pb.go`
  is not a typo-level mistake, it aborts the run with
  `can't compile regexp "*.pb.go"`. Write `.*\.pb\.go$`.

Everything else is a `//nolint:linter // reason` at the exact line, and
`nolintlint` enforces that it names a specific linter and carries a reason.

## Running it

golangci-lint searches the working directory and then each parent for
`.golangci.yml`, so a single config at the repo root applies to every
sub-module when you `cd` into it. Multi-module repos lint per module — the tool
does not cross module boundaries:

This is filekit's `lint` target — copy it, including the hard `exit 1` when the
tool is missing. (`beaver-kit`'s is a bare `golangci-lint run` over one module
that only `echo`s when golangci-lint is absent, so it reports success without
having linted anything.)

```make
lint:
	@command -v golangci-lint >/dev/null 2>&1 || { echo "brew install golangci-lint"; exit 1; }
	@set -e; for d in $(MODULES); do \
		echo "→ lint $$d"; \
		(cd "$$d" && golangci-lint run); \
	done
```

Useful invocations:

```sh
golangci-lint run                 # current module
golangci-lint run ./krypto/...    # one package
golangci-lint fmt                 # apply the formatters
golangci-lint config verify       # validate the config itself
make lint                         # every module, in repos wired like filekit
```

## The gate

A change lands only if:

| Check | Threshold |
|---|---|
| `golangci-lint run` | 0 issues |
| `govulncheck` | 0 HIGH / CRITICAL |
| `gosec` | 0 HIGH; MEDIUM needs a reviewer's sign-off |
| `go test -race ./...` | passing in every module |

The Makefiles don't yet enforce that uniformly. In `filekit`, `make ci` runs
`deps + vet + test-race + verify-release-mods` and `make check-full` adds `lint`
and the security tools. `beaver-kit` is leaner — `ci: deps lint test-race`,
`check: lint test`, no `check-full`, and no security targets at all. Bring new
modules up to filekit's shape rather than copying beaver-kit's.

Security tooling runs through `go run`, so nobody needs it installed. `gosec` is
pinned; `govulncheck` deliberately tracks `latest`, since an advisory database
you pinned last quarter is not a vulnerability check:

```make
GOVULNCHECK_VERSION = latest
GOSEC_VERSION       = v2.21.4
```

(Both variables live in `filekit/Makefile` and `configkit/Makefile`;
`beaver-kit` has no `vuln`, `gosec`, or `sec` target yet.)
