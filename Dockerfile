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

# apt keeps its downloads across builds in a cache mount rather than being
# re-fetched every time. This pair of steps is the recipe from Docker's own
# cache-mount guide, verbatim:
# https://docs.docker.com/build/cache/optimize/#use-cache-mounts
#
# It reads oddly out of context, so: the Debian images ship
# /etc/apt/apt.conf.d/docker-clean, which deletes each .deb the moment it is
# unpacked. That exists because the archives would otherwise be dead weight in
# the layer — but with a cache mount they are the whole point, so the file has
# to go and apt has to be told to keep what it downloads. Nothing deletes
# /var/lib/apt/lists afterwards either: it is the mount, not a layer, so it
# never reaches the image.
RUN rm -f /etc/apt/apt.conf.d/docker-clean \
    && echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' \
        > /etc/apt/apt.conf.d/keep-cache

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gdb \
        git \
        less \
        minisign \
        ripgrep \
        xz-utils

# Same script the cloud SessionStart hook runs, so both paths install Zig the
# same way. build.zig.zon comes along only as the version source.
COPY scripts/install-zig.sh /opt/msgpack-zig/scripts/install-zig.sh
COPY build.zig.zon /opt/msgpack-zig/build.zig.zon
RUN ZIG_VERSION="${ZIG_VERSION}" /opt/msgpack-zig/scripts/install-zig.sh

# ZLS. Upstream publishes no signature, and the archive layout has moved between
# releases, so locate the binary rather than assuming a path.
#
# /tmp is a tmpfs mount for this step only, so the archive and the unpacked tree
# never reach a layer and there is nothing to clean up afterwards.
RUN --mount=type=tmpfs,target=/tmp \
    set -euo pipefail; \
    arch="$(uname -m)"; \
    curl -fsSL -o /tmp/zls.tar.xz \
        "https://github.com/zigtools/zls/releases/download/${ZLS_VERSION}/zls-${arch}-linux.tar.xz"; \
    mkdir -p /tmp/zls; \
    tar -xJf /tmp/zls.tar.xz -C /tmp/zls; \
    install -m 0755 "$(find /tmp/zls -type f -name zls | head -n 1)" /usr/local/bin/zls; \
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
