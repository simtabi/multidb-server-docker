# multidb-server-mariadb — MariaDB with baked configuration, supervised by s6.
#
# Build context is images/, not images/mariadb/, so this shares the init
# scripts and s6 tree with the MySQL image (see images/_shared/mysql-family).
#
# BASE_IMAGE is passed digest-pinned from images/bases.tsv.
ARG BASE_IMAGE=mariadb:11.4.12@sha256:67873d30a17f6a9c331f06363b2fa15f38abca415529966d67c84f87f82439fe

FROM ${BASE_IMAGE}

ARG ENGINE_VERSION=11.4
ARG S6_OVERLAY_VERSION=3.2.3.2
ARG RCLONE_VERSION=1.75.0

LABEL org.opencontainers.image.title="multidb-server-mariadb" \
      org.opencontainers.image.description="MariaDB with multidb-server configuration and tooling, supervised by s6-overlay" \
      org.opencontainers.image.vendor="Simtabi LLC" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.source="https://github.com/simtabi/multidb-server"

USER root
ENV DEBIAN_FRONTEND=noninteractive

# Ubuntu 24.04, so apt. The base already carries tar, xz, zstd, gosu, procps
# and openssl; curl and unzip are what it lacks (DESIGN.md D-17).
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl unzip; \
    rm -rf /var/lib/apt/lists/*

# rclone from upstream rather than the distribution, so both engine images
# carry the same version (SPEC section 6.1).
RUN set -eux; \
    case "$(uname -m)" in \
        x86_64)  rc_arch='amd64' ;; \
        aarch64) rc_arch='arm64' ;; \
        *) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /tmp/rclone.zip \
        "https://downloads.rclone.org/v${RCLONE_VERSION}/rclone-v${RCLONE_VERSION}-linux-${rc_arch}.zip"; \
    unzip -q -j /tmp/rclone.zip "*/rclone" -d /usr/local/bin; \
    chmod +x /usr/local/bin/rclone; \
    rm -f /tmp/rclone.zip; \
    rclone version | head -1

RUN set -eux; \
    case "$(uname -m)" in \
        x86_64)  s6_arch='x86_64' ;; \
        aarch64) s6_arch='aarch64' ;; \
    esac; \
    url="https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}"; \
    curl -fsSL -o /tmp/s6-noarch.tar.xz "${url}/s6-overlay-noarch.tar.xz"; \
    curl -fsSL -o /tmp/s6-arch.tar.xz   "${url}/s6-overlay-${s6_arch}.tar.xz"; \
    tar -C / -Jxpf /tmp/s6-noarch.tar.xz; \
    tar -C / -Jxpf /tmp/s6-arch.tar.xz; \
    rm -f /tmp/s6-noarch.tar.xz /tmp/s6-arch.tar.xz

COPY _shared/mysql-family/s6/ /etc/s6-overlay/s6-rc.d/
COPY _shared/mysql-family/user-bundles.d/ /etc/s6-overlay/user-bundles.d/
COPY _shared/mysql-family/scripts/ /usr/local/lib/mdb/

ENV MDB_ENGINE=mariadb

RUN set -eux; \
    chmod +x /usr/local/lib/mdb/*.sh; \
    chmod +x /etc/s6-overlay/s6-rc.d/mdb-engine/run; \
    mkdir -p /etc/mysql/conf.d /var/run/mysqld; \
    chown -R mysql:mysql /var/run/mysqld

ENV S6_CMD_WAIT_FOR_SERVICES_MAXTIME=0 \
    S6_BEHAVIOUR_IF_STAGE2_FAILS=2 \
    S6_KEEP_ENV=1

HEALTHCHECK --interval=10s --timeout=5s --start-period=90s --retries=5 \
    CMD mariadb-admin ping -h localhost --protocol=socket || exit 1

EXPOSE 3306

ENTRYPOINT ["/init"]
