# GoBeaver Docs

The official documentation site for GoBeaver, built with
[Astro Starlight](https://starlight.astro.build/).

> **No Node required on your host.** All commands run inside Docker against
> the `node:22-alpine` image. If you prefer a host install, the same `npm`
> commands work — just drop the `docker run` wrapper.

## Layout

```
docs/
├── astro.config.mjs       ← site config + sidebar
├── src/
│   └── content/
│       └── docs/
│           ├── index.mdx          ← landing page
│           ├── intro/             ← what is beaver, install, quickstart
│           ├── concepts/          ← modular monolith, dual-key, multi-tenancy
│           ├── configkit/         ← stable-ish
│           ├── filekit.md         ← overview
│           ├── filekit/
│           │   ├── drivers/       ← local, s3, gcs, azure, sftp, memory, zip
│           │   └── validator/     ← standalone filevalidator subpackage
│           ├── beaverkit/         ← alpha — database, krypto, oauth, …
│           ├── cli/               ← beaver CLI reference
│           ├── recipes/           ← cookbook
│           └── contributing/
└── README.md
```

## Running locally with Docker

All commands assume your shell is in this `docs/` directory. The `Makefile`
wraps each docker invocation so you don't have to remember the flags.

| Make target          | What it does                                          |
| :------------------- | :---------------------------------------------------- |
| `make help`          | List all targets                                      |
| `make install-docker`| `npm install` inside the container                    |
| `make dev-docker`    | Dev server at [http://localhost:4321](http://localhost:4321) |
| `make build-docker`  | Production build to `./dist/`                         |
| `make preview-docker`| Preview the built site                                |
| `make check-docker`  | Run `astro check` (type + content validation)         |
| `make shell-docker`  | Open a shell inside the container                     |
| `make clean`         | Remove `dist/` and `.astro/` (keeps `node_modules/`)  |

Override the Node version or port with environment variables:

```sh
make IMAGE=node:20-alpine PORT=4322 dev-docker
```

### Equivalent raw docker commands

If you'd rather not use make, the dev server target is just:

```sh
docker run --rm -it \
  -v "$PWD":/work -w /work \
  -p 4321:4321 \
  node:22-alpine \
  npm run dev -- --host 0.0.0.0 --port 4321
```

> `--host 0.0.0.0` is required so the server inside the container is
> reachable from the host. The published port `4321:4321` matches Astro's
> default.

## Notes

- The Docker image (`node:22-alpine`) is small and pre-pulled on this
  workstation; no host Node is required.
- `node_modules/` lives on the host volume, so installs persist between
  container runs.
- File ownership behaves correctly on macOS thanks to Docker Desktop's UID
  mapping. On Linux you may need `--user "$(id -u):$(id -g)"`.
