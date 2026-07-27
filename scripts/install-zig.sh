#!/usr/bin/env bash
# Install the Zig toolchain this package builds with.
#
# This is a script rather than inline Dockerfile steps because two places need
# it: the dev image bakes it in at build time, and the Claude Code on the web
# SessionStart hook runs it against the stock cloud image, which ships no Zig.
#
# Overridable via the environment: ZIG_VERSION, ZIG_PREFIX, ZIG_BINDIR.
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# Default to whatever build.zig.zon requires, so the toolchain follows the
# package instead of drifting from it the way zig/activate did.
version=${ZIG_VERSION:-}
if [ -z "${version}" ] && [ -f "${repo_root}/build.zig.zon" ]; then
    version=$(sed -n 's/.*\.minimum_zig_version[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' \
        "${repo_root}/build.zig.zon")
fi
if [ -z "${version}" ]; then
    echo "install-zig: could not determine a Zig version" >&2
    exit 1
fi

prefix=${ZIG_PREFIX:-/opt/zig}
bindir=${ZIG_BINDIR:-/usr/local/bin}

# Cloud sessions re-run this on every start, and the container state is cached
# between them, so the common case should cost nothing.
if [ -x "${bindir}/zig" ] && [ "$("${bindir}/zig" version 2>/dev/null)" = "${version}" ]; then
    echo "install-zig: zig ${version} already installed"
    exit 0
fi

arch=$(uname -m)
case "${arch}" in
    x86_64 | aarch64) ;;
    *)
        echo "install-zig: unsupported architecture: ${arch}" >&2
        exit 1
        ;;
esac

tarball="zig-${arch}-linux-${version}.tar.xz"
base="https://ziglang.org/download/${version}"

workdir=$(mktemp -d)
trap 'rm -rf "${workdir}"' EXIT

echo "install-zig: fetching ${base}/${tarball}"
curl -fsSL -o "${workdir}/${tarball}" "${base}/${tarball}"

# Zig signs every release. minisign is in the dev image; the cloud image has no
# package for it, and installing one just to check a signature is a worse trade
# than saying plainly that the check did not happen.
pubkey=${ZIG_MINISIGN_PUBKEY:-RWSGOq2NVecA2UPNdBUZykf1CCb147pkmdtYxgb3Ti+JO/wCYvhbAb/U}
if command -v minisign > /dev/null 2>&1; then
    curl -fsSL -o "${workdir}/${tarball}.minisig" "${base}/${tarball}.minisig"
    minisign -Vm "${workdir}/${tarball}" -P "${pubkey}"
else
    echo "install-zig: minisign not found, installing ${tarball} unverified" >&2
fi

rm -rf "${prefix}"
mkdir -p "${prefix}"
tar -xJf "${workdir}/${tarball}" -C "${prefix}" --strip-components=1

mkdir -p "${bindir}"
ln -sf "${prefix}/zig" "${bindir}/zig"

"${bindir}/zig" version
