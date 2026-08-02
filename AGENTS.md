# Working on msgpack-zig with coding agents

## Claude Code on the web

Cloud sessions cannot use the toolchain image directly — [replacing the base
image is not supported](https://code.claude.com/docs/en/claude-code-on-the-web).
Zig is installed on top of the stock image instead, by a `SessionStart` hook in
`.claude/settings.json` that runs `scripts/install-zig.sh` — the same installer
the `Dockerfile` uses, so both paths land on the same compiler.

That download needs to reach a mirror, and the mirror list itself lives on
`ziglang.org` — neither is on the default Trusted allowlist. Set the
environment's network access to **Custom**, keep the default package-manager
list, and add `ziglang.org`. To stay off it entirely, allow a mirror's host
instead and set `ZIG_MIRRORS` to that mirror in the environment's variables,
which skips discovery. Without either, the hook reports the problem and the
session still starts, but `zig build` will not work.
