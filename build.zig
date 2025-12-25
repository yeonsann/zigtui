const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Module export for other projects
    const zigtui_module = b.addModule("zigtui", .{
        .root_source_file = b.path("src/lib.zig"),
    });

    // Tests
    const lib_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/lib.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_lib_tests = b.addRunArtifact(lib_tests);
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_lib_tests.step);

    // Example: Hello World
    const hello_example = b.addExecutable(.{
        .name = "hello",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/hello.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigtui", .module = zigtui_module },
            },
        }),
    });
    const install_hello = b.addInstallArtifact(hello_example, .{});
    const examples_step = b.step("examples", "Build example applications");
    examples_step.dependOn(&install_hello.step);

    // Run hello example
    const run_hello = b.addRunArtifact(hello_example);
    run_hello.step.dependOn(&install_hello.step);
    const run_hello_step = b.step("run-hello", "Run hello example");
    run_hello_step.dependOn(&run_hello.step);

    // Example: Widget Showcase
    const showcase_example = b.addExecutable(.{
        .name = "showcase",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/showcase.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigtui", .module = zigtui_module },
            },
        }),
    });
    showcase_example.linkLibC();
    const install_showcase = b.addInstallArtifact(showcase_example, .{});
    examples_step.dependOn(&install_showcase.step);

    // Run showcase example
    const run_showcase = b.addRunArtifact(showcase_example);
    run_showcase.step.dependOn(&install_showcase.step);
    const run_showcase_step = b.step("run-showcase", "Run widget showcase example");
    run_showcase_step.dependOn(&run_showcase.step);
}
