const std = @import("std");
const builtin = @import("builtin");
const zon = @import("build.zig.zon");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const version: std.SemanticVersion = try .parse(zon.version);
    const volk_source = b.dependency("volk", .{});
    const os_tag = target.query.os_tag orelse builtin.os.tag;

    const volk = b.addTranslateC(.{
        .root_source_file = volk_source.path("volk.h"),
        .optimize = optimize,
        .target = target,
    });

    const volk_mod = volk.addModule("volk");

    var vulkan_include: std.Build.LazyPath = undefined;

    if (findVulkan(b)) |path| {
        vulkan_include = .{ .cwd_relative = path };
    } else |err| {
        return err;
    }

    volk.addIncludePath(vulkan_include);
    volk_mod.addIncludePath(vulkan_include);

    switch (os_tag) {
        .windows => {
            volk.defineCMacro("VK_USE_PLATFORM_WIN32_KHR", "1");
            volk.defineCMacro("_WIN32", "1");
            volk_mod.addCMacro("VK_USE_PLATFORM_WIN32_KHR", "1");
            volk_mod.addCMacro("_WIN32", "1");
        },

        .macos => {
            volk.defineCMacro("DVK_USE_PLATFORM_MACOS_MVK", "1");
            volk.defineCMacro("D__APPLE__", "1");
            volk_mod.addCMacro("DVK_USE_PLATFORM_MACOS_MVK", "1");
            volk_mod.addCMacro("D__APPLE__", "1");
        },

        .linux => {
            volk.defineCMacro("DVK_USE_PLATFORM_XLIB_KHR", "1");
            volk_mod.addCMacro("DVK_USE_PLATFORM_XLIB_KHR", "1");
        },

        else => {},
    }

    volk_mod.addCSourceFiles(.{ .root = volk_source.path(""), .files = &.{"volk.c"}, .flags = &.{} });

    const volk_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "volk",
        .version = version,
        .root_module = volk_mod,
    });

    b.installArtifact(volk_lib);
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
