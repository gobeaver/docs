# GoBeaver Docs — Dockerized npm targets.
#
# All targets run inside a node:22-alpine + git image (see Dockerfile), so no
# host Node install is required. The image is built on first use.

IMAGE       ?= gobeaver-docs-node
PORT        ?= 4321
WORKDIR     := /work
DOCKER_RUN  := docker run --rm -e GITHUB_TOKEN -v "$(CURDIR)":$(WORKDIR) -w $(WORKDIR)
DOCKER_TTY  := $(DOCKER_RUN) -it
DOCKER_PORT := $(DOCKER_TTY) -p $(PORT):$(PORT)

.PHONY: help image install-docker dev-docker build-docker preview-docker check-docker shell-docker clean

help: ## Show this help.
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*##/ {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

image: ## Build the Node + git image used by every target.
	docker build -q -t $(IMAGE) . >/dev/null

install-docker: image ## Install npm dependencies inside the container.
	$(DOCKER_RUN) $(IMAGE) npm install --no-fund --no-audit

dev-docker: image ## Start the Astro dev server on http://localhost:$(PORT).
	$(DOCKER_PORT) $(IMAGE) npm run dev -- --host 0.0.0.0 --port $(PORT)

build-docker: image ## Build the production site to ./dist.
	$(DOCKER_RUN) $(IMAGE) npm run build

preview-docker: image ## Preview the built site on http://localhost:$(PORT).
	$(DOCKER_PORT) $(IMAGE) npm run preview -- --host 0.0.0.0 --port $(PORT)

check-docker: image ## Run `astro check` (type + content validation).
	$(DOCKER_RUN) $(IMAGE) npm run astro -- check

shell-docker: image ## Drop into a shell inside the container.
	$(DOCKER_TTY) $(IMAGE) sh

clean: ## Remove build output and Astro cache (keeps node_modules).
	rm -rf dist .astro
