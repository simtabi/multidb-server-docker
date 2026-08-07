# simtabi/db-toolkit-docker

[![Images](https://img.shields.io/badge/ghcr.io-db--toolkit-blue)](https://github.com/simtabi/db-toolkit-docker/pkgs/container/db-toolkit-pg)
[![Tests](https://github.com/simtabi/db-toolkit-docker/actions/workflows/ci.yml/badge.svg)](https://github.com/simtabi/db-toolkit-docker/actions/workflows/ci.yml)
[![Static analysis](https://github.com/simtabi/db-toolkit-docker/actions/workflows/lint.yml/badge.svg)](https://github.com/simtabi/db-toolkit-docker/actions/workflows/lint.yml)
[![License MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

> A complete local database toolkit: PostgreSQL, MySQL, and MariaDB, each version-switchable, with browser UIs, installed once and shared by many projects.

Runs on macOS, Windows, and Linux across amd64 and arm64; dev-first, prod-capable. The registry badge is a static label rather than a version badge because images publish to GHCR, which exposes no shields endpoint for a private package.

## Install

```bash
git clone https://github.com/simtabi/db-toolkit-docker.git
cd db-toolkit-docker
make init
make up
```

PostgreSQL and Adminer are running. `make up PROFILES=pg,mysql,mariadb,ui` brings the rest.

## <a name="documentation"></a>Documentation

Full documentation is hosted at
**<https://opensource.simtabi.com/documentation/simtabi/db-toolkit-docker/>**.

### Guides

- [Installation](docs/installation.md) — prerequisites and first run
- [Getting started](docs/getting-started.md) — a new project connected in under a minute
- [Configuration](docs/configuration.md) — every `DBTK_` variable
- [Architecture](docs/architecture.md) — why a stack of single-purpose containers
- [Operations](docs/OPERATIONS.md) — VPS, exposure, tuning, HA
- [Release](docs/release.md) — how versions ship

### Reference

- [Specification](docs/SPEC.md) — the build contract
- [Design](DESIGN.md) — pinned versions, capacity table, decision log

### Recipes

- [Restore](docs/RESTORE.md) — the 2am runbook
- [Upgrade](docs/UPGRADE.md) — guided major-version migration
- [Onboarding](docs/ONBOARDING.md) — migrate existing native databases in
- [Windows](docs/WINDOWS.md) — WSL2 and git-bash notes

## Community

Issues and discussions: <https://github.com/simtabi/db-toolkit-docker/issues>.

## Contributing & security

See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md).

## License

MIT. See [LICENSE](LICENSE).
