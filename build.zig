const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("msgpack", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const lib_unit_test_mod = b.addModule("lib_unit_test_mod", .{
        .root_source_file = b.path("src/test.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib_unit_tests = b.addTest(.{
        .root_module = lib_unit_test_mod,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const integration_test_mod = b.addModule("integration_test_mod", .{
        .root_source_file = b.path("test/test.zig"),
        .target = target,
        .optimize = optimize,
    });

    integration_test_mod.addImport("msgpack", mod);

    const integration_tests = b.addTest(.{
        .root_module = integration_test_mod,
    });

    const run_integration_tests = b.addRunArtifact(integration_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_integration_tests.step);
    test_step.dependOn(&run_lib_unit_tests.step);

    // Fuzz tests — compiled with -ffuzz instrumentation.
    // Run via: zig build test --release=safe --fuzz
    const fuzz_test_mod = b.addModule("fuzz_test_mod", .{
        .root_source_file = b.path("fuzz/fuzz.zig"),
        .target = target,
        .optimize = optimize,
    });
    fuzz_test_mod.addImport("msgpack", mod);

    const fuzz_tests = b.addTest(.{
        .root_module = fuzz_test_mod,
    });

    const run_fuzz_tests = b.addRunArtifact(fuzz_tests);
    test_step.dependOn(&run_fuzz_tests.step);

    // Fuzz step for standalone fuzzing (zig build fuzz -- --fuzz).
    // Also accessible via the standard `test` step with --fuzz flag.
    const fuzz_step = b.step("fuzz", "Run fuzz tests (alias for 'zig build test --release=safe --fuzz')");
    fuzz_step.dependOn(test_step);

    // Generate documentation for the module.
    const lib = b.addLibrary(.{
        .name = "msgpack",
        .root_module = mod,
        .linkage = .static,
    });

    const install_docs = b.addInstallDirectory(.{
        .source_dir = lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    const docs_step = b.step("docs", "Copy documentation to prefix path");
    docs_step.dependOn(&install_docs.step);
}
