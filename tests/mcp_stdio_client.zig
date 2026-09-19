//! A test client that drives a built `semidx-mcp` executable over its real
//! stdin and stdout, with stderr captured to a file.
//!
//! Every wait is bounded: a server that stops answering or does not exit is
//! killed, and the test fails naming what it waited for instead of hanging.

const std = @import("std");

const testing = std.testing;
const io = testing.io;
pub const Value = std.json.Value;

pub const modern_meta = "\"_meta\":{\"io.modelcontextprotocol/protocolVersion\":\"2026-07-28\"," ++
    "\"io.modelcontextprotocol/clientCapabilities\":{},\"io.modelcontextprotocol/clientInfo\":{\"name\":\"smoke\",\"version\":\"1\"}}";

/// How long a client waits for one response, and for the process to exit
/// after its input closes. Generous: in a Debug build a response over the tiny
/// fixture root takes milliseconds and the first response over a copy of this
/// repository under 200 ms, and the executable is already built when a test
/// runs, so the bound never includes compilation.
/// Exceeding it means the server hangs, and the test fails instead of the
/// release gate hanging with it.
pub const response_timeout_seconds = 30;

fn deadline() std.Io.Timeout {
    const timeout: std.Io.Timeout = .{ .duration = .{ .raw = .fromSeconds(response_timeout_seconds), .clock = .awake } };
    return timeout.toDeadline(io);
}

