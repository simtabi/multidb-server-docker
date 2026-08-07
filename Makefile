# db-toolkit — the single entry point for humans and CI.
#
# Targets marked "phase N" are scaffolded but not implemented yet. They fail
# loudly rather than succeeding silently, so `make verify` stays honestly red
# until the feature behind them exists.

SHELL := bash
.SHELLFLAGS := -euo pipefail -c
.DEFAULT_GOAL := help

COMPOSE_PROJECT_NAME ?= dbtk
export COMPOSE_PROJECT_NAME

ENV_FILE ?= .env
COMPOSE  := docker compose

# Profile selection, in precedence order: PROFILES= on the command line for a
# single run, then DBTK_PROFILES in .env permanently, then the documented
# default (SPEC section 7).
env_profiles := $(shell grep -E '^DBTK_PROFILES=' $(ENV_FILE) 2>/dev/null | tail -1 | cut -d= -f2-)
COMPOSE_PROFILES := $(or $(PROFILES),$(env_profiles),pg,ui)
export COMPOSE_PROFILES

# down, status, and logs must see every service regardless of the selected
# profiles, or a running container from another profile becomes invisible and
# un-stoppable through the Makefile.
all_profiles := --profile '*'

# Emit a consistent "not implemented" failure. $(1) is the owning phase.
define unimplemented
	@printf '\033[33m✗ %s\033[0m is scaffolded but not implemented yet (phase %s).\n' "$@" "$(1)" >&2; \
	printf '  See docs/KIT.md section 5 for what that phase delivers.\n' >&2; \
	exit 1
endef

.PHONY: help
help: ## Show this help
	@printf 'db-toolkit — make targets\n\n'
	@grep -hE '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'
	@printf '\nProfiles: make up PROFILES=pg,mysql,ui\n'

# -----------------------------------------------------------------------------
# Setup
# -----------------------------------------------------------------------------

.PHONY: init
init: ## Create .env, generate secrets and certs, run check-env
	@scripts/init

.PHONY: init-prod
init-prod: ## Render .env.prod with prod-safe values
	$(call unimplemented,4)

.PHONY: check-env
check-env: ## Validate env: sentinels, required vars, port collisions
	@scripts/check-env

.PHONY: certs
certs: ## Create the toolkit CA and per-engine server certificates
	@scripts/certs

.PHONY: build
build: ## Build every engine image for this architecture
	@scripts/build

.PHONY: certs-renew
certs-renew: ## Rotate server certs with live reload (no downtime)
	$(call unimplemented,4)

.PHONY: rotate-secrets
rotate-secrets: ## Rotate every database password and secret file, applied live
	$(call unimplemented,4)

# -----------------------------------------------------------------------------
# Lifecycle
# -----------------------------------------------------------------------------

.PHONY: up
up: ## Boot the stack (never touches data)
	@scripts/check-env --quiet
	@$(COMPOSE) up -d --wait

.PHONY: down
down: ## Stop the stack (never touches data)
	@# No -v, ever. Removing volumes is `make destroy`, which demands a typed
	@# confirmation naming the volume (SPEC section 15).
	@$(COMPOSE) $(all_profiles) down --remove-orphans

.PHONY: status
status: ## Show service status
	@$(COMPOSE) $(all_profiles) ps

.PHONY: logs
logs: ## Tail service logs
	@$(COMPOSE) $(all_profiles) logs -f --tail=100

.PHONY: destroy
destroy: ## Delete data volumes (typed confirmation required)
	$(call unimplemented,5)

.PHONY: test-profile
test-profile: ## Boot the tmpfs speed profile and run its checks
	$(call unimplemented,4)

# -----------------------------------------------------------------------------
# Clients and provisioning
# -----------------------------------------------------------------------------

.PHONY: psql
psql: ## PostgreSQL shell (socket-first)
	@# Socket-first: faster than TCP and it removes a network surface entirely
	@# (SPEC section 10.1).
	@$(COMPOSE) exec pg psql -h /var/run/postgresql -U $(or $(USER_NAME),postgres)

.PHONY: mysql
mysql: ## MySQL shell (socket-first)
	@$(COMPOSE) exec mysql mysql --protocol=socket -uroot \
		-p"$$(cat secrets/mysql_root_password.txt)"

.PHONY: mariadb
mariadb: ## MariaDB shell (socket-first)
	@$(COMPOSE) exec mariadb mariadb --protocol=socket -uroot \
		-p"$$(cat secrets/mariadb_root_password.txt)"

.PHONY: shell
shell: ## Open the cli image
	$(call unimplemented,5)

.PHONY: new-project
new-project: ## Provision DB + roles + extensions, print the Laravel .env block
	$(call unimplemented,5)

# -----------------------------------------------------------------------------
# Backup and restore
# -----------------------------------------------------------------------------

.PHONY: backup
backup: ## Dump one database
	$(call unimplemented,4)

.PHONY: backup-all
backup-all: ## Dump every database on every enabled engine, plus PG globals
	$(call unimplemented,4)

.PHONY: restore
restore: ## Guided, confirmed restore (ENGINE= DB= FILE=)
	$(call unimplemented,4)

.PHONY: verify-backups
verify-backups: ## Restore the latest set into throwaway containers, assert row counts
	$(call unimplemented,4)

.PHONY: import
import: ## Move data in (files, existing native databases)
	$(call unimplemented,5)

.PHONY: export
export: ## Move data out
	$(call unimplemented,5)

.PHONY: upgrade
upgrade: ## Guided major-version migration (ENGINE= FROM= TO=)
	$(call unimplemented,5)

# -----------------------------------------------------------------------------
# Scale and HA (SPEC section 21)
# -----------------------------------------------------------------------------

.PHONY: ha-status
ha-status: ## Show cluster topology and replication lag
	$(call unimplemented,7)

.PHONY: ha-failover
ha-failover: ## Controlled switchover (typed confirmation required)
	$(call unimplemented,7)

.PHONY: ha-reinit
ha-reinit: ## Rebuild a replica from the pgBackRest repo (NODE=)
	$(call unimplemented,7)

# -----------------------------------------------------------------------------
# Verification — real from phase 1, because everything heals against it
# -----------------------------------------------------------------------------

.PHONY: verify
verify: ## Full acceptance harness (SPEC section 18 as scripts)
	@scripts/verify/run.sh

.PHONY: verify-fast
verify-fast: ## Inner-loop subset of the harness
	@VERIFY_TAGS=fast scripts/verify/run.sh

.PHONY: verify-structure
verify-structure: ## Harness self-test: every check is well-formed and runnable
	@scripts/verify/run.sh --structure-only

.PHONY: lint
lint: ## shellcheck every script in the repository
	@scripts/lint.sh

.PHONY: self-update
self-update: ## Update the toolkit itself, never project data
	$(call unimplemented,5)
