const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimizeOpt = b.standardOptimizeOption(.{});
    const targetOpt = b.standardTargetOptions(.{});

    const module = b.addModule("toml", .{
        .root_source_file = b.path("src/root2.zig"),
        .target = targetOpt,
        .optimize = optimizeOpt,
    });

    // Tests
    {
        // Run with `zig build test -Dtest-filter hashmap`
        const test_filter = b.option([]const []const u8, "test-filter", "Filter tests by name") orelse &.{};

        const main_tests = b.addTest(.{
            .root_module = module,
            .filters = test_filter,
        });

        const run_tests = b.addRunArtifact(main_tests);

        const test_step = b.step("test", "Run library tests");
        test_step.dependOn(&run_tests.step);
    }

    // examples
    // {
    //     const example_mod = b.addModule("example1", .{
    //         .root_source_file = b.path("examples/example1.zig"),
    //         .target = targetOpt,
    //         .optimize = optimizeOpt,
    //     });

    //     const example1 = b.addExecutable(.{
    //         .name = "example1",
    //         .root_module = example_mod,
    //     });
    //     example1.root_module.addImport("toml", module);
    //     b.installArtifact(example1);

    //     const run_example1 = b.addRunArtifact(example1);
    //     if (b.args) |args| {
    //         run_example1.addArgs(args);
    //     }

    //     const build_examples = b.step("examples", "Build and run examples");
    //     build_examples.dependOn(&run_example1.step);

    //     b.default_step.dependOn(build_examples);
    // }

    // toml-test decoder
    {
        const decoder_mod = b.addModule("toml-test-decoder", .{
            .root_source_file = b.path("test/main.zig"),
            .target = targetOpt,
            .optimize = optimizeOpt,
        });
        decoder_mod.addImport("toml", module);

        const decoder = b.addExecutable(.{
            .name = "toml-test-decoder",
            .root_module = decoder_mod,
        });
        b.installArtifact(decoder);

        const decoder_step = b.step("decoder", "Build the toml-test decoder");
        decoder_step.dependOn(&decoder.step);
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
