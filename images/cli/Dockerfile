# multidb-server-cli — every client tool, no server.
#
# SPEC decision 12: CLI tools are not daemons, so the one-process-per-container
# rule does not apply to them. This is the one place a combined image is right,
# and it exists so the tools are usable with NO engine container running --
# inspecting a dump, restoring into a remote host, or opening a shell against
# a database that lives somewhere else entirely.
#
# Build context is images/, like every other image here.
ARG BASE_IMAGE=debian:12-slim@sha256:abd67ffcfa541b485a3dff59865ab629aa048a6c613e639d36e7456b0b229241

FROM ${BASE_IMAGE}

ARG PG_CLIENT_VERSION=17
ARG RCLONE_VERSION=1.75.0

LABEL org.opencontainers.image.title="multidb-server-cli" \
      org.opencontainers.image.description="PostgreSQL, MySQL and MariaDB clients, dump/restore tools, and the multidb-server scripts" \
      org.opencontainers.image.vendor="Simtabi LLC" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.source="https://github.com/simtabi/multidb-server"

ENV DEBIAN_FRONTEND=noninteractive

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gnupg \
        jq \
        less \
        openssl \
        procps \
        unzip \
        zstd; \
    rm -rf /var/lib/apt/lists/*

# PostgreSQL client from PGDG so its major matches the engines this toolkit
# runs, rather than whatever Debian happens to ship.
RUN set -eux; \
    . /etc/os-release; \
    install -d /usr/share/postgresql-common/pgdg; \
    curl -fsSo /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc \
        https://www.postgresql.org/media/keys/ACCC4CF8.asc; \
    echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt ${VERSION_CODENAME}-pgdg main" \
        > /etc/apt/sources.list.d/pgdg.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends "postgresql-client-${PG_CLIENT_VERSION}"; \
    rm -rf /var/lib/apt/lists/*

# MySQL-family clients. Debian's mariadb-client also provides the `mysql` and
# `mysqldump` names, so both families work from one package.
#
# Worth knowing: those names are MariaDB's implementations. For INTERACTIVE use
# against MySQL that is fine, but scheduled dumps deliberately do not run from
# here -- each backup sidecar runs on its own engine's image so it uses that
# engine's native dump tool (see docker-compose.yml).
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends mariadb-client; \
    rm -rf /var/lib/apt/lists/*

# rclone for S3-compatible targets, matching the engine images' version.
RUN set -eux; \
    case "$(dpkg --print-architecture)" in \
        amd64) rc_arch='amd64' ;; \
        arm64) rc_arch='arm64' ;; \
        *) echo "unsupported architecture: $(dpkg --print-architecture)" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /tmp/rclone.zip \
        "https://downloads.rclone.org/v${RCLONE_VERSION}/rclone-v${RCLONE_VERSION}-linux-${rc_arch}.zip"; \
    unzip -q -j /tmp/rclone.zip "*/rclone" -d /usr/local/bin; \
    chmod +x /usr/local/bin/rclone; \
    rm -f /tmp/rclone.zip

# The toolkit scripts, so backup/restore/new-project are available here too.
COPY --chmod=0755 cli/entrypoint.sh /usr/local/bin/mdb-entrypoint

# No server runs here, so there is no engine user to drop to and nothing
# listening. Running as a non-root user keeps a mounted host directory from
# being written as root.
RUN set -eux; \
    useradd --create-home --uid 1000 --shell /bin/bash mdb
USER mdb
WORKDIR /work

ENTRYPOINT ["/usr/local/bin/mdb-entrypoint"]
CMD ["bash"]
