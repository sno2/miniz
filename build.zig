const std = @import("std");

const version: std.SemanticVersion = .{ .major = 3, .minor = 1, .patch = 0 };

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const linkage = b.option(std.builtin.LinkMode, "linkage", "Link mode") orelse .static;
    const strip = b.option(bool, "strip", "Omit debug information");
    const pic = b.option(bool, "pie", "Produce Position Independent Code");

    const enable_tests = b.option(bool, "enable_tests", "Enable tests") orelse false;
    const enable_examples = b.option(bool, "enable_examples", "Enable examples") orelse false;

    const no_stdio = b.option(bool, "no_stdio", "Disable stdio for file I/O") orelse false;
    const no_time = b.option(bool, "no_time", "Disable time") orelse false;
    const no_deflate = b.option(bool, "no_deflate", "Disable decompression APIs") orelse false;
    const no_inflate = b.option(bool, "no_inflate", "Disable compression APIs") orelse false;
    const no_archive = b.option(bool, "no_archive", "Disable ZIP archive APIs") orelse false;
    const no_archive_writing = b.option(bool, "no_archive_writing", "Disable ZIP writing archives APIs") orelse false;
    const no_zlib = b.option(bool, "no_zlib", "Disable zlib-style APIs") orelse false;
    const no_zlib_compatible_names = b.option(bool, "no_zlib_compatible_names", "Disable zlib names") orelse false;

    const upstream = b.dependency("miniz", .{});

    const miniz_export = b.addConfigHeader(.{ .include_path = "miniz_export.h" }, .{
        .MINIZ_NO_STDIO = if (no_stdio) true else null,
        .MINIZ_NO_TIME = if (no_time) true else null,
        .MINIZ_NO_DEFLATE_APIS = if (no_deflate) true else null,
        .MINIZ_NO_INFLATE_APIS = if (no_inflate) true else null,
        .MINIZ_NO_ARCHIVE_APIS = if (no_archive) true else null,
        .MINIZ_NO_ARCHIVE_WRITING_APIS = if (no_archive_writing) true else null,
        .MINIZ_NO_ZLIB_APIS = if (no_zlib) true else null,
        .MINIZ_NO_ZLIB_COMPATIBLE_NAMES = if (no_zlib_compatible_names) true else null,
    });
    if (target.result.os.tag == .windows and linkage == .dynamic) {
        miniz_export.addValue("MINIZ_EXPORT", enum { @"__declspec(dllexport)" }, .@"__declspec(dllexport)");
    } else {
        miniz_export.addValue("MINIZ_EXPORT", void, {});
    }

    const miniz_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .strip = strip,
        .pic = pic,
    });
    miniz_mod.addConfigHeader(miniz_export);
    miniz_mod.addIncludePath(upstream.path("."));
    miniz_mod.addCSourceFiles(.{
        .root = upstream.path("."),
        .files = &.{
            "miniz.c",
            "miniz_zip.c",
            "miniz_tinfl.c",
            "miniz_tdef.c",
        },
        .flags = &.{"-std=c90"},
    });

    const miniz = b.addLibrary(.{
        .name = "miniz",
        .linkage = linkage,
        .root_module = miniz_mod,
        .version = version,
    });
    miniz.installConfigHeader(miniz_export);
    miniz.installHeadersDirectory(upstream.path("."), "", .{
        .exclude_extensions = &.{"tests/timer.h"},
    });
    b.installArtifact(miniz);

    const test_step = b.step("test", "Run tests");
    if (enable_tests) {
        const miniz_tester_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libcpp = true,
        });
        miniz_tester_mod.linkLibrary(miniz);
        miniz_tester_mod.addCSourceFiles(.{
            .root = upstream.path("tests"),
            .files = &.{
                "miniz_tester.cpp",
                "timer.cpp",
            },
            .flags = &.{
                "-std=c++20",
                "-D__DATE__=\"(date omitted)\"",
                "-D__TIME__=\"(time omitted)\"",
            },
        });

        const miniz_tester = b.addExecutable(.{
            .name = "miniz_tester",
            .root_module = miniz_tester_mod,
        });

        if (b.lazyDependency("testfile", .{})) |testfile| {
            const configurations: []const []const []const u8 = &.{
                &.{"-v"},
                &.{ "-v", "-r" },
                &.{ "-v", "-b", "-r" },
                &.{ "-v", "-a" },
            };

            var maybe_before: ?*std.Build.Step = null;
            for (configurations) |configuration| {
                const run_test = b.addRunArtifact(miniz_tester);
                if (maybe_before) |before| run_test.step.dependOn(before);
                maybe_before = &run_test.step;
                run_test.setName(b.fmt("miniz_tester {s}", .{configuration}));
                run_test.addArgs(configuration);
                run_test.addArg("a");
                run_test.addDirectoryArg(testfile.path("src"));
                run_test.expectExitCode(0);

                test_step.dependOn(&run_test.step);
            }
        }
    } else {
        try test_step.addError("-Denable_tests is required to run tests", .{});
    }

    if (enable_examples) {
        const example_sources: []const []const u8 = &.{
            "example1.c",
            "example2.c",
            "example3.c",
            "example4.c",
            "example5.c",
            "example6.c",
        };

        for (example_sources) |example_source| {
            const example_mod = b.createModule(.{
                .target = target,
                .optimize = optimize,
            });
            example_mod.linkLibrary(miniz);
            example_mod.addCSourceFile(.{
                .file = upstream.path("examples").path(b, example_source),
                .flags = &.{"-std=c90"},
            });

            const example = b.addExecutable(.{
                .name = std.fs.path.stem(example_source),
                .root_module = example_mod,
            });
            b.installArtifact(example);
        }
    }
}
