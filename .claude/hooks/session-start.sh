#!/bin/bash
# Give Claude Code on the web sessions the Zig toolchain this package needs.
#
# The cloud image ships no Zig, and replacing it with our own image is not
# supported, so the toolchain is installed on top of the stock one instead. The
# container state is cached after this completes, so it is normally a no-op.
set -euo pipefail

# Local machines already have a toolchain, or use the dev image.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
    exit 0
fi

project_dir=${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}

# A missing toolchain should not stop the session from starting — Claude can
# still read code and answer questions. Report it and let the session continue.
if ! "${project_dir}/scripts/install-zig.sh"; then
    cat >&2 <<'EOF'
session-start: could not install Zig.

Zig is downloaded from ziglang.org, which is not on the Trusted network
allowlist. In the environment's settings, set Network access to Custom, keep
the default package-manager list, and add:

    ziglang.org

`zig build test` will not work in this session until then.
EOF
fi

exit 0