pub const Client = struct {
    gpa: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    child: std.process.Child,
    /// Where the server's stderr is captured, reported when it hangs.
    log_dir: std.Io.Dir,
    stdin_buffer: [4096]u8,
    stdin_writer: std.Io.File.Writer,
    stdout_streams: std.Io.File.MultiReader.Buffer(1),
    stdout: std.Io.File.MultiReader,
    /// Every line the server wrote to stdout.
    transcript: std.ArrayList(u8),

    /// Starts `exe --root <root>` followed by `extra_args`. The server writes
    /// its stderr to `stderr_file`, which must be `stderr.log` in `log_dir`.
    pub fn start(
        gpa: std.mem.Allocator,
        exe: []const u8,
        root: []const u8,
        extra_args: []const []const u8,
        log_dir: std.Io.Dir,
        stderr_file: std.Io.File,
    ) !*Client {
        const self = try gpa.create(Client);
        errdefer gpa.destroy(self);
        self.gpa = gpa;
        self.arena = .init(gpa);
        errdefer self.arena.deinit();
        self.transcript = .empty;
        self.log_dir = log_dir;
        const argv = try std.mem.concat(self.arena.allocator(), []const u8, &.{ &.{ exe, "--root", root }, extra_args });
        self.child = try std.process.spawn(io, .{
            .argv = argv,
            .stdin = .pipe,
            .stdout = .pipe,
            .stderr = .{ .file = stderr_file },
        });
        self.stdin_writer = self.child.stdin.?.writer(io, &self.stdin_buffer);
        self.stdout.init(gpa, io, self.stdout_streams.toStreams(), &.{self.child.stdout.?});
        return self;
    }

    pub fn destroy(self: *Client) void {
        if (self.child.id != null) self.killAndReap();
        self.stdout.deinit();
        if (self.child.stdout) |file| file.close(io);
        if (self.child.stdin) |file| file.close(io);
        self.transcript.deinit(self.gpa);
        self.arena.deinit();
        self.gpa.destroy(self);
    }

    fn killAndReap(self: *Client) void {
        const pid = self.child.id.?;
        std.posix.kill(pid, .KILL) catch |err| std.debug.print("killing semidx-mcp failed: {t}\n", .{err});
        var status: c_int = 0;
        _ = std.c.waitpid(pid, &status, 0);
        self.child.id = null;
    }

    /// Fails the test the way a hang should: kill the server, say what was
    /// awaited, and show what it wrote to stderr.
    fn hung(self: *Client, awaited: []const u8) error{ServerTimedOut} {
        self.killAndReap();
        const stderr_text = self.log_dir.readFileAlloc(io, "stderr.log", self.arena.allocator(), .limited(1 << 20)) catch "<stderr unreadable>";
        std.debug.print(
            "semidx-mcp did not produce {s} within {d}s and was killed; its stderr:\n{s}\n",
            .{ awaited, response_timeout_seconds, stderr_text },
        );
        return error.ServerTimedOut;
    }

    pub fn sendLine(self: *Client, line: []const u8) !void {
        try self.stdin_writer.interface.writeAll(line);
        try self.stdin_writer.interface.writeByte('\n');
        try self.stdin_writer.interface.flush();
    }

    /// Reads one stdout line, waiting at most the response timeout.
    pub fn readLine(self: *Client, awaited: []const u8) ![]const u8 {
        const until = deadline();
        const reader = self.stdout.reader(0);
        while (true) {
            const buffered = reader.buffered();
            if (std.mem.indexOfScalar(u8, buffered, '\n')) |end| {
                const line = try self.arena.allocator().dupe(u8, buffered[0..end]);
                reader.toss(end + 1);
                try self.transcript.appendSlice(self.gpa, line);
                try self.transcript.append(self.gpa, '\n');
                return line;
            }
            self.stdout.fill(64 * 1024, until) catch |err| switch (err) {
                error.Timeout => return self.hung(awaited),
                error.EndOfStream => return error.ServerClosedStdout,
                else => |e| return e,
            };
        }
    }

    /// Reads one stdout line and requires it to be a JSON-RPC response to `id`.
    pub fn receive(self: *Client, id: i64, awaited: []const u8) !Value {
        const line = try self.readLine(awaited);
        const arena = self.arena.allocator();
        const value = std.json.parseFromSliceLeaky(Value, arena, line, .{}) catch |err| {
            std.debug.print("non-protocol stdout line: {s}\n", .{line});
            return err;
        };
        try testing.expectEqualStrings("2.0", value.object.get("jsonrpc").?.string);
        try testing.expectEqual(id, value.object.get("id").?.integer);
        return value;
    }

    pub fn request(self: *Client, id: i64, method: []const u8, params: []const u8) !Value {
        const arena = self.arena.allocator();
        const line = try std.fmt.allocPrint(arena, "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"{s}\",\"params\":{s}}}", .{ id, method, params });
        try self.sendLine(line);
        return self.receive(id, try std.fmt.allocPrint(arena, "a response to request {d} ({s})", .{ id, method }));
    }

    pub fn callTool(self: *Client, id: i64, name: []const u8, arguments: []const u8) !std.json.ObjectMap {
        const params = try std.fmt.allocPrint(self.arena.allocator(), "{{{s},\"name\":\"{s}\",\"arguments\":{s}}}", .{ modern_meta, name, arguments });
        const response = try self.request(id, "tools/call", params);
        const result = response.object.get("result").?.object;
        try testing.expectEqualStrings("complete", result.get("resultType").?.string);
        try testing.expect(!result.get("isError").?.bool);
        return result.get("structuredContent").?.object;
    }

    /// Closes the server's input and returns everything it wrote to stdout
    /// afterwards and its exit status, each within the timeout.
    pub fn shutdown(self: *Client) !struct { trailing: []const u8, exit_code: u8 } {
        self.child.stdin.?.close(io);
        self.child.stdin = null;

        const until = deadline();
        while (true) {
            self.stdout.fill(64 * 1024, until) catch |err| switch (err) {
                error.EndOfStream => break,
                error.Timeout => return self.hung("end of stdout after its input closed"),
                else => |e| return e,
            };
        }
        const trailing = try self.arena.allocator().dupe(u8, self.stdout.reader(0).buffered());

        const pid = self.child.id.?;
        var status: c_int = 0;
        while (true) {
            const reaped = std.c.waitpid(pid, &status, std.c.W.NOHANG);
            if (reaped == pid) break;
            if (reaped < 0) return error.WaitFailed;
            const remaining = until.toDurationFromNow(io) orelse unreachable;
            if (remaining.raw.nanoseconds <= 0) return self.hung("an exit after its input closed");
            try io.sleep(.fromMilliseconds(10), .awake);
        }
        self.child.id = null;
        const raw: u32 = @bitCast(status);
        if (!std.c.W.IFEXITED(raw)) return error.ServerDidNotExitNormally;
        return .{ .trailing = trailing, .exit_code = std.c.W.EXITSTATUS(raw) };
    }
};
