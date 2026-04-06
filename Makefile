# GoBeaver Docs — Dockerized npm targets.
#
# All targets run inside node:22-alpine so no host Node install is required.
# Override the image with `make IMAGE=node:20-alpine dev-docker` if you need
# a different version.

IMAGE       ?= node:22-alpine
PORT        ?= 4321
WORKDIR     := /work
DOCKER_RUN  := docker run --rm -v "$(CURDIR)":$(WORKDIR) -w $(WORKDIR)
DOCKER_TTY  := $(DOCKER_RUN) -it
DOCKER_PORT := $(DOCKER_TTY) -p $(PORT):$(PORT)

.PHONY: help install-docker dev-docker build-docker preview-docker check-docker shell-docker clean

help: ## Show this help.
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*##/ {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

install-docker: ## Install npm dependencies inside the container.
	$(DOCKER_RUN) $(IMAGE) npm install --no-fund --no-audit

dev-docker: ## Start the Astro dev server on http://localhost:$(PORT).
	$(DOCKER_PORT) $(IMAGE) npm run dev -- --host 0.0.0.0 --port $(PORT)

build-docker: ## Build the production site to ./dist.
	$(DOCKER_RUN) $(IMAGE) npm run build

preview-docker: ## Preview the built site on http://localhost:$(PORT).
	$(DOCKER_PORT) $(IMAGE) npm run preview -- --host 0.0.0.0 --port $(PORT)

check-docker: ## Run `astro check` (type + content validation).
	$(DOCKER_RUN) $(IMAGE) npm run astro -- check

shell-docker: ## Drop into a shell inside the container.
	$(DOCKER_TTY) $(IMAGE) sh

clean: ## Remove build output and Astro cache (keeps node_modules).
	rm -rf dist .astro
