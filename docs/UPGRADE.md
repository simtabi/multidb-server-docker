# Upgrade

Moving a database to a new major version, without a window where losing the old
copy is possible.

## The guarantee this rests on

**Volumes are per engine and per major version.** PostgreSQL 16's data lives in
one volume, 17's in another, and an upgrade writes only to the new one.

The consequence is the useful part: **the old volume is never touched**, so a
failed upgrade is a non-event and rollback is changing one line in `.env` back.
You are not racing a backup.

## Upgrade

```bash
make backup-all
make upgrade ENGINE=pg FROM=16 TO=17
```

Take the backup anyway. The volume guarantee protects you from the upgrade; it
does not protect you from discovering a week later that something was already
wrong.

`make upgrade` does the dump-and-restore path:

1. starts the old major against its existing volume, read-only work only
2. dumps every database and, for PostgreSQL, the globals
3. starts the new major against a fresh volume
4. restores
5. compares object and row counts, and **fails loudly if they disagree**
6. tells you to set `MMDB_PG_VERSION=17` — it does not edit `.env` for you

Step 6 is deliberate. The upgrade proving it worked and you deciding to switch
are two different decisions, and collapsing them means a surprise the next time
anyone runs `make up`.

## Then switch

```
MMDB_PG_VERSION=17
```

```bash
make up
make psql -c '\l'
```

## Rolling back

```
MMDB_PG_VERSION=16
```

```bash
make up
```

That is the whole procedure. The 16 volume was never written to.

## Why dump-and-restore rather than pg_upgrade --link

`pg_upgrade --link` is dramatically faster on large datasets — it hard-links
files instead of copying them — and it is not what `make upgrade` runs.

The reason is that `--link` **mutates the source data directory**. After it runs,
the old cluster is no longer safely startable, which trades away the exact
property that makes this whole procedure calm. On a development machine, and on
most production databases under a few hundred gigabytes, dump-and-restore is
minutes and the guarantee is worth more than the minutes.

If your dataset is large enough that this matters, run it by hand, from a
verified backup, having read the PostgreSQL documentation for your version pair,
and expect to need `--check` first. It is not automated here because automating
it would mean shipping a fast path whose failure mode is losing the source.

## MySQL and MariaDB

Same command, same guarantee:

```bash
make upgrade ENGINE=mysql FROM=8.0 TO=8.4
```

Two version-specific traps, both of which bite after the upgrade rather than
during it:

**MySQL 8.4 removed `mysql_native_password`.** Clients too old to speak
`caching_sha2_password` stop connecting. `MMDB_MYSQL_NATIVE_PASSWORD_COMPAT=true`
re-enables it as a transition, not a destination.

**MariaDB and MySQL have diverged** far enough that they are not interchangeable
targets. Upgrade MariaDB to MariaDB. Moving between them is a migration, and the
tool for it is `make export` / `make import`.

## MongoDB, Cassandra, FerretDB

```bash
make upgrade ENGINE=mongodb FROM=7.0 TO=8.0
```

**MongoDB does not support skipping major versions.** 6.0 → 8.0 must go through
7.0. Upgrading in place past a skipped major produces a server that will not
start against the data files.

Also note `MMDB_MONGODB_VERSION=7.0` is the default for a reason: 8.x crash-loops
on Linux kernel 6.19 and later (SERVER-121912), which includes current Docker
Desktop VMs. Verify 8.x starts on your machine before you migrate to it.

**Cassandra** upgrades want `nodetool drain` before shutdown and an
`upgradesstables` afterwards. On a single-node development cluster
`make upgrade` handles this; on a real cluster, follow the Cassandra
documentation — a rolling upgrade is not a thing this toolkit can do for you.

## Cleaning up the old volume

Only once the new version has been running long enough that you would have
noticed a problem. There is no hurry, and the disk is cheaper than the regret.

```bash
docker volume ls | grep mmdb
docker volume rm mmdb_pg16_data
```

---

[← Docs index](../README.md#documentation)
