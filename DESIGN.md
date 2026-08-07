# db-toolkit design

Step 1 output: research resolved, versions pinned, spec reconciled. **No implementation code exists yet and none will be written until this document is approved.**

Everything below was verified during this session against live registries, the GitHub API, and — where prose was ambiguous or absent — against containers actually booted on arm64. Where a claim came from a doc page rather than an executed check, it says so.

## 1. Settled identity

| Field | Value |
|---|---|
| Repository | `github.com/simtabi/db-toolkit-docker` |
| Images | `ghcr.io/simtabi/db-toolkit-{pg,mysql,mariadb,cli}` |
| Docs | `https://opensource.simtabi.com/documentation/simtabi/db-toolkit-docker/` |
| Product page | `https://opensource.simtabi.com/products/simtabi/db-toolkit-docker` |
| Env prefix | `DBTK_` |
| Compose project | `dbtk` |
| Registry visibility | private until explicitly flipped public (section 19 default) |

Resolves the three-way conflict recorded in decision **D-02**.

## 2. Final service map

| Service | Image | Profile | Internal port | Host port env | Published by default |
|---|---|---|---|---|---|
| `pg` | `ghcr.io/simtabi/db-toolkit-pg:<ver>` | `pg` | 5432 | `DBTK_PG_HOST_PORT` | no |
| `mysql` | `ghcr.io/simtabi/db-toolkit-mysql:<ver>` | `mysql` | 3306 | `DBTK_MYSQL_HOST_PORT` | no |
| `mariadb` | `ghcr.io/simtabi/db-toolkit-mariadb:<ver>` | `mariadb` | 3306 | `DBTK_MARIADB_HOST_PORT` (3307) | no |
| `adminer` | `adminer:5.4.1` | `ui` | 8080 | `DBTK_ADMINER_HOST_PORT` | no (via Caddy) |
| `phpmyadmin` | `phpmyadmin:5.2.3` | `ui` | 80 | `DBTK_PMA_HOST_PORT` | no (via Caddy) |
| `pgadmin` | `dpage/pgadmin4:9.9` | `ui` | 80 | `DBTK_PGADMIN_HOST_PORT` | no (via Caddy) |
| `caddy` | `caddy:2.10.2` | `ui`, `prod` | 80/443 | `DBTK_CADDY_HTTP_PORT` / `_HTTPS_PORT` | yes (the only web surface) |
| `backup` | `nfrastack/db-backup:4.9.0` | `backup` | — | — | no |
| `pgbackrest` | built into `db-toolkit-pg` | `prod`, `ha` | — | — | no |
| `pg-exporter` | `quay.io/prometheuscommunity/postgres-exporter:v0.19.0` | `metrics` | 9187 | — | no |
| `mysqld-exporter` | `prom/mysqld-exporter:v0.18.0` | `metrics` | 9104 | — | no |
| `pgbouncer` | `edoburu/pgbouncer:v1.25.2-p0` | `prod` (required), `ha` | 6432 | `DBTK_PGBOUNCER_HOST_PORT` | no |
| `etcd` | `gcr.io/etcd-development/etcd:v3.6.6` | `ha` | 2379/2380 | — | no |
| `haproxy` | `haproxy:3.2-alpine` | `ha` | 5432 w / 5433 r | `DBTK_HAPROXY_*_PORT` | no |
| `cli` | `ghcr.io/simtabi/db-toolkit-cli:<ver>` | on demand | — | — | no |

Profiles: engine selectors `pg` / `mysql` / `mariadb`; mode overlays `ui` / `backup` / `metrics` / `prod` / `test` / `ha`. Default `COMPOSE_PROFILES=pg,ui`.

## 3. Pinned versions

All digests resolved from the live registry this session. **Every image below is confirmed `linux/amd64` + `linux/arm64`.**

