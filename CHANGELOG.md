# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-08-10

First public release.

Six database engines behind one toolkit — PostgreSQL, MySQL, MariaDB, MongoDB,
Cassandra and FerretDB — each version-switchable, authenticated by default, with
verified backups, point-in-time recovery, connection pooling and a rehearsal HA
topology. 42 acceptance checks; every claim below is one of them.

### Added

- **Six engines from one descriptor model.** An engine is a declarative
  `engine.conf` plus family hooks; adding one to an existing family costs a
  single file. Nothing branches on an engine name.
- **Authenticated by default**, which several engines are not: MongoDB ships
  with no authentication and Cassandra with `AllowAllAuthenticator` *and*
  `AllowAllAuthorizer`. Check 32 asserts every engine refuses anonymous access.
- **Point-in-time recovery** for PostgreSQL (pgBackRest) and the MySQL family
  (binary logs), proven by recovering to a moment *between* two writes.
- **Connection pooling that stores no application password** — pgBouncer
  resolves credentials with `auth_query`; ProxySQL mirrors password verifiers,
  never cleartext.
- **Verified backups**: `make verify-backups` restores the latest set into
  throwaway containers and asserts the row counts, because an unrestored backup
  is a hypothesis.
- **High availability** — Patroni, a three-node etcd quorum and HAProxy, with a
  killed leader replaced in ~20s and the write port following it.
- **Row-level security kit**, proven to isolate tenants including from the table
  owner.
- **Exposure is a decision**: `MDB_PUBLISH=none` by default, so no host port is
  bound and nothing can collide; `direct` and `proxy` publish from a single
  configurable base.
- **Supply chain**: every image official, upstream, or justified in
  `IMAGE-PROVENANCE.md`; every reference digest-pinned; trivy in CI with
  waivers that must carry a reason and a revisit condition.


- Repository scaffold per `docs/SPEC.md` section 15.
- The complete `make verify` acceptance harness, written before the features it
  checks so every subsequent phase has something to heal against.
- `DESIGN.md`: pinned versions with digests, the arm64 extension matrix, the
  capacity truth table, and the decision log.
- `docs/SPEC.md` section 21 (scale, HA, sync) as an approved amendment.
- `scripts/check-env`, enforcing sentinel rejection, the `_FILE` convention,
  supported version menus, port-collision detection, and the prod guards
  (mandatory pooling, UI basic auth, 3-node etcd quorum).
- CI workflows for static analysis and the amd64/arm64 verify matrix.

- `multidb-server-pg`: PostgreSQL 15–18 with the full extension suite (vector,
  PostGIS, pg_cron, pgaudit, pg_repack, pg_partman, pgtap, http, hypopg,
  pg_graphql, pg_net, pgsodium, pgjwt), supervised by s6-overlay v3.
- Ordered s6 init: permissions, configuration, certificates, provisioning, then
  the engine — wrapping the official entrypoint rather than replacing it.
- Multi-project triplet provisioning with cross-project access denied.
- `make init`, `certs`, `build`, `up`, `down`, `status`, `logs`, `psql`.
- `docker-compose.yml` with the `pg` and `ui` profiles and per-major volumes.
- `multidb-server-mysql` (8.0/8.4/9.7) and `multidb-server-mariadb` (10.11/11.4/11.8),
  both s6-supervised with baked utf8mb4 / `utf8mb4_unicode_ci` / explicit
  `sql_mode`, triplet provisioning, and the same tool suite.
- phpMyAdmin serving both MySQL-family servers from one instance via
  `PMA_HOSTS`, and `make mysql` / `make mariadb` client shells.

### Fixed

- All shell is bash 3.2 compatible, so the toolkit runs on stock macOS
  (see `DESIGN.md` D-24).
- PostgreSQL now shuts down cleanly under s6 via a per-service `down-signal`,
  so the next boot performs no crash recovery (D-09, D-27).
- `pg_graphql`'s packaged symlinks are flattened, which also protects against
  the PG 18 volume mount shadowing them (D-26).

[Unreleased]: https://github.com/simtabi/multidb-server-docker/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/simtabi/multidb-server-docker/releases/tag/v0.1.0
