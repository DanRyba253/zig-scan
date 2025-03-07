const std = @import("std");

pub fn build(b: *std.Build) void {
    // source directory
    const src_dir = "src";

    // build options for the library
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    _ = b.addModule("zig_scan", .{
        .root_source_file = b.path(src_dir ++ "/zig_scan.zig"),
    });

    // try to generate test step
    generate_test_step: {
        var src = std.fs.cwd().openDir(src_dir, .{
            .iterate = true,
        }) catch break :generate_test_step;
        defer src.close();

        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const allocator = gpa.allocator();

        var walker = src.walk(allocator) catch break :generate_test_step;
        defer walker.deinit();

        const run_all_tests = b.step("test", "Run all tests");

        while (walker.next() catch break :generate_test_step) |entry| {
            if (entry.kind != .file) continue;

            if (std.mem.endsWith(u8, entry.basename, ".zig")) {
                const path_len = src_dir.len + 1 + entry.path.len;
                var path = allocator.alloc(u8, path_len) catch break :generate_test_step;
                defer allocator.free(path);

                std.mem.copyForwards(u8, path, src_dir);
                path[src_dir.len] = std.fs.path.sep;
                std.mem.copyForwards(u8, path[src_dir.len + 1 ..], entry.path);

                const file_tests = b.addTest(.{
                    .root_source_file = b.path(path),
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
}
