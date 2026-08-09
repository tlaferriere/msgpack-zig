# Msgpack for Zig

This is a zig implementation of msgpack, available as a module.

## API Documentation

Here is the [API Documentation](https://tlaferriere.github.io/msgpack-zig/)

## Limits

msgpack is a binary format, usually parsed from input you do not control. A
length field sits in the header of every string, array, map and extension value,
and it is a claim by the sender — not a fact. `Unpacker` therefore treats a
declared length as a limit and a loop bound, never as an allocation size, and
enforces one ceiling of its own:

```zig
var message = msgpack.Unpacker.initWithOptions(allocator, &reader, .{
    .max_message_bytes = 64 * 1024 * 1024, // default
    .max_prealloc_bytes = 1024 * 1024,     // default
});
```

- **`max_message_bytes`** is the guarantee: decoding one message never demands
  more than this, whatever the input claims or how deeply it nests. Exceeding it
  is `error.MessageTooLong`, returned before any allocation is attempted. It is a
  ceiling on what a message may ask for, not a measurement of live heap — nested
  containers all draw from the same per-message allowance, and it resets on each
  `unpack_as`.
- **`max_prealloc_bytes`** is only a performance dial. At or below it a value is
  allocated once at its exact size; above it, capacity grows geometrically from
  the bytes and elements that actually arrive. Either way a sender who claims 4
  GiB and delivers 8 bytes pays for 8 bytes.

`Unpacker.init` uses the defaults. Raise `max_message_bytes` via
`initWithOptions` if you legitimately decode messages larger than 64 MiB.

## Running Tests

```sh
# Run all tests (unit + integration + fuzz smoke tests):
zig build test

# Run fuzz tests with the fuzzer (continuously mutates inputs to find crashes):
zig build test --release=safe --fuzz

# Limited fuzz runs (e.g. 1 million iterations):
zig build test --release=safe --fuzz=1000000

# Generate docs:
zig build docs
```

## Fuzz Testing

Fuzz tests live in `fuzz/fuzz.zig` and use Zig's built-in `std.testing.fuzz` API.

Three strategies are employed:

- **Unpacker fuzzing** (`fuzz unpack scalars`, `arrays`, `maps`, `structs`) —
  Feeds arbitrary byte sequences to the `Unpacker` and attempts to deserialize
  each family of types. Expected `DeserializeError` returns are ignored; only
  panics, crashes and leaks are caught. This is the most critical target since
  msgpack is a binary format commonly parsed from untrusted input. The container
  targets matter especially because they size an allocation from a length field
  taken straight from the input, then fill it with fallible reads.

- **Structured round-trip fuzzing** — Uses `Smith` to generate random values,
  packs them with `Packer`, then unpacks with `Unpacker` and asserts the result
  matches the original. Covers scalars (`u64`, `i64`, `?u32`, `bool`, `f32`,
  `f64`), non-power-of-two and oversized int widths, strings, binary blobs,
  slices, maps, structs serialized as maps, extension types, and timestamps.
  Catches logic errors in both serialization and deserialization paths.

- **Mutation fuzzing** (`fuzz mutated valid message`) — Packs a valid message,
  then lets the fuzzer corrupt a single byte. Keeping the prefix structurally
  valid reaches parser states that uniformly random bytes almost never hit.

When run without `--fuzz`, each fuzz test executes as a quick smoke test against
an empty input. With `--fuzz`, the build system rebuilds the test binary with
`-ffuzz` instrumentation and the built-in libFuzzer-based fuzzer takes over,
continuously mutating inputs to maximize code coverage.

> **Note:** `--release=safe` belongs on the `--fuzz` runs only; the test suite
> itself builds and passes in Debug. Fuzz mode is where the other modes break:
> Debug fails to compile, because `-ffuzz` pulls in a branch of Zig 0.16's test
> runner that does not build, and ReleaseSmall strips the debug info the fuzzer
> reads coverage from. ReleaseFast does run, but turns off the safety checks
> most of these targets detect bugs *with*.

## Contributing

To make it easy to have the right toolchain on hand, the repo ships a
`Dockerfile` that installs Zig 0.16 (the version `build.zig.zon` requires) and a
matching ZLS. Build it once, passing your own uid/gid so files written into the
mounted worktree stay yours:

```sh
docker build -t msgpack-zig-dev \
    --build-arg UID="$(id -u)" --build-arg GID="$(id -g)" .
```

Then work inside it with the repo bind-mounted:

```sh
docker run --rm -it \
    -v "$PWD:/workspace" \
    -v msgpack-zig-cache:/home/dev/.cache \
    msgpack-zig-dev

# inside the container:
zig build test
zig build docs
```

The image carries no source of its own — `/workspace` is your checkout, so edits
made on the host are what get compiled. The named volume holds Zig's global
cache, which is what keeps rebuilds incremental between runs; the project's own
`.zig-cache` (including the fuzz corpus) lives in the worktree as usual.

Other Zig versions are one flag away, should you need to check behaviour against
one: `--build-arg ZIG_VERSION=0.16.1 --build-arg ZLS_VERSION=0.16.1`. Left unset,
`ZIG_VERSION` follows `.minimum_zig_version` in `build.zig.zon`, so the toolchain
tracks the package rather than drifting from it.

### Where Zig comes from

`scripts/install-zig.sh` downloads Zig from a [community
mirror](https://ziglang.org/download/community-mirrors/), picked at random from
upstream's list, because ziglang.org's bandwidth is donated and upstream asks
that automation stay off it. ziglang.org is used only if every mirror fails.

Mirrors are run by volunteers, so nothing is trusted on arrival: each download
is checked against Zig's minisign public key, and a mirror that serves anything
that does not verify is skipped rather than used. The check is required — if
`minisign` is missing the script installs it, and refuses to continue if it
cannot. A few knobs, none of them normally needed:

| Variable | Effect |
| --- | --- |
| `ZIG_MIRRORS` | Mirrors to use, whitespace separated. Skips discovery, which is what a network that only allows one host needs. |
| `ZIG_MIRROR_LIST` | Where to discover mirrors, if not upstream's list. |
| `ZIG_VERSION` | What to install, if not `.minimum_zig_version`. |
| `ZIG_PREFIX`, `ZIG_BINDIR` | Where it lands. Defaults to `/opt/zig` and `/usr/local/bin`. |

### Pulling the image instead of building it

The `Dev Image` workflow publishes the same toolchain to GHCR on every push to
`main`, so it can be pulled rather than rebuilt:

```sh
docker pull ghcr.io/tlaferriere/msgpack-zig-dev:latest
docker run --rm -it -v "$PWD:/workspace" ghcr.io/tlaferriere/msgpack-zig-dev:latest
```

Images are tagged `latest` and `sha-<commit>`, and built for `linux/amd64` and
`linux/arm64`. The published image is the `tools` stage: identical tools, but
running as root with no baked-in uid, which is what suits a base image or a
throwaway container. The `dev` stage above is the one to build locally, since
only you know which uid should own your files.
