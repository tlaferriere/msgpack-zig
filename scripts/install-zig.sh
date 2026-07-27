#!/usr/bin/env bash
# Install the Zig toolchain this package builds with.
#
# This is a script rather than inline Dockerfile steps because two places need
# it: the dev image bakes it in at build time, and the Claude Code on the web
# SessionStart hook runs it against the stock cloud image, which ships no Zig.
#
# Downloads go to a community mirror. ziglang.org's bandwidth is donated and
# upstream asks that automation stay off it, so it is only the last resort here.
#
# Overridable via the environment:
#   ZIG_VERSION      what to install (default: .minimum_zig_version)
#   ZIG_PREFIX       where to unpack it (default: /opt/zig)
#   ZIG_BINDIR       where to link it (default: /usr/local/bin)
#   ZIG_MIRRORS      mirror bases to try, whitespace separated. Set this on a
#                    restricted network to skip mirror discovery, which would
#                    otherwise have to reach ziglang.org first.
#   ZIG_MIRROR_LIST  where to discover mirrors (default: upstream's list)
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

# Mirrors are run by volunteers and are not trusted: the signature check below
# is what makes downloading from them safe, so it is required, not best effort.
if ! command -v minisign > /dev/null 2>&1; then
    if [ "$(id -u)" = 0 ] && command -v apt-get > /dev/null 2>&1; then
        echo "install-zig: installing minisign to verify the download"
        apt-get install -y --no-install-recommends minisign \
            || { apt-get update && apt-get install -y --no-install-recommends minisign; }
    fi
fi
if ! command -v minisign > /dev/null 2>&1; then
    echo "install-zig: minisign is required to verify mirror downloads" >&2
    echo "install-zig: install it (apt-get install minisign / brew install minisign)" >&2
    exit 1
fi

# https://ziglang.org/download/ publishes this key alongside every release.
pubkey=${ZIG_MINISIGN_PUBKEY:-RWSGOq2NVecA2UPNdBUZykf1CCb147pkmdtYxgb3Ti+JO/wCYvhbAb/U}
mirror_list_url=${ZIG_MIRROR_LIST:-https://ziglang.org/download/community-mirrors.txt}
# Mirror operators use this to tell tools apart in their logs.
source_tag=${ZIG_MIRROR_SOURCE:-msgpack-zig}

mirrors=()
if [ -n "${ZIG_MIRRORS:-}" ]; then
    read -r -a mirrors <<< "${ZIG_MIRRORS}"
else
    # Shuffled so a fleet of builders spreads itself over the mirrors rather
    # than all leaning on whichever one happens to be listed first.
    if list=$(curl -fsSL --max-time 20 "${mirror_list_url}" 2> /dev/null); then
        while IFS= read -r line; do
            [ -n "${line}" ] && mirrors+=("${line}")
        done < <(printf '%s\n' "${list}" | sed 's/#.*//; s/[[:space:]]//g' | grep -v '^$' | shuf)
    else
        echo "install-zig: could not read the mirror list at ${mirror_list_url}" >&2
    fi
fi

workdir=$(mktemp -d)
trap 'rm -rf "${workdir}"' EXIT

fetch_and_verify() {
    local tarball_url=$1 sig_url=$2
    rm -f "${workdir}/${tarball}" "${workdir}/${tarball}.minisig"
    curl -fsSL --max-time 300 -o "${workdir}/${tarball}" "${tarball_url}" || return 1
    curl -fsSL --max-time 60 -o "${workdir}/${tarball}.minisig" "${sig_url}" || return 1
    minisign -Vm "${workdir}/${tarball}" -P "${pubkey}" > /dev/null 2>&1 || return 1
}

got_it=
for mirror in "${mirrors[@]}"; do
    base=${mirror%/}
    echo "install-zig: trying ${base}"
    # Mirrors serve the release files flat, unlike ziglang.org's per-version
    # directories.
    if fetch_and_verify \
        "${base}/${tarball}?source=${source_tag}" \
        "${base}/${tarball}.minisig?source=${source_tag}"; then
        got_it=${base}
        break
    fi
    echo "install-zig: ${base} did not serve a valid ${tarball}" >&2
done

if [ -z "${got_it}" ]; then
    # Every mirror failed, or there were none. Upstream would rather serve this
    # than have the install fail outright.
    canonical="https://ziglang.org/download/${version}"
    echo "install-zig: falling back to ${canonical}" >&2
    if fetch_and_verify "${canonical}/${tarball}" "${canonical}/${tarball}.minisig"; then
        got_it=${canonical}
    fi
fi

if [ -z "${got_it}" ]; then
    echo "install-zig: could not obtain a verified ${tarball}" >&2
    exit 1
fi

echo "install-zig: verified ${tarball} from ${got_it}"

rm -rf "${prefix}"
mkdir -p "${prefix}"
tar -xJf "${workdir}/${tarball}" -C "${prefix}" --strip-components=1

mkdir -p "${bindir}"
ln -sf "${prefix}/zig" "${bindir}/zig"

"${bindir}/zig" version
