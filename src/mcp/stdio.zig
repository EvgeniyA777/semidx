//! The stdio framing: one JSON-RPC message per line in, one per line out.
//!
//! The loop owns framing only. It never writes to `out` itself except through
//! the handler, and the handler writes whole lines, so nothing but protocol
//! messages can reach stdout from here.

const std = @import("std");
const Reader = std.Io.Reader;
const Writer = std.Io.Writer;

const protocol = @import("protocol.zig");

/// Serves lines from `in` until end of stream.
///
/// `handler` provides `handleLine(line, out)`, which writes zero or one complete
/// response line, and `oversized(out)`, which answers a message that exceeded
/// the reader's capacity. `in` must be buffered to at least
/// `protocol.max_message_bytes`.
pub fn serve(handler: anytype, in: *Reader, out: *Writer) !void {
    while (true) {
        const raw = in.takeDelimiter('\n') catch |err| switch (err) {
            error.StreamTooLong => {
                // The message is refused, and the rest of its line is skipped
                // so the next line is read as the next message.
                _ = in.discardDelimiterInclusive('\n') catch |discard_err| switch (discard_err) {
                    error.EndOfStream => {
                        try handler.oversized(out);
                        try out.flush();
                        return;
                    },
                    else => |e| return e,
                };
                try handler.oversized(out);
                try out.flush();
                continue;
            },
            else => |e| return e,
        } orelse return;

        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0) continue;
        try handler.handleLine(line, out);
        try out.flush();
    }
}

const testing = std.testing;

const EchoHandler = struct {
    lines: std.ArrayList([]u8) = .empty,
    oversized_count: usize = 0,

    fn handleLine(self: *EchoHandler, line: []const u8, out: *Writer) !void {
        try self.lines.append(testing.allocator, try testing.allocator.dupe(u8, line));
        try out.print("{{\"seen\":{d}}}\n", .{line.len});
    }

    fn oversized(self: *EchoHandler, out: *Writer) !void {
        self.oversized_count += 1;
        try out.writeAll("{\"oversized\":true}\n");
    }

    fn deinit(self: *EchoHandler) void {
        for (self.lines.items) |line| testing.allocator.free(line);
        self.lines.deinit(testing.allocator);
    }
};

test "lines are framed by newline, blank lines are skipped, and a final line needs no newline" {
    var in: Reader = .fixed("{\"a\":1}\r\n\n   \n{\"b\":2}");
    var out: Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    var handler: EchoHandler = .{};
    defer handler.deinit();

    try serve(&handler, &in, &out.writer);

    try testing.expectEqual(@as(usize, 2), handler.lines.items.len);
    try testing.expectEqualStrings("{\"a\":1}", handler.lines.items[0]);
    try testing.expectEqualStrings("{\"b\":2}", handler.lines.items[1]);
    try testing.expectEqualStrings("{\"seen\":7}\n{\"seen\":7}\n", out.written());
}

test "an oversized message is refused and the next line is still served" {
    const long = "x" ** 64;
    var backing: Reader = .fixed(long ++ "\n{\"ok\":1}\n" ++ long);
    var buffer: [16]u8 = undefined;
    var limited = backing.limited(.unlimited, &buffer);
    var out: Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    var handler: EchoHandler = .{};
    defer handler.deinit();

    try serve(&handler, &limited.interface, &out.writer);

    try testing.expectEqual(@as(usize, 2), handler.oversized_count);
    try testing.expectEqual(@as(usize, 1), handler.lines.items.len);
    try testing.expectEqualStrings("{\"ok\":1}", handler.lines.items[0]);
}

test {
    _ = protocol;
}
