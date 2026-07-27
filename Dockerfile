# syntax=docker/dockerfile:1

# Development toolchain for msgpack-zig: Zig 0.16 plus a matching ZLS.
#
# This image carries tools only — the repo is meant to be bind-mounted, not
# copied in, so edits on the host are what get built.
#
#   docker build -t msgpack-zig-dev \
#       --build-arg UID="$(id -u)" --build-arg GID="$(id -g)" .
#
#   docker run --rm -it \
#       -v "$PWD:/workspace" \
#       -v msgpack-zig-cache:/home/dev/.cache \
#       msgpack-zig-dev
#
# The named cache volume is what keeps `zig build` incremental across runs; it
# also holds the fuzz corpus under the project's .zig-cache, which stays in the
# bind-mounted worktree.

FROM debian:trixie-slim

LABEL org.opencontainers.image.title="msgpack-zig dev toolchain" \
      org.opencontainers.image.source="https://github.com/tlaferriere/msgpack-zig"

# build.zig.zon declares .minimum_zig_version = "0.16.0".
ARG ZIG_VERSION=0.16.0
# ZLS releases track Zig releases; keep this in step with ZIG_VERSION.
ARG ZLS_VERSION=0.16.0
# Zig's release signing key, published alongside the tarballs on
# https://ziglang.org/download/. Override only if upstream rotates it.
ARG ZIG_MINISIGN_PUBKEY=RWSGOq2NVecA2UPNdBUZykf1CCb147pkmdtYxgb3Ti+JO/wCYvhbAb/U

# Supplied by BuildKit. Docker's arch names differ from the ones in the Zig and
# ZLS asset names, so each install step maps it below.
ARG TARGETARCH

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gdb \
        git \
        less \
        minisign \
        xz-utils \
    && rm -rf /var/lib/apt/lists/*

# Zig, verified against the upstream signature before it is unpacked.
RUN set -euo pipefail; \
    case "${TARGETARCH}" in \
        amd64) arch=x86_64 ;; \
        arm64) arch=aarch64 ;; \
        *) echo "unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    tarball="zig-${arch}-linux-${ZIG_VERSION}.tar.xz"; \
    base="https://ziglang.org/download/${ZIG_VERSION}"; \
    curl -fsSL -o "/tmp/${tarball}" "${base}/${tarball}"; \
    curl -fsSL -o "/tmp/${tarball}.minisig" "${base}/${tarball}.minisig"; \
    minisign -Vm "/tmp/${tarball}" -P "${ZIG_MINISIGN_PUBKEY}"; \
    mkdir -p /opt/zig; \
    tar -xJf "/tmp/${tarball}" -C /opt/zig --strip-components=1; \
    rm -f "/tmp/${tarball}" "/tmp/${tarball}.minisig"; \
    ln -s /opt/zig/zig /usr/local/bin/zig; \
    zig version

# ZLS. Upstream publishes no signature, and the archive layout has moved
# between releases, so locate the binary rather than assuming a path.
RUN set -euo pipefail; \
    case "${TARGETARCH}" in \
        amd64) arch=x86_64 ;; \
        arm64) arch=aarch64 ;; \
        *) echo "unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /tmp/zls.tar.xz \
        "https://github.com/zigtools/zls/releases/download/${ZLS_VERSION}/zls-${arch}-linux.tar.xz"; \
    mkdir -p /tmp/zls; \
    tar -xJf /tmp/zls.tar.xz -C /tmp/zls; \
    install -m 0755 "$(find /tmp/zls -type f -name zls | head -n 1)" /usr/local/bin/zls; \
    rm -rf /tmp/zls /tmp/zls.tar.xz; \
    zls --version

# Run as a normal user so files written into the bind-mounted worktree keep the
# host's ownership. Pass UID/GID at build time when they are not 1000.
ARG USER=dev
ARG UID=1000
ARG GID=1000
RUN groupadd --gid "${GID}" "${USER}" \
    && useradd --uid "${UID}" --gid "${GID}" --create-home --shell /bin/bash "${USER}"

# The worktree is mounted from the host, so its owner rarely matches any user
# git knows about in here; without this every git command trips the
# dubious-ownership guard.
RUN git config --system --add safe.directory /workspace

# Keep the global cache (fetched packages, compiler artifacts) on its own path
# so a single named volume makes rebuilds incremental.
ENV ZIG_GLOBAL_CACHE_DIR=/home/${USER}/.cache/zig
RUN install -d -o "${UID}" -g "${GID}" "${ZIG_GLOBAL_CACHE_DIR}"

USER ${USER}
WORKDIR /workspace
CMD ["bash"]
