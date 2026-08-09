# db-toolkit-mysql — MySQL with baked configuration, supervised by s6.
#
# Build context is images/, not images/mysql/, so this can share the init
# scripts and s6 tree with the MariaDB image (see images/_shared/mysql-family).
#
# BASE_IMAGE is passed digest-pinned from images/bases.tsv.
ARG BASE_IMAGE=mysql:8.4.11@sha256:b3b90af2a6552ae30c266fdb7d5dd55f3afb72404bb78d37fe8a23eb857fd3fb

FROM ${BASE_IMAGE}

ARG ENGINE_VERSION=8.4
ARG S6_OVERLAY_VERSION=3.2.3.2
ARG RCLONE_VERSION=1.75.0

LABEL org.opencontainers.image.title="db-toolkit-mysql" \
      org.opencontainers.image.description="MySQL with db-toolkit configuration and tooling, supervised by s6-overlay" \
      org.opencontainers.image.vendor="Simtabi LLC" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.source="https://github.com/simtabi/db-toolkit-docker"

USER root

# Oracle Linux 9, so microdnf. The base already carries tar, xz, zstd, curl,
# gosu and openssl; procps-ng and unzip are what it lacks (DESIGN.md D-17).
RUN set -eux; \
    microdnf install -y procps-ng unzip findutils; \
    microdnf clean all

# --- mysqlbinlog, for point-in-time recovery -----------------------------------
# The official image is mysql-community-server-minimal on Oracle Linux 9 and
# ships no mysqlbinlog, so a binary log could be written and never replayed --
# an audit trail rather than a recovery path.
#
# Installing mysql-community-client does not work: it owns /usr/bin/mysql,
# mysqladmin and mysqldump too, and rpm refuses the file conflicts with
# server-minimal. So ONE FILE is extracted from that RPM instead. No package is
# installed, nothing conflicts, and nothing else from the client package ends
# up in the image.
#
# The version is read from the INSTALLED server rather than pinned here, because
# mysqlbinlog must be able to read what this exact server writes. A pinned
# version would silently drift the first time the base image bumped.
RUN set -eux; \
    arch="$(uname -m)"; \
    ver="$(rpm -q --qf '%{VERSION}-%{RELEASE}' mysql-community-server-minimal)"; \
    microdnf install -y cpio; \
    curl -fsSL -o /tmp/mysql-client.rpm \
        "https://repo.mysql.com/yum/mysql-8.4-community/el/9/${arch}/mysql-community-client-${ver}.${arch}.rpm"; \
    cd /tmp; \
    rpm2cpio /tmp/mysql-client.rpm | cpio -idm ./usr/bin/mysqlbinlog; \
    install -m 0755 /tmp/usr/bin/mysqlbinlog /usr/local/bin/mysqlbinlog; \
    rm -rf /tmp/mysql-client.rpm /tmp/usr; \
    microdnf remove -y cpio; \
    microdnf clean all; \
    mysqlbinlog --version

# rclone is not packaged for Oracle Linux, so it comes from upstream. It is the
# S3 push tool SPEC section 6.1 requires baked into every engine image.
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

# s6-overlay v3 as PID 1.
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
# user-bundles.d, not s6-rc.d/user: the legacy location makes s6 rewrite files
# under /etc at boot, which fails on a read-only root filesystem (D-28).
COPY _shared/mysql-family/user-bundles.d/ /etc/s6-overlay/user-bundles.d/
COPY _shared/mysql-family/scripts/ /usr/local/lib/dbtk/

# Selects the engine-specific half of the shared scripts: daemon name, client
# binary, and the [mysqld] vs [mariadbd] config section.
ENV DBTK_ENGINE=mysql

RUN set -eux; \
    chmod +x /usr/local/lib/dbtk/*.sh; \
    chmod +x /etc/s6-overlay/s6-rc.d/dbtk-engine/run; \
    mkdir -p /etc/mysql/conf.d /var/run/mysqld; \
    chown -R mysql:mysql /var/run/mysqld

# Gracetimes stay at the s6 defaults; raising them only makes the container
# idle after everything is already down (DESIGN.md D-27).
ENV S6_CMD_WAIT_FOR_SERVICES_MAXTIME=0 \
    S6_BEHAVIOUR_IF_STAGE2_FAILS=2 \
    S6_KEEP_ENV=1

HEALTHCHECK --interval=10s --timeout=5s --start-period=90s --retries=5 \
    CMD mysqladmin ping -h localhost --protocol=socket || exit 1

EXPOSE 3306

ENTRYPOINT ["/init"]
