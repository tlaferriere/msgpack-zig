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

Two strategies are employed:

- **Unpacker fuzzing** (`fuzz unpack raw bytes`) — Feeds arbitrary byte sequences
  to the `Unpacker` and attempts to deserialize every primitive type (bool, ints,
  floats, strings, timestamps). Expected `DeserializeError` returns are ignored;
  only panics and crashes are caught. This is the most critical target since
  msgpack is a binary format commonly parsed from untrusted input.

- **Structured round-trip fuzzing** (5 tests) — Uses `Smith` to generate random
  values (`u64`, `i64`, `?u32`, `bool`, `f64`), packs them with `Packer`, then
  unpacks with `Unpacker` and asserts the result matches the original. Catches
  logic errors in both serialization and deserialization paths.

When run without `--fuzz`, each fuzz test executes as a quick smoke test against
an empty input. With `--fuzz`, the build system rebuilds the test binary with
`-ffuzz` instrumentation and the built-in libFuzzer-based fuzzer takes over,
continuously mutating inputs to maximize code coverage.

> **Note:** `--release=safe` is required because Debug mode causes a compilation error in the standard library.

## Contributing

To make it easy to have the right
