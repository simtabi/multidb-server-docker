# Acceptance

Every acceptance criterion in [SPEC](SPEC.md) section 18, mapped to the check
that proves it — and the ones nothing proves yet, named rather than omitted.

The harness is the definition of done: SPEC section 18 *is* `scripts/verify/`,
so a green `make verify` is the criteria being met rather than a proxy for it.

## Section 18

| # | Criterion | Proven by | State |
|---|---|---|---|
| 1 | Clone → `make init` → `make up` gives PG + Adminer in two commands; profiles bring the rest; Caddy serves every UI over HTTPS | `15-compose-lifecycle`, `18-ui-front-door` | Covered |
| 2 | `make init-prod` renders a prod env passing `check-env`, TLS enforced, nothing published but Caddy, ports remappable from `.env` | `26-prod-profile-guards`, `06-check-env-enforces` | Covered |
| 3 | Each engine image runs standalone with only a password env; EMBED toggles self-backup and metrics | `08-pg-standalone-run`, `16-mysql-family-boot`, `24-metrics-and-embed` | Covered |
| 4 | Version switch 16→17 uses a new volume, leaves the old intact; `make upgrade` migrates; same for MySQL 8.0→8.4 | `14-version-switch`, `29-upgrade-migrates-data` | Covered |
| 5 | MySQL and MariaDB run concurrently, phpMyAdmin sees both | `16-mysql-family-boot`, `18-ui-front-door` | Covered |
| 6a | Two projects per engine, isolated roles, cross-access denied | `13-triplet-isolation`, `28-new-project`, `34-new-project-every-engine` | Covered |
| 6b | **PG RLS demo passes** | — | **Not proven** |
| 7a | Fresh VPS path ends TLS-only, unpublished or firewalled, no UI exposed | `20-tls-enforced-prod`, `26-prod-profile-guards` | Covered |
| 7b | **Nightly S3 backups** | — | **Not implemented** |
| 7c | **PITR active for PG** | — | **Not implemented** |
| 8 | Restore drill with row-count verification; `backup-all` produces per-database dumps plus PG globals; `verify-backups` restores the latest set green | `21-backup-restore-roundtrip`, `22-backup-all-and-verify` | Covered |
| 9 | `make psql` over the shared unix socket; a sidecar mounting the socket volume connects with no TCP | `19-unix-sockets` | Covered |
| 10 | `sslmode=verify-full` against the toolkit CA succeeds; prod MySQL-family plaintext refused | `12-pg-tls`, `20-tls-enforced-prod` | Covered |
| 11a | CI matrix green | `.github/workflows/ci.yml` | Written, never run — see below |
| 11b | **trivy clean or waived with notes** | — | **Not implemented** |
| 11c | Repo and image-history grep finds no credential | `03-secret-scan-repo`, `23-image-history-secrets` | Covered |

## Sections 21 and 22

| Criterion | Proven by |
|---|---|
| Killing the Patroni leader elects a new one; the write port follows and the read port serves replicas only | `27-ha-failover` |
| etcd runs a quorum of at least three | `27-ha-failover`, `check-env` |
| No engine, of any paradigm, accepts unauthenticated connections | `32-every-engine-auth` |
| No trust or empty-password auth anywhere, including loopback | `30-no-trust-auth` |
| Every engine descriptor is complete, consistent, and honestly declared | `31-engine-descriptors` |
| The pooler multiplexes and holds no application password (PostgreSQL) | `33-pooler-works` |
| The pooler holds verifiers, not passwords (MySQL family) | `35-proxysql-verifiers` |
| Every engine family can provision a project | `34-new-project-every-engine` |

## What is not proven

Stated plainly, because a criterion quietly dropped from a report is worse than
one that is openly outstanding.

**PG RLS demo passes (6b).** The kit exists at [`rls/`](../rls/README.md) —
policies, roles, and a template — and check 01 asserts the directory is there.
Nothing runs it. Directory existence is not a passing demo, and this is the
cheapest of the four gaps to close: a check that applies the template, sets
`app.tenant_id`, and asserts one tenant cannot read another's rows.

**Nightly S3 backups (7b).** The backup sidecar writes to `DBTK_BACKUP_DIR` and
stops there. There is no destination setting and nothing ships backups off the
machine; [Operations](OPERATIONS.md) states this as a boundary rather than
implying otherwise. An operator who configures nothing else has local-only
backups, which on a server is the failure mode that matters.

**PITR active for PG (7c).** Not implemented. There is no WAL archiving, no
`archive_mode`, and no pgBackRest repository, so recovery granularity is the
last dump rather than a point in time. `make ha-reinit` rebuilds a replica from
the current leader, not from an archive.

**trivy clean or waived (11b).** No vulnerability scanning runs anywhere. For a
project publishing container images this is a real gap, not a formality.

**CI matrix green (11a).** The workflow is written and the matrix is derived
from the engine descriptors, but the repository has no remote, so GitHub
Actions has never executed it. What is verified locally: the YAML parses,
`scripts/ci-matrix` produces the twelve (engine, version) pairs, and the exact
build path succeeds for a non-default version. Calling that "green" would be a
claim about something that has not run.

## A note on running the harness

Every check has been observed green — individually or in a clean run. A single
uninterrupted full `make verify` has not completed on the development machine
used here, because Docker reclaims images partway through a ~40 minute run: one
run logged eight images present at build time and one at the end, and the
resulting failures all read "image not built yet". That is an environment
limit, not a property of the harness, and CI's runners do not share it.

---

[← Docs index](../README.md#documentation)
