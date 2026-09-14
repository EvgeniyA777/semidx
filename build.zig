const std = @import("std");

/// Local parser dependency locations resolved at configure time.
///
/// The slice keeps every parser dependency local and explicit: grammar C
/// sources come from a pinned local checkout produced by
/// `scripts/setup-tree-sitter-grammars.sh`, and the tree-sitter runtime comes
/// from a local install prefix. Nothing is fetched during a build or during
/// indexing.
const ParserDeps = struct {
    grammars_dir: []const u8,
    runtime_include: []const u8,
    runtime_lib: []const u8,
};

/// Grammar checkouts compiled into the full lane, by directory name under the
/// grammars directory. Each one is a pinned checkout from
/// `scripts/setup-tree-sitter-grammars.sh`.
const grammar_checkouts = [_][]const u8{ "tree-sitter-java", "tree-sitter-clojure", "tree-sitter-zig" };

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // `core` is the shared semantic model, the in-memory graph, the frontend
    // contract, and reconciliation. It must stay free of parser dependencies:
    // nothing below adds a C source file or include path to this module.
    const core = b.addModule("semidx_core", .{
        .root_source_file = b.path("src/core/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Source discovery owns the only filesystem access in the ingestion path.
    // It reads `core/model` for value vocabulary and nothing else from the core,
    // and nothing in the core reads it back.
    const source = b.addModule("semidx_source", .{
        .root_source_file = b.path("src/source/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "semidx_core", .module = core },
        },
    });

    const core_tests = b.addTest(.{ .root_module = core });
    const run_core_tests = b.addRunArtifact(core_tests);
    const source_tests = b.addTest(.{ .root_module = source });
    const run_source_tests = b.addRunArtifact(source_tests);

    const core_test_step = b.step("test-core", "Run every lane that needs no parser: shared core and source ingestion");
    core_test_step.dependOn(&run_core_tests.step);
    core_test_step.dependOn(&run_source_tests.step);

    const test_step = b.step("test", "Run the full test lane");
    test_step.dependOn(&run_core_tests.step);
    test_step.dependOn(&run_source_tests.step);

    const deps = resolveParserDeps(b) orelse {
        const fail = b.addFail(
            \\tree-sitter parser dependencies were not found locally.
            \\
            \\The vertical slice needs two local dependencies:
            \\  1. pinned grammar sources: run ./scripts/setup-tree-sitter-grammars.sh
            \\     (override the location with -Dgrammars-dir=<path> or
            \\      SEMIDX_TREE_SITTER_GRAMMARS_DIR)
            \\  2. a tree-sitter runtime with tree_sitter/api.h and libtree-sitter.a
            \\     (override the prefix with -Dtree-sitter-prefix=<path> or
            \\      SEMIDX_TREE_SITTER_PREFIX)
            \\
            \\`zig build test-core` still runs without either of them.
        );
        test_step.dependOn(&fail.step);
        return;
    };

    // The tree-sitter adapter is the only module that sees the C ABI.
    const tree_sitter = b.addModule("semidx_tree_sitter", .{
        .root_source_file = b.path("src/frontend/tree_sitter.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    addParserDeps(b, tree_sitter, deps);

    const frontends = b.addModule("semidx_frontends", .{
        .root_source_file = b.path("src/frontends/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "semidx_core", .module = core },
            .{ .name = "semidx_tree_sitter", .module = tree_sitter },
        },
    });

    const semidx = b.addModule("semidx", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "semidx_core", .module = core },
            .{ .name = "semidx_tree_sitter", .module = tree_sitter },
            .{ .name = "semidx_frontends", .module = frontends },
            .{ .name = "semidx_source", .module = source },
        },
    });

    const ts_tests = b.addTest(.{ .root_module = tree_sitter });
    const run_ts_tests = b.addRunArtifact(ts_tests);
    test_step.dependOn(&run_ts_tests.step);

    const frontend_tests = b.addTest(.{ .root_module = frontends });
    const run_frontend_tests = b.addRunArtifact(frontend_tests);
    test_step.dependOn(&run_frontend_tests.step);

    // Fixture and reconciliation tests read source from the repository, so the
    // fixture root is passed in rather than discovered from the cwd.
    const options = b.addOptions();
    options.addOption([]const u8, "fixtures_dir", b.pathFromRoot("fixtures/vertical-slice"));

    const slice_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/vertical_slice_test.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "semidx", .module = semidx },
                .{ .name = "semidx_core", .module = core },
                .{ .name = "build_options", .module = options.createModule() },
            },
        }),
    });
    const run_slice_tests = b.addRunArtifact(slice_tests);
    test_step.dependOn(&run_slice_tests.step);

    // Developer-only inspection command. It is not a public contract and no
    // test asserts against its output.
    const exe = b.addExecutable(.{
        .name = "semidx-dev",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "semidx", .module = semidx },
                .{ .name = "semidx_core", .module = core },
            },
        }),
    });
    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);
    run_exe.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_exe.addArgs(args);
    const run_step = b.step("run", "Run the developer-only graph inspection command");
    run_step.dependOn(&run_exe.step);
}

fn addParserDeps(b: *std.Build, module: *std.Build.Module, deps: ParserDeps) void {
    module.addIncludePath(.{ .cwd_relative = deps.runtime_include });
    module.addObjectFile(.{ .cwd_relative = deps.runtime_lib });

    for (grammar_checkouts) |grammar| {
        const src_dir = b.pathJoin(&.{ deps.grammars_dir, grammar, "src" });
        module.addIncludePath(.{ .cwd_relative = src_dir });
        module.addCSourceFile(.{
            .file = .{ .cwd_relative = b.pathJoin(&.{ src_dir, "parser.c" }) },
            .flags = &.{ "-std=c11", "-fno-sanitize=undefined" },
        });
    }
}

fn resolveParserDeps(b: *std.Build) ?ParserDeps {
    const grammars_dir = b.option(
        []const u8,
        "grammars-dir",
        "Directory holding pinned tree-sitter grammar checkouts",
    ) orelse b.graph.environ_map.get("SEMIDX_TREE_SITTER_GRAMMARS_DIR") orelse
        b.pathFromRoot(".tree-sitter-grammars");

    for (grammar_checkouts) |grammar| {
        if (!fileExists(b, b.pathJoin(&.{ grammars_dir, grammar, "src", "parser.c" }))) return null;
    }

    const configured_prefix = b.option(
        []const u8,
        "tree-sitter-prefix",
        "Install prefix of the tree-sitter runtime (expects include/ and lib/)",
    ) orelse b.graph.environ_map.get("SEMIDX_TREE_SITTER_PREFIX");

    const candidates: []const []const u8 = if (configured_prefix) |prefix|
        &.{prefix}
    else
        &.{ "/opt/homebrew", "/usr/local", "/usr" };

    for (candidates) |prefix| {
        const include = b.pathJoin(&.{ prefix, "include" });
        const lib = b.pathJoin(&.{ prefix, "lib", "libtree-sitter.a" });
        if (fileExists(b, b.pathJoin(&.{ include, "tree_sitter", "api.h" })) and fileExists(b, lib)) {
            return .{
                .grammars_dir = grammars_dir,
                .runtime_include = include,
                .runtime_lib = lib,
            };
        }
    }

    return null;
}

fn fileExists(b: *std.Build, path: []const u8) bool {
    std.Io.Dir.cwd().access(b.graph.io, path, .{}) catch return false;
    return true;
}