| Component | Pin | Digest | Source |
|---|---|---|---|
| pgvector PG15 | `0.8.6-pg15` | `sha256:a20a57d7aa5217a6af0a391ccf69f4a8512406d6c14be08132f801468cc3cc62` | [pgvector](https://hub.docker.com/r/pgvector/pgvector) |
| pgvector PG16 | `0.8.6-pg16` | `sha256:a36250871de0833b8757561c72f2477ef1ddd1101afa4e617fb552e0de514c6b` | ibid |
| pgvector PG17 | `0.8.6-pg17` | `sha256:7ae6051efd0e60444282c27c7e141af07f322ce033300e727a49c3dd11075e38` | ibid |
| pgvector PG18 | `0.8.6-pg18` | `sha256:691673308c99d2161ba298736f3147f1f22d79de2fb7ec93ae9b4afcab870b62` | ibid |
| MySQL 8.0 | `8.0.44` | `sha256:9c3380eac945af0736031b200027f581925927c81e010056214a4bd6b6693714` | [mysql](https://hub.docker.com/_/mysql) |
| MySQL 8.4 LTS | `8.4.11` | `sha256:b3b90af2a6552ae30c266fdb7d5dd55f3afb72404bb78d37fe8a23eb857fd3fb` | ibid |
| MySQL 9 innovation | `9.7.2` | `sha256:257388edf9c84dbc04c763625446d5f3fa6ed60d1b0873bc552c614ba0a7ab4e` | ibid |
| MariaDB 10.11 LTS | `10.11.18` | `sha256:de61fed4a40d3842f3ee09944ba52792156cfd9adf489b2cc670fc6ded28df8d` | [mariadb](https://hub.docker.com/_/mariadb) |
| MariaDB 11.4 LTS | `11.4.12` | `sha256:67873d30a17f6a9c331f06363b2fa15f38abca415529966d67c84f87f82439fe` | ibid |
| MariaDB 11.8 LTS | `11.8.8` | `sha256:d9f7eb2637296652f24b484afd5d246f759f49f5babcadc6a9e344c9acb75fbf` | ibid |
| Adminer | `5.4.1` | `sha256:a3167350c4eb9ae4473b8ea0f49c8e5ae74c87b240ee2f6086521dba2a6bf243` | [adminer](https://hub.docker.com/_/adminer) |
| phpMyAdmin | `5.2.3` | `sha256:5e2289bcd500868ed4ac9261ddd7cbcc6e20036f83031ade72667b15dca31c60` | [phpmyadmin](https://hub.docker.com/_/phpmyadmin) |
| pgAdmin | `9.9` | `sha256:5d9624a93634d1c5e595619cc57b1d330758120d1baf445fa97300c0c1fc3c0a` | [pgadmin4](https://www.pgadmin.org/docs/pgadmin4/latest/container_deployment.html) |
| Caddy | `2.10.2` | `sha256:c3d7ee5d2b11f9dc54f947f68a734c84e9c9666c92c88a7f30b9cba5da182adb` | [caddy](https://caddyserver.com/docs/) |
| pgBouncer | `edoburu/pgbouncer:v1.25.2-p0` | `sha256:7d7a27d9e90985cab5cf42256f5c13a3120baa4b055b69df37beb272b89b2340` | see **D-10** |
| postgres_exporter | `v0.19.0` | `sha256:e8a170b85eab07c75c2b0f3aa2806be5c2fe5bba46fd0336914e1f36572cde08` | prometheus-community |
| mysqld_exporter | `v0.18.0` | `sha256:2598c0571f383708e19016d119bb45c06128a9ebc962c9f49483278ac5a94c41` | prometheus |
| db-backup | `nfrastack/db-backup:4.9.0` | `sha256:80d3bc0524611d85fd82738b228f88a92077ad2d0a36ae32237d6a25a93e2439` | see **D-03** |
| etcd | `v3.6.6` | `sha256:60a30b5d81b2217555e2cfb9537f655b7ba97220b99c39ee2e162a7127225890` | etcd-development |
| s6-overlay | `v3.2.3.2` (2026-07-16) | release assets `s6-overlay-{noarch,x86_64,aarch64}.tar.xz` | [s6-overlay](https://github.com/just-containers/s6-overlay) |
| Patroni | `4.1.4` (pip) | no image published — see **D-11** | [patroni](https://github.com/patroni/patroni) |
| pgBackRest | `2.59.0` | PGDG apt package | [pgbackrest](https://pgbackrest.org) |

Base distro note: the unsuffixed `pgvector/pgvector:0.8.6-pgNN` tags are **Debian 12 bookworm** (verified: `PG 17.10 (Debian 17.10-1.pgdg12+1)`). `-trixie` variants exist; see **D-16**.

## 4. PG extension matrix — arm64 ground truth

Verified by booting `pgvector/pgvector:0.8.6-pg17` **on arm64** and querying PGDG apt directly, not by reading availability pages.

| Extension | arm64 source | Version | Status |
|---|---|---|---|
| vector | PGDG `postgresql-17-pgvector` | 0.8.6 | apt |
| postgis (+topology, raster) | PGDG `postgresql-17-postgis-3` | 3.6.4 | apt |
| pg_cron | PGDG `postgresql-17-cron` | 1.6.7 | apt |
| pgaudit | PGDG `postgresql-17-pgaudit` | 17.1 | apt |
| pg_repack | PGDG `postgresql-17-repack` | 1.5.3 | apt |
| pg_partman | PGDG `postgresql-17-partman` | 5.5.0 | apt — **spec's arm64 concern was misplaced** |
| pgtap | PGDG `postgresql-17-pgtap` | 1.3.4 | apt |
| http | PGDG `postgresql-17-http` | 1.7.2 | apt — **also fine on arm64** |
| hypopg | PGDG `postgresql-17-hypopg` | 1.4.3 | apt (bonus) |
| plpython3u | PGDG `postgresql-plpython3-17` | 17.10 | apt, behind `DBTK_PG_PLPYTHON` |
| pg_stat_statements, pg_trgm, uuid-ossp, pgcrypto, citext, hstore | base image contrib | — | already present |
| **pg_graphql** | official `.deb`, **pg14–18 × amd64+arm64** | 1.6.1 | download release asset |
| **pg_net** | source build (C + libcurl) | 0.20.5 | builder stage |
| **pgsodium** | source build (C + libsodium) | 3.1.11 | builder stage |
| **pgjwt** | vendored SQL (pure plpgsql) | unversioned | see **D-06** |

**There is no extension in section 5 that cannot ship on arm64.** The honest answer to the named unknown is that the gap does not exist; four extensions simply need a non-apt path, and all four are architecture-portable. `pg_graphql` — the one most likely to have been a real problem, being Rust/pgrx — publishes prebuilt arm64 `.deb`s covering our entire 15–18 matrix.

## 5. Capacity truth table

Reproduced from SPEC.md section 21.1 as the sizing contract:

| Tier | DBTK_MEM | shared_buffers | max_connections | RAM on connections | pgBouncer pool | App connections |
|---|---|---|---|---|---|---|
| dev-small | 2 GB | 512 MB | 100 | ~1.0 GB | direct | 100 |
| prod-small | 4 GB | 1 GB | 100 | ~1.0 GB | 25 | ~1000 |
| prod-medium | 8 GB | 2 GB | 200 | ~2.0 GB | 50 | ~2500 |
| prod-large | 16 GB | 4 GB | 300 | ~3.0 GB | 100 | ~5000 |
| anti-pattern | any | any | 500 direct | ~5.0 GB idle | none | thrashing |

~10 MB per direct PG connection. Pooling is **required** under `prod`, enforced by `check-env`.

## 6. Environment variable reference

### Core
| Variable | Default | Description | Profile |
|---|---|---|---|
| `COMPOSE_PROJECT_NAME` | `dbtk` | Stable container/network/volume names | all |
| `DBTK_PROFILES` | `pg,ui` | Persistent profile selection | all |
| `DBTK_TZ` | `UTC` | Timezone baked into every engine | all |
| `DBTK_BIND_ADDR` | `127.0.0.1` | Host bind address for every published port | all |
| `DBTK_MEM` | `4` | Memory budget (GB) driving PGTune-style presets | all |
| `DBTK_CPUS` | `2` | CPU budget driving tuning presets | all |
| `DBTK_STOP_GRACE` | `60s` | `stop_grace_period`; Docker's 10s kills mid-checkpoint | all |
| `DBTK_SOCKETS` | `false` | Share a unix socket volume across containers | all |
| `DBTK_NETWORK_SUBNET` | `172.28.0.0/16` | Internal network subnet | all |
| `DBTK_LOG_MAX_SIZE` / `_MAX_FILE` | `10m` / `3` | json-file rotation caps | all |

### PostgreSQL
| Variable | Default | Description | Profile |
|---|---|---|---|
| `DBTK_PG_VERSION` | `17` | Selects image tag **and** data volume name | `pg` |
| `DBTK_PG_HOST_PORT` | unset | Publish 5432 when set | `pg` |
| `DBTK_PG_DATABASES` | unset | `db:user:__FILE__` triplets, comma-separated | `pg` |
| `DBTK_PG_INIT_EXTENSIONS` | `vector,pg_stat_statements` | Per-database `CREATE EXTENSION` at provision | `pg` |
| `DBTK_PG_SHARED_PRELOAD` | `pg_stat_statements` | Assembled into `shared_preload_libraries` | `pg` |
| `DBTK_PG_SHM` | `256m` | `shm_size`; must be ≥ `maintenance_work_mem` for parallel HNSW | `pg` |
| `DBTK_PG_PLPYTHON` | `false` | Enable untrusted plpython3u (superuser only) | `pg` |
| `DBTK_PG_SLOW_MS` | `500` dev / `0` prod | `log_min_duration_statement` | `pg` |
| `DBTK_PG_EMBED_EXPORTER` | `false` | Run exporter under s6 inside the engine container | standalone |
| `DBTK_PG_EMBED_BACKUP` | `false` | Run scheduled dumps under s6 inside the container | standalone |
| `DBTK_PG_SYNC_MODE` | `off` | Synchronous commit for zero-data-loss replication | `ha` |

### MySQL / MariaDB
| Variable | Default | Description | Profile |
|---|---|---|---|
| `DBTK_MYSQL_VERSION` | `8.4` | Image tag + volume name | `mysql` |
| `DBTK_MARIADB_VERSION` | `11.4` | Image tag + volume name | `mariadb` |
| `DBTK_MYSQL_HOST_PORT` | unset | Publish 3306 when set | `mysql` |
| `DBTK_MARIADB_HOST_PORT` | unset | Publish 3307 when set | `mariadb` |
| `DBTK_MYSQL_DATABASES` / `DBTK_MARIADB_DATABASES` | unset | Same triplet contract as PG | resp. |
| `DBTK_MYSQL_NATIVE_PASSWORD_COMPAT` | `false` | Re-enable `mysql_native_password` (8.4 dropped it) | `mysql` |
| `DBTK_MYSQL_SLOW_SECONDS` / `DBTK_MARIADB_SLOW_SECONDS` | `1` dev / off prod | Slow query log threshold | resp. |
| `DBTK_MYSQL_NOFILE` / `DBTK_MARIADB_NOFILE` | `10240` | nofile ulimit | resp. |

### TLS and secrets
| Variable | Default | Description | Profile |
|---|---|---|---|
| `DBTK_TLS_ENFORCE` | `false` dev / `true` prod | `require_secure_transport` + hostssl-only pg_hba | all |
| `DBTK_EXTRA_SANS` | unset | Extra SANs on generated server certs | all |
| `DBTK_MTLS` | `false` | Client certificate enforcement | all |
| `DBTK_CERT_DAYS` | `825` | Server certificate lifetime | all |
| `DBTK_*_PASSWORD_FILE` | `secrets/*.txt` | `_FILE` convention; never a plain value | all |

### Backup
| Variable | Default | Description | Profile |
|---|---|---|---|
| `DBTK_BACKUP_SCHEDULE` | `0300` | Nightly start (HHMM) | `backup` |
| `DBTK_BACKUP_COMPRESSION` | `ZSTD` | Maps to `DBnn_COMPRESSION` | `backup` |
| `DBTK_BACKUP_ENCRYPT` | `false` dev / `true` prod | Maps to `DBnn_ENCRYPT` | `backup` |
| `DBTK_BACKUP_RETAIN_DAILY/WEEKLY/MONTHLY` | `7` / `4` / `6` | GFS retention tiers | `backup` |
| `DBTK_S3_*` (`BUCKET`, `KEY_ID`, `KEY_SECRET`, `REGION`, `HOST`) | unset | S3-compatible target; wiring present, disabled until set | `backup` |
| `DBTK_BACKUP_NOTIFY_URL` | unset | Failure webhook so backups never fail silently | `backup` |

### UI, proxy, HA
| Variable | Default | Description | Profile |
|---|---|---|---|
| `DBTK_CADDY_HTTP_PORT` / `_HTTPS_PORT` | `80` / `443` | Caddy published ports | `ui`, `prod` |
| `DBTK_UI_DOMAIN` | `db.localhost` | Hostname suffix for UI routes | `ui` |
| `DBTK_UI_BASIC_AUTH_USER` / `_HASH` | unset / unset | Required under `prod` | `prod` |
| `DBTK_PGADMIN_EMAIL` / `_PASSWORD_FILE` | — | pgAdmin login | `ui` |
| `DBTK_PGBOUNCER_POOL_MODE` | `transaction` | Pool mode | `prod`, `ha` |
| `DBTK_PGBOUNCER_DEFAULT_POOL_SIZE` | from tier | Per capacity table | `prod`, `ha` |
| `DBTK_HA_ENABLE` | `false` | Master HA switch | `ha` |
| `DBTK_HA_CLUSTER_NAME` | `dbtk-pg` | Patroni scope | `ha` |
| `DBTK_HA_NODE_NAME` | hostname | Patroni node identity | `ha` |
| `DBTK_HA_ETCD_HOSTS` | `etcd1:2379,...` | etcd endpoints (3-node quorum) | `ha` |
| `DBTK_HAPROXY_WRITE_PORT` / `_READ_PORT` | `5432` / `5433` | Leader / replica routing | `ha` |
| `DBTK_HA_FAILOVER_BUDGET` | `30` | Seconds allowed for election in the CI assertion | `ha` |

## 7. Decision log

Every spec issue found, and how it was resolved. Entries marked **[needs your call]** are the ones worth your attention.

**D-01 — SPEC.md had no section 21.** The kickoff prompt required reconciling "section 21 (scale, HA, sync)" and producing its capacity truth table; the design doc ended at section 20. *Resolution:* authored section 21 from the verified HA research baseline and appended it to SPEC.md as an approved amendment (you approved this before I wrote it). Its requirements are folded into services, env, commands, CI, and acceptance above.

**D-02 — Three-way identity conflict.** SPEC line 5 says "repo laranail/db-toolkit"; section 16 publishes to `ghcr.io/simtabi/`; the actual checkout is `simtabi/db-toolkit-docker`. *Resolution:* `simtabi/db-toolkit-docker` + `ghcr.io/simtabi/*`, per your call.

**D-03 — The backup sidecar moved namespace and the spec's reference is stale.** `tiredofit/docker-db-backup` is now published as **`nfrastack/db-backup`**. `tiredofit/db-backup` last published `4.1.100` on 2026-03-13; `nfrastack/db-backup` is at `4.9.0` (2026-07-30). *Resolution:* pin `nfrastack/db-backup:4.9.0` by digest; SPEC references updated in docs during phase 4.

**D-04 — [needs your call] The free tier caps backup jobs at 3, which is exactly our engine count.** The project moved to a sponsorware model: "*To unlock advanced features, one must provide a code…*" and "*A limit of 3 can be created when not in advanced mode.*" I verified by parsing every table in the README that **no environment variable is actually `Adv.`-gated** — S3, encryption, checksums, `EXTRA_BACKUP_OPTS` and `BACKUP_GLOBALS` are all free. The only real constraint is the **3-job ceiling**, and pg + mysql + mariadb is exactly 3, leaving zero headroom for a fourth job (a second PG major during a migration window, or an HA replica). *Resolution offered, your pick:*
  - **(a) Recommended — write our own sidecar.** SPEC section 11 already mandates "one dump helper, two callers", and section 6.1 already bakes `rclone` and `zstd` into every engine image. A thin cron container on `db-toolkit-cli` driving that same script removes a third-party dependency, the sponsorware risk, and the job ceiling, at the cost of writing retention/notification logic ourselves (~150 lines).
  - **(b) Keep `nfrastack/db-backup:4.9.0`** and accept a hard 3-job ceiling, documenting that a 4th engine or migration-window job requires a sponsor code.
  I will implement (a) unless you say otherwise, and either way the shared dump helper is the single source of dump flags.

**D-05 — Floating tags on the backup image are currently arm64-only.** `nfrastack/db-backup:latest` and `:alpine_3.24` publish **only** `linux/arm64` right now; the versioned `4.9.0` and `4.9.0-alpine_3.24` are correctly amd64+arm64. An amd64 CI runner pulling `latest` would fail outright. *Resolution:* no change needed — CLAUDE.md's "pinned digests everywhere, no `latest`" rule already prevents this. Recorded because it is a live demonstration that the rule earns its keep.

**D-06 — [needs your call] pgjwt is unmaintained.** `michelp/pgjwt` has **no releases at all** and its last push was **2023-03-02**, over three years ago. It is not in PGDG. It is ~50 lines of plpgsql over `pgcrypto`. *Resolution offered:* vendor the SQL into `images/pg/initdb.d/` pinned to a specific commit, documented as vendored-and-frozen; or drop it from the default suite. I lean **vendor**, because it is trivial, arch-independent, and dropping it silently changes the spec's promised extension list. Say the word if you would rather drop it.

**D-07 — Four extensions are not in PGDG; none is an arm64 blocker.** `pg_graphql`, `pg_net`, `pgsodium`, `pgjwt`. *Resolution:* `pg_graphql` 1.6.1 publishes official prebuilt `.deb`s for **pg14–18 on both amd64 and arm64** — download, no build. `pg_net` 0.20.5 and `pgsodium` 3.1.11 build from source in a builder stage (both C, both portable). `pgjwt` per D-06.

**D-08 — The spec's arm64 worry was aimed at the wrong extensions.** It named `http` and `pg_partman` as at-risk. Both are in PGDG for arm64 (`1.7.2` and `5.5.0`, verified on a booted arm64 container). No workaround needed.

**D-09 — PostgreSQL will shut down uncleanly under s6 unless we override the stop signal.** The official postgres image sets `STOPSIGNAL SIGINT` (fast shutdown). s6 sends **SIGTERM**, which PostgreSQL interprets as *smart* shutdown — it waits for every client to disconnect voluntarily, so it hangs until `S6_KILL_GRACETIME` expires and then takes SIGKILL, forcing crash recovery on the next boot. This is silent: the container appears to stop normally. *Resolution:* the PG s6 service directory gets a **`down-signal`** file containing `SIGINT` (confirmed supported in the s6 service directory format, replacing SIGTERM for `s6-svc -d`). `make verify` gets a dedicated clean-shutdown check that asserts the next boot logs no recovery.

**D-10 — The official pgBouncer image is amd64-only and years stale.** `pgbouncer/pgbouncer:latest` is a single-arch (amd64) manifest at version **1.15.0**, while upstream pgBouncer is at **1.25.2**. It would break the arm64 half of the matrix and ship a very old pooler. *Resolution:* use **`edoburu/pgbouncer:v1.25.2-p0`** (multi-arch amd64+arm64, current upstream version).

**D-11 — Patroni publishes no production image.** The Patroni project ships only a Dockerfile and compose explicitly marked development-only. Spilo (`ghcr.io/zalando/spilo-NN`) is multi-arch and production-grade, **but it bundles its own PostgreSQL**, which would replace `db-toolkit-pg` entirely and discard our extension suite, baked config, and certs — directly contradicting the spec's core premise. *Resolution:* layer **Patroni 4.1.4 (pip)** onto our own `db-toolkit-pg` image as an s6 service, gated by the `ha` profile. Keeps one PG image across dev, prod, and HA. Costs us the Patroni bootstrap wiring that Spilo would have given free; that work lands in phase 7.

**D-12 — etcd pinned at `v3.6.6`**, multi-arch confirmed. Section 21 states the 3-node minimum explicitly, because a 2-node etcd has *lower* availability than a single node.

**D-13 — MariaDB 11.4 auto-TLS does not conflict with our CA (verified empirically).** I booted `mariadb:11.4.12` twice. With no certs configured: `have_ssl=YES`, `ssl_ca`/`ssl_cert`/`ssl_key` all **empty**, and **no `.pem` written to the datadir** — so zero-config SSL uses an **ephemeral, in-memory, per-start** certificate. With our CA-issued certs in `/etc/mysql/conf.d`: our paths are honoured exactly and `require_secure_transport=ON` works. *Resolution:* explicit certs take precedence; auto-generation only fills a gap. Documented consequence: clients **cannot** use verify-full against the ephemeral cert (it changes every restart), which is precisely why `make certs` and the mounted CA are mandatory rather than optional.

**D-14 — MariaDB's "latest 11.x" is now 11.8, and it is also LTS.** The spec's third MariaDB slot assumed a rolling non-LTS release. *Resolution:* offer `10.11` / `11.4` (default) / `11.8`, all LTS, all pinned. Strictly better than tracking a short-lived release.

**D-15 — MySQL 9.x innovation releases are short-lived.** Current is `9.7.2`. Innovation releases are superseded roughly quarterly and unsupported once replaced. *Resolution:* pin `9.7.2`, and document in UPGRADE.md that the 9.x slot is a preview track, not a deployment target; 8.4 LTS stays the default.

**D-16 — pgvector base distro choice.** Unsuffixed `0.8.6-pgNN` tags are Debian 12 **bookworm**; `-trixie` (Debian 13) variants exist. *Resolution:* build on **bookworm** now, because every PGDG extension version in section 4 was verified against `bookworm-pgdg`. A trixie migration is a tracked follow-up, not a phase-2 blocker.

**D-17 — MySQL and MariaDB do not share a base OS.** MySQL official images are **Oracle Linux 9**; MariaDB is **Ubuntu 24.04** (verified: `11.4.12-MariaDB-ubu2404`). Package managers, config paths, and available client tooling differ. *Resolution:* the two Dockerfiles cannot share a tooling layer; `images/mysql/` uses `microdnf`, `images/mariadb/` uses `apt`. Flagged because "baked-in conf.d + client tooling" in section 6 reads as though one recipe covers both. It does not.

**D-18 — `read_only` rootfs conflicts with every engine.** Section 9 asks for read-only root "wherever the engine tolerates it". PostgreSQL needs writable `PGDATA`, `/var/run/postgresql`, and `/tmp`; MySQL/MariaDB need `/var/run/mysqld` and `/tmp`; s6 needs `/run`. *Resolution:* `read_only: true` **with** an explicit tmpfs list per engine, proven by a `make verify` check that boots each engine read-only. If any engine fails that check it gets `read_only: false` with the reason recorded here rather than a silently dropped hardening claim.

**D-19 — Non-root and s6 as PID 1 interact.** s6-overlay must start as root to run its init stages (permissions, cert placement, conf assembly), then drop to the engine user via `s6-setuidgid`. A container-level `USER postgres` would break stage 1. *Resolution:* container runs as root PID 1 (s6), every long-running service drops privileges; `make verify` asserts no engine process runs as uid 0. This satisfies the intent of section 9 while being honest that the *container user* is root.

**D-20 — "No `latest`" vs. the spec's moving tags.** Section 6 lists tags `:9` and `:11`, which are moving aliases. *Resolution:* our published tags keep those friendly aliases, but every **upstream** base is pinned to an exact minor **and digest**; Renovate raises the bumps.

**D-21 — Supply-chain signing.** Section 9 says "signs images with cosign", while the Simtabi org convention settles on `attest-build-provenance` as the mandatory default with cosign optional. *Resolution:* build provenance attestation + syft SBOM are mandatory in CI; cosign is not added in v1 absent a named downstream consumer. Recorded so the SECURITY.md verification instructions match what CI actually produces.

**D-22 — Repo hygiene: `CLAUDE.md` was being silently excluded.** Your global gitignore (`~/.config/git/ignore:22`) ignores `CLAUDE.md`, so the first commit dropped it while committing `.DS_Store`. Since KIT.md makes CLAUDE.md the contract that binds every session and git the memory between them, losing it would quietly break the whole loop. *Resolution:* repo `.gitignore` negates it (`!CLAUDE.md`), which wins over `core.excludesFile`; `.DS_Store` untracked and ignored.

**D-24 — Every script must be bash 3.2 compatible, because macOS ships bash 3.2.** Found in phase 1 when `make lint` died with `mapfile: command not found`. macOS ships GNU bash **3.2.57** (the last GPLv2 release) and this machine has no Homebrew bash, so `mapfile` (bash 4.0), associative arrays (`declare -A`, bash 4.0), and friends are all unavailable. SPEC section 1 promises the toolkit works "identical across macOS, Windows, and Linux", so depending on a bash the platform does not ship would break that promise on the primary development platform — and it would have broken quietly, since CI runs Linux with bash 5. *Resolution:* every script is written to bash 3.2. Array building uses `while IFS= read -r` loops instead of `mapfile`; `check-env`'s port-collision tracking uses a plain string of `port:key` pairs instead of an associative array. A repo `.shellcheckrc` sets `source-path=SCRIPTDIR` so checks can source `lib.sh` through a dynamic path without tripping SC1091. Recorded because it is a standing constraint on every future phase, not a one-off fix.

**D-23 — Section 19 defaults applied unchanged**, per the kickoff prompt: no plpython3u (toggle available), Tailscale-first prod docs on generic Ubuntu LTS, S3 wiring present but disabled until credentials exist, `ghcr.io/simtabi` private until flipped, defaults PG 17 / MySQL 8.4 / MariaDB 11.4, no extensions beyond sections 5–6, public Laranail conventions only.

## 8. arm64 deliverability

**Nothing in the spec is undeliverable on arm64.** The named unknown anticipated gaps that do not exist:

| Anticipated risk | Actual arm64 status | Workaround needed |
|---|---|---|
| `pg_graphql` (Rust/pgrx) | official prebuilt `.deb`, pg14–18, arm64 | none |
| `pg_net` | source build, portable C | builder stage |
| `pgsodium` | source build, portable C + libsodium | builder stage |
| `pgjwt` | pure plpgsql, arch-independent | vendoring (D-06), not arch |
| `http` | PGDG arm64 1.7.2 | none |
| `pg_partman` | PGDG arm64 5.5.0 | none |
| Every pinned image in §3 | amd64 + arm64 confirmed | none |

The only genuine arm64 hazards found were in **tooling, not extensions**: the official pgBouncer image (amd64-only, D-10) and the backup image's floating tags (arm64-only, D-05). Both are resolved by pinning.

## 9. What happens on approval

Phase 1 builds the complete `make verify` harness first — every SPEC section 18 criterion plus the section 21 additions and the D-09/D-18/D-19 checks — red where features do not exist yet. Then phases 2–7 in order, one per session, each ending on a green `make verify` and a commit.

---

**Awaiting your approval.** The two entries I would most like a decision on before phase 4 are **D-04** (own backup sidecar vs. the 3-job ceiling) and **D-06** (vendor pgjwt vs. drop it). Everything else I consider settled unless you disagree.
