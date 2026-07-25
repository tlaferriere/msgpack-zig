# Msgpack for Zig

This is a zig implementation of msgpack, available as a module.

## API Documentation

Here is the [API Documentation](https://tlaferriere.github.io/msgpack-zig/)

## Running Tests

```sh
# Run all tests (unit + integration + fuzz smoke tests):
zig build test --release=safe

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

> **Note:** `--release=safe` is required because Debug mode causes a compilation error in the standard library.

## Contributing

To make it easy to have the right
