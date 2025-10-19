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
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    b.installArtifact(lib);
}
