# Fix fuzzing crashes
When fixing a crash found by running `zig build --release=safe test --fuzz=100000`, always ensure to create a unit test to reproduce the exact error reported by the fuzzer.

To do so, if `jj` is installed, create a revision with a command like `jj new -m "Reproduce string out-of-bounds error"` describing the error you are trying to reproduce.
Add a unit test that reproduces the crash found in fuzzing.

Once the test runs, fails with the same error found in fuzzing, create a new revision with a command like `jj new -m "Fix string out-of-bounds error"` describing the fix.
Then apply the fix with minimal code changes, avoiding scope creep.