const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const lib = b.addStaticLibrary("zig-toml", "src/main.zig");
    lib.setBuildMode(mode);
    lib.install();

    // === tests
    const main_tests = b.addTest("src/tests.zig");
    main_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);

    // === examples
    const example1 = b.addExecutable("example1", "examples/example1.zig");
    example1.addPackagePath("zig-toml", "src/main.zig");
    example1.setBuildMode(mode);
    example1.install();

    const run_example1 = example1.run();
    if (b.args) |args| {
        run_example1.addArgs(args);
    }

    const build_examples = b.step("examples", "Build and run examples");
    build_examples.dependOn(&run_example1.step);
}
