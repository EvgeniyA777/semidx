//! `semidx-mcp`: the local MCP stdio preview server.
//!
//! stdout carries MCP messages and nothing else. Everything meant for a person
//! — usage, startup summary, failures — goes to stderr.

const std = @import("std");
const mcp = @import("semidx_mcp");

const usage =
    \\usage: semidx-mcp [--root <dir>] [--allow-evidence-text] [--version]
    \\
    \\Indexes <dir> (default: the current directory) into an in-memory semantic
    \\graph and serves it as an MCP server over stdio.
    \\
    \\  --root <dir>              source tree to index; result paths are relative to it
    \\  --allow-evidence-text     let tool results include the source text producers
    \\                            recorded as evidence, bounded per claim; off by default
    \\  --version                 print the product version to stdout and exit
    \\
;

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var stderr_buffer: [4096]u8 = undefined;
    var stderr = std.Io.File.stderr().writer(io, &stderr_buffer);
    const log = &stderr.interface;

    var options: mcp.Options = .{ .root = "." };
    var root_owned: ?[]u8 = null;
    defer if (root_owned) |root| gpa.free(root);

    var arguments = init.minimal.args.iterate();
    defer arguments.deinit();
    _ = arguments.skip();
    while (arguments.next()) |argument| {
        if (std.mem.eql(u8, argument, "--root")) {
            const root = arguments.next() orelse return fail(log, "--root needs a directory");
            if (root_owned) |previous| gpa.free(previous);
            root_owned = try gpa.dupe(u8, root);
            options.root = root_owned.?;
        } else if (std.mem.eql(u8, argument, "--allow-evidence-text")) {
            options.evidence_text = true;
        } else if (std.mem.eql(u8, argument, "--version")) {
            // Not serving, so stdout is free: a version belongs where scripts
            // read it.
            var stdout_buffer: [128]u8 = undefined;
            var stdout = std.Io.File.stdout().writer(io, &stdout_buffer);
            try stdout.interface.print("semidx-mcp {s}\n", .{mcp.protocol.product_version});
            try stdout.interface.flush();
            return;
        } else if (std.mem.eql(u8, argument, "--help") or std.mem.eql(u8, argument, "-h")) {
            try log.writeAll(usage);
            try log.flush();
            return;
        } else {
            try log.print("semidx-mcp: unknown argument {s}\n", .{argument});
            return fail(log, null);
        }
    }

    var server = mcp.Server.init(gpa, io, options, log) catch |err| {
        try log.print("semidx-mcp: could not index {s}: {t}\n", .{ options.root, err });
        try log.flush();
        std.process.exit(1);
    };
    defer server.deinit();
    if (options.evidence_text) {
        try log.print("semidx-mcp: evidence text is enabled for {s}\n", .{options.root});
        try log.flush();
    }

    const stdin_buffer = try gpa.alloc(u8, mcp.protocol.max_message_bytes);
    defer gpa.free(stdin_buffer);
    var stdin = std.Io.File.stdin().reader(io, stdin_buffer);
    var stdout_buffer: [64 * 1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(io, &stdout_buffer);

    try server.serve(&stdin.interface, &stdout.interface);
    try log.print("semidx-mcp: input closed; exiting\n", .{});
    try log.flush();
}

fn fail(log: *std.Io.Writer, message: ?[]const u8) !void {
    if (message) |text| try log.print("semidx-mcp: {s}\n", .{text});
    try log.writeAll(usage);
    try log.flush();
    std.process.exit(2);
}
