# multidb-server-cassandra — Apache Cassandra with authentication actually on.
#
# The headline: the official image ships `AllowAllAuthenticator` AND
# `AllowAllAuthorizer`. That is not weak authentication, it is none, with no
# authorization either — any client that reaches port 9042 is a superuser.
# SPEC section 22.3 requires every engine here to correct that at build time.
#
# Build context is images/, like every other image.
ARG BASE_IMAGE=cassandra:5.0.8@sha256:259578bbeac315a7326c2a99e60eab86f3415e9e895207bf2a032af4de8c16b5

FROM ${BASE_IMAGE}

ARG ENGINE_VERSION=5.0
ARG S6_OVERLAY_VERSION=3.2.3.2

LABEL org.opencontainers.image.title="multidb-server-cassandra" \
      org.opencontainers.image.description="Apache Cassandra with authentication and authorization enabled, supervised by s6-overlay" \
      org.opencontainers.image.vendor="Simtabi LLC" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.source="https://github.com/simtabi/multidb-server-docker"

USER root
ENV DEBIAN_FRONTEND=noninteractive

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl procps xz-utils zstd; \
    rm -rf /var/lib/apt/lists/*

# s6-overlay v3 as PID 1, same contract as every other engine image.
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

COPY cassandra/s6/ /etc/s6-overlay/s6-rc.d/
COPY cassandra/user-bundles.d/ /etc/s6-overlay/user-bundles.d/
COPY cassandra/scripts/ /usr/local/lib/mdb/

ENV MDB_ENGINE=cassandra

RUN set -eux; \
    chmod +x /usr/local/lib/mdb/*.sh; \
    chmod +x /etc/s6-overlay/s6-rc.d/mdb-engine/run; \
    mkdir -p /mdb/overrides /run/mdb

# Gracetimes at the s6 defaults; raising them only makes the container idle
# after everything is already down (DESIGN.md D-27).
ENV S6_CMD_WAIT_FOR_SERVICES_MAXTIME=0 \
    S6_BEHAVIOUR_IF_STAGE2_FAILS=2 \
    S6_KEEP_ENV=1

# Cassandra is slow to become queryable even on a healthy start: it has a JVM
# to warm and a gossip round to complete. The start period reflects reality
# rather than optimism.
HEALTHCHECK --interval=15s --timeout=10s --start-period=180s --retries=6 \
    CMD nodetool status | grep -q '^UN' || exit 1

EXPOSE 9042

ENTRYPOINT ["/init"]
