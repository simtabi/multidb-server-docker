# db-toolkit-pg — PostgreSQL with the full extension suite, supervised by s6.
#
# BASE_IMAGE is passed digest-pinned from images/bases.tsv (the single source of
# truth). It varies by PostgreSQL major, which is why it cannot be a literal
# here; scripts/verify/02-pinned-versions.sh validates that file so the
# indirection is not a way to smuggle in an unpinned base.
ARG BASE_IMAGE=pgvector/pgvector:0.8.6-pg17@sha256:7ae6051efd0e60444282c27c7e141af07f322ce033300e727a49c3dd11075e38

# =============================================================================
# Builder: the four extensions PGDG does not package.
#
# DESIGN.md D-07: pg_graphql ships official prebuilt .deb packages for pg14-18
# on both amd64 and arm64, so it is downloaded rather than compiled. pg_net and
# pgsodium are portable C and are built here. pgjwt is pure plpgsql and is
# vendored, pinned to a commit, because upstream is unmaintained (D-06).
# =============================================================================
FROM ${BASE_IMAGE} AS builder

ARG ENGINE_VERSION=17
ARG PG_GRAPHQL_VERSION=1.6.1
ARG PG_NET_VERSION=0.20.5
# Held one release behind on purpose. pgsodium 3.1.11 added crypto_ipcrypt and
# with it a requirement for libsodium >= 1.0.20; Debian 12 bookworm ships
# 1.0.18, and so does Debian 13 trixie, so this is not fixable by moving base
# image. 3.1.9 is the last release that builds against 1.0.18. See DESIGN.md D-25.
ARG PGSODIUM_VERSION=3.1.9
# michelp/pgjwt has no releases and its last commit is from 2023-03-02, so it is
# pinned by commit rather than tag. See DESIGN.md D-06.
ARG PGJWT_COMMIT=f3d82fd30151e754e19ce5d6a06c71c20689ce3d

