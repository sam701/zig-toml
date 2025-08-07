const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimizeOpt = b.standardOptimizeOption(.{});
    const targetOpt = b.standardTargetOptions(.{});

    const module = b.addModule("toml", .{
        .root_source_file = b.path("src/root.zig"),
        .target = targetOpt,
        .optimize = optimizeOpt,
    });

    const main_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests.zig"),
            .target = targetOpt,
            .optimize = optimizeOpt,
        }),
    });

    const run_tests = b.addRunArtifact(main_tests);
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_tests.step);

    // examples
    {
        const example1 = b.addExecutable(.{
            .name = "example1",
            .root_module = b.createModule(.{
                .root_source_file = b.path("examples/example1.zig"),
                .target = targetOpt,
                .optimize = optimizeOpt,
            }),
        });
        example1.root_module.addImport("toml", module);
        b.installArtifact(example1);

        const run_example1 = b.addRunArtifact(example1);
        if (b.args) |args| {
            run_example1.addArgs(args);
        }

        const build_examples = b.step("examples", "Build and run examples");
        build_examples.dependOn(&run_example1.step);

        b.default_step.dependOn(build_examples);
    }

    // Docs
    {
        const lib = b.addLibrary(.{
            .linkage = .static,
            .name = "toml",
            .root_module = module,
        });
        b.installArtifact(lib);

        const install_docs = b.addInstallDirectory(.{
            .source_dir = lib.getEmittedDocs(),
            .install_dir = .prefix,
            .install_subdir = "docs",
        });

        const docs_step = b.step("docs", "Install docs into zig-out/docs");
        docs_step.dependOn(&install_docs.step);
    }
}
