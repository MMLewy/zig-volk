const std = @import("std");
const builtin = @import("builtin");
const zon = @import("build.zig.zon");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const version: std.SemanticVersion = try .parse(zon.version);

    const lib = b.addLibrary(.{
        .name = "volk",
        .linkage = .static,
        .version = version,
        .root_module = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true, .imports = &.{} }),
    });

    const c_common_files = [_][]const u8{"volk.c"};
    const volk_source = b.dependency("volk", .{});
    const os_tag = target.query.os_tag orelse builtin.os.tag;

    var vulkan_include: []u8 = undefined;

    if (findVulkan(b)) |path2| {
        vulkan_include = try std.mem.concat(b.allocator, u8, &.{ "-I", path2 });
    } else |err| {
        return err;
    }

    const c_flags: [3][]const u8 = switch (os_tag) {
        .windows => [_][]const u8{ "-DVK_USE_PLATFORM_WIN32_KHR", "-D_WIN32", vulkan_include },
        .macos => [_][]const u8{ "-DVK_USE_PLATFORM_MACOS_MVK", "-D__APPLE__", vulkan_include },
        .linux => [_][]const u8{ "-DVK_USE_PLATFORM_XLIB_KHR", "", vulkan_include },
        else => [_][]const u8{ "", "", vulkan_include },
    };
    lib.root_module.addCSourceFiles(.{ .root = volk_source.path(""), .files = &c_common_files, .flags = &c_flags });

    lib.installHeadersDirectory(volk_source.path(""), "", .{
        .include_extensions = &[_][]const u8{"volk.h"},
    });

    b.installArtifact(lib);
}

fn findVulkan(b: *std.Build) error{ VulkanNotFound, OutOfMemory }![]u8 {
    const path_env1: []const u8 = std.process.getEnvVarOwned(b.allocator, "VK_SDK_PATH") catch "";
    const path_env2: []const u8 = std.process.getEnvVarOwned(b.allocator, "VULKAN_SDK") catch "";

    const exe_path = b.findProgram(&.{"vkconfig"}, &.{ path_env1, path_env2 }) catch {
        return error.VulkanNotFound;
    };

    const relative_include_path = std.fs.path.join(b.allocator, &.{ std.fs.path.dirname(exe_path) orelse "", "..", "Include" }) catch {
        return error.OutOfMemory;
    };
    defer b.allocator.free(relative_include_path);

    const include_path = std.fs.cwd().realpathAlloc(b.allocator, relative_include_path) catch |err| {
        switch (err) {
            std.mem.Allocator.Error.OutOfMemory => return error.OutOfMemory,
            else => return error.VulkanNotFound,
        }
    };

    return include_path;
}
