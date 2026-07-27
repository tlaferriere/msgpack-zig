# syntax=docker/dockerfile:1

# Development toolchain for msgpack-zig: Zig 0.16 plus a matching ZLS.
#
# Two targets:
#   tools  root, no unprivileged user. What CI publishes to GHCR, and what to
#          use as a base image or a plain `docker run`.
#   dev    the default. Adds a normal user so files written into a bind-mounted
#          worktree keep the host's ownership.
#
#   docker build -t msgpack-zig-dev \
#       --build-arg UID="$(id -u)" --build-arg GID="$(id -g)" .
#
#   docker run --rm -it \
#       -v "$PWD:/workspace" \
#       -v msgpack-zig-cache:/home/dev/.cache \
#       msgpack-zig-dev
#
# The image carries tools only; the worktree is mounted, never copied, so the
# image cannot go stale against the source. The named cache volume is what keeps
# `zig build` incremental across runs.

FROM debian:trixie-slim AS tools

LABEL org.opencontainers.image.title="msgpack-zig dev toolchain" \
      org.opencontainers.image.source="https://github.com/tlaferriere/msgpack-zig"

# build.zig.zon declares .minimum_zig_version = "0.16.0"; install-zig.sh reads
# that file when this is empty, so the two cannot drift.
ARG ZIG_VERSION=
# ZLS releases track Zig releases; keep this in step with the Zig version.
ARG ZLS_VERSION=0.16.0

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gdb \
        git \
        less \
        minisign \
        ripgrep \
        xz-utils \
    && rm -rf /var/lib/apt/lists/*

# Same script the cloud SessionStart hook runs, so both paths install Zig the
# same way. build.zig.zon comes along only as the version source.
COPY scripts/install-zig.sh /opt/msgpack-zig/scripts/install-zig.sh
COPY build.zig.zon /opt/msgpack-zig/build.zig.zon
RUN ZIG_VERSION="${ZIG_VERSION}" /opt/msgpack-zig/scripts/install-zig.sh

# ZLS. Upstream publishes no signature, and the archive layout has moved between
# releases, so locate the binary rather than assuming a path.
RUN set -euo pipefail; \
    arch="$(uname -m)"; \
    curl -fsSL -o /tmp/zls.tar.xz \
        "https://github.com/zigtools/zls/releases/download/${ZLS_VERSION}/zls-${arch}-linux.tar.xz"; \
    mkdir -p /tmp/zls; \
    tar -xJf /tmp/zls.tar.xz -C /tmp/zls; \
    install -m 0755 "$(find /tmp/zls -type f -name zls | head -n 1)" /usr/local/bin/zls; \
    rm -rf /tmp/zls /tmp/zls.tar.xz; \
    zls --version

# The worktree is mounted from the host, so its owner rarely matches any user
# git knows about in here; without this every git command trips the
# dubious-ownership guard.
RUN git config --system --add safe.directory /workspace

WORKDIR /workspace
CMD ["bash"]

# Default target: same tools, run as a normal user. Pass UID/GID at build time
# when they are not 1000.
FROM tools AS dev

ARG USER=dev
ARG UID=1000
ARG GID=1000
RUN groupadd --gid "${GID}" "${USER}" \
    && useradd --uid "${UID}" --gid "${GID}" --create-home --shell /bin/bash "${USER}"

# Keep the global cache (fetched packages, compiler artifacts) on its own path
# so a single named volume makes rebuilds incremental.
ENV ZIG_GLOBAL_CACHE_DIR=/home/${USER}/.cache/zig
RUN install -d -o "${UID}" -g "${GID}" "${ZIG_GLOBAL_CACHE_DIR}"

USER ${USER}
WORKDIR /workspace
CMD ["bash"]