ENV DEBIAN_FRONTEND=noninteractive

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        git \
        libcurl4-openssl-dev \
        libsodium-dev \
        pkg-config \
        "postgresql-server-dev-${ENGINE_VERSION}"; \
    rm -rf /var/lib/apt/lists/*

WORKDIR /build

# --- pg_graphql: official prebuilt .deb, per architecture --------------------
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    url="https://github.com/supabase/pg_graphql/releases/download/v${PG_GRAPHQL_VERSION}"; \
    deb="pg_graphql-v${PG_GRAPHQL_VERSION}-pg${ENGINE_VERSION}-${arch}-linux-gnu.deb"; \
    curl -fsSL -o "/build/${deb}" "${url}/${deb}"; \
    mkdir -p /build/out; \
    dpkg-deb -x "/build/${deb}" /build/out

# That .deb does not put its files in the extension directory: it puts them in
# /var/lib/postgresql/extension and SYMLINKS them from there. Two problems.
# First, we only copy /usr into the final image, so the links would dangle and
# PostgreSQL reports "Could not open extension control file ... No such file or
# directory" while `ls` cheerfully shows the entry. Second, and worse, PG 18
# mounts the data volume at /var/lib/postgresql itself, which would shadow the
# real files at runtime even if they were copied.
#
# Flattening the symlinks into real files removes both failure modes.
# See DESIGN.md D-26.
RUN set -eux; \
    find /build/out/usr/share/postgresql -type l -name 'pg_graphql*' | while read -r link; do \
        target="$(readlink -f "$link")"; \
        if [ -f "$target" ]; then \
            rm "$link"; \
            cp "$target" "$link"; \
        else \
            echo "unresolved symlink: $link -> $target" >&2; exit 1; \
        fi; \
    done; \
    find /build/out/usr/share/postgresql -name 'pg_graphql*' -type l | grep . && exit 1 || true

# --- pg_net: C + libcurl ------------------------------------------------------
RUN set -eux; \
    git clone --depth 1 --branch "v${PG_NET_VERSION}" https://github.com/supabase/pg_net.git; \
    cd pg_net; \
    make; \
    make install DESTDIR=/build/out

# --- pgsodium: C + libsodium --------------------------------------------------
RUN set -eux; \
    git clone --depth 1 --branch "v${PGSODIUM_VERSION}" https://github.com/michelp/pgsodium.git; \
    cd pgsodium; \
    make; \
    make install DESTDIR=/build/out

# --- pgjwt: pure plpgsql, vendored and frozen --------------------------------
RUN set -eux; \
    git clone https://github.com/michelp/pgjwt.git; \
    cd pgjwt; \
    git checkout "${PGJWT_COMMIT}"; \
    make install DESTDIR=/build/out

# =============================================================================
# Final image
# =============================================================================
FROM ${BASE_IMAGE}

ARG ENGINE_VERSION=17
ARG S6_OVERLAY_VERSION=3.2.3.2

LABEL org.opencontainers.image.title="db-toolkit-pg" \
      org.opencontainers.image.description="PostgreSQL with the full db-toolkit extension suite, supervised by s6-overlay" \
      org.opencontainers.image.vendor="Simtabi LLC" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.source="https://github.com/simtabi/db-toolkit-docker"

ENV DEBIAN_FRONTEND=noninteractive \
    PG_MAJOR=${ENGINE_VERSION}

# --- PGDG extensions + the baked tool suite ----------------------------------
# Every package here was confirmed available for arm64 against PGDG bookworm
# during step 1 research (DESIGN.md section 4).
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gnupg \
        locales \
        openssl \
        procps \
        rclone \
        xz-utils \
        zstd \
        "postgresql-${PG_MAJOR}-cron" \
        "postgresql-${PG_MAJOR}-hypopg" \
        "postgresql-${PG_MAJOR}-http" \
        "postgresql-${PG_MAJOR}-partman" \
        "postgresql-${PG_MAJOR}-pgaudit" \
        "postgresql-${PG_MAJOR}-pgtap" \
        "postgresql-${PG_MAJOR}-postgis-3" \
        "postgresql-${PG_MAJOR}-postgis-3-scripts" \
        "postgresql-${PG_MAJOR}-repack" \
        "postgresql-plpython3-${PG_MAJOR}" \
        libcurl4 \
        libsodium23; \
    rm -rf /var/lib/apt/lists/*

# --- the four extensions built or fetched above ------------------------------
COPY --from=builder /build/out/usr/ /usr/

# --- s6-overlay v3 as PID 1 ---------------------------------------------------
# DESIGN.md D-19: s6 must start as root to run its init stages (permissions,
# certificate placement, conf assembly) and then drops to the postgres user via
# s6-setuidgid. The container user is therefore root; no engine process is.
RUN set -eux; \
    case "$(dpkg --print-architecture)" in \
        amd64) s6_arch='x86_64' ;; \
        arm64) s6_arch='aarch64' ;; \
        *) echo "unsupported architecture: $(dpkg --print-architecture)" >&2; exit 1 ;; \
    esac; \
    url="https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}"; \
    curl -fsSL -o /tmp/s6-noarch.tar.xz "${url}/s6-overlay-noarch.tar.xz"; \
    curl -fsSL -o /tmp/s6-arch.tar.xz   "${url}/s6-overlay-${s6_arch}.tar.xz"; \
    tar -C / -Jxpf /tmp/s6-noarch.tar.xz; \
    tar -C / -Jxpf /tmp/s6-arch.tar.xz; \
    rm -f /tmp/s6-noarch.tar.xz /tmp/s6-arch.tar.xz

COPY pg/s6/ /etc/s6-overlay/s6-rc.d/
# The user bundle goes in user-bundles.d, not s6-rc.d/user. The legacy location
# is deprecated and, more importantly, makes s6 rewrite files under /etc during
# boot -- which fails outright on a read-only root filesystem.
COPY pg/user-bundles.d/ /etc/s6-overlay/user-bundles.d/
COPY pg/scripts/ /usr/local/lib/dbtk/

RUN set -eux; \
    chmod +x /usr/local/lib/dbtk/*.sh; \
    chmod +x /etc/s6-overlay/s6-rc.d/dbtk-postgres/run; \
    mkdir -p /etc/dbtk /var/run/postgresql /etc/postgresql/conf.d; \
    chown -R postgres:postgres /var/run/postgresql

# STOPSIGNAL is deliberately left at the default SIGTERM.
#
# The obvious move is STOPSIGNAL SIGINT, since PostgreSQL wants SIGINT for a
# fast shutdown -- and it is wrong. Docker sends STOPSIGNAL to PID 1, which is
# s6, and s6 only begins its shutdown sequence on SIGTERM. Sending it SIGINT
# means nothing happens at all until the stop timeout expires and everything is
# SIGKILLed: measurably worse than doing nothing.
#
# The correct split is SIGTERM to s6, which then stops each service with that
# service's own down-signal -- SIGINT for PostgreSQL. See s6/dbtk-postgres/
# down-signal and DESIGN.md D-09.

# Wait indefinitely for init stages rather than starting the engine early, and
# bring the whole container down if an init stage fails instead of running a
# half-provisioned database.
# Gracetimes stay at the s6 defaults (3000ms) on purpose. Raising them does NOT
# give the database more time to shut down -- s6-supervise already waits
# indefinitely for a service to exit -- it only makes s6 sit on its hands after
# everything is already down, which shows up as a container that takes the full
# grace period to stop long after PostgreSQL has checkpointed and exited.
# The database's own budget is stop_grace_period / docker stop -t.
ENV S6_CMD_WAIT_FOR_SERVICES_MAXTIME=0 \
    S6_BEHAVIOUR_IF_STAGE2_FAILS=2 \
    S6_KEEP_ENV=1

HEALTHCHECK --interval=10s --timeout=5s --start-period=60s --retries=5 \
    CMD pg_isready -U "${POSTGRES_USER:-postgres}" -h /var/run/postgresql || exit 1

EXPOSE 5432

ENTRYPOINT ["/init"]
