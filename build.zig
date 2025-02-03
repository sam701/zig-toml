const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimizeOpt = b.standardOptimizeOption(.{});
    const targetOpt = b.standardTargetOptions(.{});

    const datetime = b.createModule(.{ .root_source_file = b.path("src/datetime.zig") });
    const parser = b.createModule(.{ .root_source_file = b.path("src/parser.zig") });

    const module = b.addModule("zig-toml", .{ .root_source_file = b.path("src/main.zig") });
    module.addImport("datetime", datetime);
    module.addImport("parser", parser);
    datetime.addImport("parser", parser);

    const main_tests = b.addTest(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = targetOpt,
        .optimize = optimizeOpt,
    });
    const serialize_tests = b.addTest(.{
        .root_source_file = b.path("src/serialize/tests.zig"),
        .target = targetOpt,
        .optimize = optimizeOpt,
    });

    main_tests.root_module.addImport("parser", parser);
    main_tests.root_module.addImport("datetime", datetime);
    serialize_tests.root_module.addImport("datetime", datetime);

    const run_tests = b.addRunArtifact(main_tests);
    const run_serialize_tests = b.addRunArtifact(serialize_tests);
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_tests.step);
    test_step.dependOn(&run_serialize_tests.step);

    // === examples
    const example1 = b.addExecutable(.{
        .name = "example1",
        .root_source_file = b.path("examples/example1.zig"),
        .target = targetOpt,
        .optimize = optimizeOpt,
    });
    example1.root_module.addImport("zig-toml", module);
    b.installArtifact(example1);

    const run_example1 = b.addRunArtifact(example1);
    if (b.args) |args| {
        run_example1.addArgs(args);
    }

    const build_examples = b.step("examples", "Build and run examples");
    build_examples.dependOn(&run_example1.step);

    b.default_step.dependOn(build_examples);
}
