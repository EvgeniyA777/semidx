//! `semidx-mcp`: the local MCP stdio preview server.
//!
//! stdout carries MCP messages and nothing else. Everything meant for a person
//! — usage, startup summary, failures — goes to stderr.

const std = @import("std");
const mcp = @import("semidx_mcp");

const usage =
    \\usage: semidx-mcp [--root <dir>] [--allow-evidence-text] [--version]
    \\                  [--enable-jev-ranking --jev-endpoint <https-url>
    \\                   --jev-model <versioned-id> --jev-send <categories>]
    \\
    \\Indexes <dir> (default: the current directory) into an in-memory semantic
    \\graph and serves it as an MCP server over stdio.
    \\
    \\  --root <dir>              source tree to index; result paths are relative to it
    \\  --allow-evidence-text     let tool results include the source text producers
    \\                            recorded as evidence, bounded per claim; off by default
    \\  --version                 print the product version to stdout and exit
    \\
    \\Optional Jev ranking projection (ADR 013; off by default, no outbound
    \\attempt unless all four inputs below are present and valid):
    \\  --enable-jev-ranking      advertise and allow semidx_rank_context
    \\  --jev-endpoint <url>      the exact consented HTTPS destination, e.g.
    \\                            https://api.typesafe.ai/v1/systemone
    \\  --jev-model <id>          a versioned model id, e.g. jev-1.13.0; moving
    \\                            aliases such as jev-latest are rejected
    \\  --jev-send <categories>   exactly "query-text,graph-metadata"
    \\  TYPESAFE_API_KEY          environment variable read only when
    \\                            --enable-jev-ranking is present
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

    var enable_jev_ranking = false;
    var jev_endpoint: []const u8 = "";
    var jev_model: []const u8 = "";
    var jev_send: []const u8 = "";

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
        } else if (std.mem.eql(u8, argument, "--enable-jev-ranking")) {
            enable_jev_ranking = true;
        } else if (std.mem.eql(u8, argument, "--jev-endpoint")) {
            jev_endpoint = arguments.next() orelse return fail(log, "--jev-endpoint needs a URL");
        } else if (std.mem.eql(u8, argument, "--jev-model")) {
            jev_model = arguments.next() orelse return fail(log, "--jev-model needs a versioned model id");
        } else if (std.mem.eql(u8, argument, "--jev-send")) {
            jev_send = arguments.next() orelse return fail(log, "--jev-send needs a comma-separated category list");
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

    if (enable_jev_ranking) {
        // Read the secret only now: never when the enable flag is absent, and
        // never logged, printed, or stored past this presence check.
        const key = init.environ_map.get("TYPESAFE_API_KEY");
        const key_present = if (key) |value| value.len > 0 else false;
        options.jev = mcp.jev_consent.validate(jev_endpoint, jev_model, jev_send, key_present) catch |err| {
            return fail(log, mcp.jev_consent.describe(err));
        };
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
    if (options.jev) |consent| {
        try log.print("semidx-mcp: Jev ranking is enabled; destination {s}, model {s}\n", .{ consent.origin, consent.model });
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
