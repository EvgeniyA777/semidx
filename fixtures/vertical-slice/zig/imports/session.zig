//! Importer unit for the local-import fixture. Plan 006 expects exactly two
//! cross-unit call facts from `run` (to `wire.writeString` and
//! `util.clean`), one from the member `Session.send`, and every other
//! qualified call to stay unresolved with its reason.

const std = @import("std");
const wire = @import("wire.zig");
const util = @import("./support/../support/util.zig");
const outside = @import("../../../outside.zig");
const upper = @import("Wire.zig");
const absent = @import("absent.zig");
const twin = @import("wire.zig");
const twin = @import("support/util.zig");
const copy = wire;

pub const Session = struct {
    sent: usize,

    pub fn send(self: *Session, text: []const u8) void {
        self.sent += wire.writeString(text);
        self.flush();
    }

    fn flush(self: *Session) void {
        _ = self;
        helper();
        reset();
    }

    fn reset() void {}

    pub const Nested = struct {
        count: u8,

        fn deep() void {
            helper();
        }
    };
};

fn helper() void {}

pub fn run(text: []const u8) usize {
    const total = wire.writeString(text);
    wire.hidden();
    wire.twice();
    wire.flushAll();
    _ = wire.Frame.encode(undefined);
    std.debug.print("{d}\n", .{total});
    util.clean();
    outside.run();
    upper.run();
    absent.run();
    twin.run();
    _ = copy.writeString(text);
    return total;
}

pub fn shadowed(wire: anytype) void {
    _ = wire.writeString("x");
}
