const std = @import("std");

pub fn build(b: *std.Build) void {
    // source directory
    const src_dir = "src";

    // build options for the library
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    _ = b.addModule("zig-scan", .{
        .root_source_file = b.path(src_dir ++ "/zig-scan.zig"),
    });

    // try to generate test step
    generate_test_step: {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const allocator = gpa.allocator();
        const argv = [_][]const u8{ "find", src_dir, "-name", "*.zig" };

        const r = std.process.Child.run(.{
            .allocator = allocator,
            .argv = &argv,
        }) catch break :generate_test_step;

        defer {
            allocator.free(r.stdout);
            allocator.free(r.stderr);
        }

        const run_all_tests = b.step("test", "Run all tests");

        var split_iter = std.mem.splitScalar(u8, r.stdout, '\n');

        while (split_iter.next()) |line| {
            if (line.len == 0) continue;

            const file_tests = b.addTest(.{
                .root_source_file = b.path(line),
                .target = target,
                .optimize = optimize,
            });

            if (b.args) |args| {
                file_tests.filters = args;
            }

            const run_file_tests = b.addRunArtifact(file_tests);
            run_file_tests.has_side_effects = true;
            run_all_tests.dependOn(&run_file_tests.step);
        }
    }
}
