# simtabi/db-toolkit-docker

[![Images](https://img.shields.io/badge/ghcr.io-db--toolkit-blue)](https://github.com/simtabi/db-toolkit-docker/pkgs/container/db-toolkit-pg)
[![Tests](https://github.com/simtabi/db-toolkit-docker/actions/workflows/ci.yml/badge.svg)](https://github.com/simtabi/db-toolkit-docker/actions/workflows/ci.yml)
[![Static analysis](https://github.com/simtabi/db-toolkit-docker/actions/workflows/lint.yml/badge.svg)](https://github.com/simtabi/db-toolkit-docker/actions/workflows/lint.yml)
[![License MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

> One local database toolkit for SQL and NoSQL: PostgreSQL, MySQL, MariaDB, MongoDB, Cassandra and FerretDB, each version-switchable, secure by default, with browser UIs — installed once and shared by many projects.

Runs on macOS, Windows and Linux across amd64 and arm64; dev-first, prod-capable. The registry badge is a static label rather than a version badge, because GHCR exposes no shields endpoint for a private package.

## Install

```bash
git clone https://github.com/simtabi/db-toolkit-docker.git
cd db-toolkit-docker
make init
make up
```

PostgreSQL and Adminer are running. Add engines with profiles:

```bash
make up PROFILES=pg,mysql,mongodb,ui
```

## Engines

Every engine is **authenticated by default**, which several of them are not out
of the box — correcting that is a large part of why this exists.

| Engine | Paradigm | Versions | Pooling | Licence |
|---|---|---|---|---|
| PostgreSQL | relational | 15 · 16 · 17 · 18 | pgBouncer (required in prod) | PostgreSQL |
| MySQL | relational | 8.0 · 8.4 · 9.7 | ProxySQL (optional) | GPL-2.0 |
| MariaDB | relational | 10.11 · 11.4 · 11.8 | ProxySQL (optional) | GPL-2.0 |
| MongoDB | document | 7.0 · 8.0 · 8.3 | driver-side | SSPL — [referenced, not published](docs/licensing.md) |
| Cassandra | wide-column | 4.1 · 5.0 | driver-side | Apache-2.0 |
| FerretDB | document | 2 | driver-side | Apache-2.0 |

Adding another is a descriptor file — see [Adding an engine](docs/adding-an-engine.md).

## <a name="documentation"></a>Documentation

Full documentation is hosted at
**<https://opensource.simtabi.com/documentation/simtabi/db-toolkit-docker/>**.

### Guides

- [Installation](docs/installation.md) — prerequisites and first run
- [Getting started](docs/getting-started.md) — a new project connected in under a minute
- [Configuration](docs/configuration.md) — every `DBTK_` variable
- [Architecture](docs/architecture.md) — how engines are declared rather than hardcoded
- [Adding an engine](docs/adding-an-engine.md) — the extensibility contract
- [Connection pooling](docs/pooling.md) — why the answer differs per engine
- [Licensing](docs/licensing.md) — what you are running, and under what terms
- [Operations](docs/OPERATIONS.md) — VPS, exposure, tuning, HA
- [Release](docs/release.md) — how versions ship

### Reference

- [Specification](docs/SPEC.md) — the build contract
- [Design](DESIGN.md) — pinned versions, capacity table, decision log
- [Row-level security kit](rls/README.md) — database-enforced multi-tenancy

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

MIT for this repository. Published images inherit the licence of the database
they contain — see [Licensing](docs/licensing.md). See [LICENSE](LICENSE).
