//! Interned string storage owned by a graph.
//!
//! Every string reachable from an entity, an assertion, a diagnostic, or an
//! identity event lives here. Interning gives the graph one place that owns
//! text, so a published snapshot can borrow it instead of deep-copying, and so
//! a frontend's temporary buffers can be freed as soon as its batch is
//! integrated.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const StringPool = struct {
    gpa: Allocator,
    arena: std.heap.ArenaAllocator,
    set: std.StringHashMapUnmanaged(void),

    pub fn init(gpa: Allocator) StringPool {
        return .{
            .gpa = gpa,
            .arena = std.heap.ArenaAllocator.init(gpa),
            .set = .empty,
        };
    }

    pub fn deinit(self: *StringPool) void {
        self.set.deinit(self.gpa);
        self.arena.deinit();
        self.* = undefined;
    }

    pub fn allocator(self: *StringPool) Allocator {
        return self.arena.allocator();
    }

    pub fn intern(self: *StringPool, value: []const u8) Allocator.Error![]const u8 {
        if (self.set.getKey(value)) |existing| return existing;
        const owned = try self.arena.allocator().dupe(u8, value);
        try self.set.put(self.gpa, owned, {});
        return owned;
    }

    pub fn internOptional(self: *StringPool, value: ?[]const u8) Allocator.Error!?[]const u8 {
        return if (value) |v| try self.intern(v) else null;
    }

    pub fn internSlice(self: *StringPool, values: []const []const u8) Allocator.Error![]const []const u8 {
        if (values.len == 0) return &.{};
        const owned = try self.arena.allocator().alloc([]const u8, values.len);
        for (values, owned) |value, *slot| slot.* = try self.intern(value);
        return owned;
    }

    pub fn print(
        self: *StringPool,
        comptime fmt: []const u8,
        args: anytype,
    ) Allocator.Error![]const u8 {
        var buffer: std.ArrayList(u8) = .empty;
        defer buffer.deinit(self.gpa);
        try buffer.print(self.gpa, fmt, args);
        return self.intern(buffer.items);
    }
};

const testing = std.testing;

test "equal strings intern to one allocation" {
    var pool = StringPool.init(testing.allocator);
    defer pool.deinit();

    var buffer = "greet".*;
    const a = try pool.intern("greet");
    const b = try pool.intern(&buffer);
    try testing.expectEqualStrings("greet", a);
    try testing.expectEqual(a.ptr, b.ptr);
}

test "interned slices and formatted strings are owned by the pool" {
    var pool = StringPool.init(testing.allocator);
    defer pool.deinit();

    const containers = try pool.internSlice(&.{ "demo", "Greeter" });
    try testing.expectEqual(@as(usize, 2), containers.len);
    try testing.expectEqualStrings("Greeter", containers[1]);

    const signature = try pool.print("{s}({s})", .{ "greet", "" });
    try testing.expectEqualStrings("greet()", signature);
    try testing.expectEqual(signature.ptr, (try pool.intern("greet()")).ptr);
}
