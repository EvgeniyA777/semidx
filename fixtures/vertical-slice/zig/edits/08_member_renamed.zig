//! Zig fixture for the vertical slice.

const std = @import("std");

pub const Greeter = struct {
    name: []const u8,

    pub fn welcome(self: Greeter) []const u8 {
        return self.name;
    }
};

pub const Mood = enum { calm, loud };

const limit: usize = 3;

fn greeting() []const u8 {
    return "hello";
}

pub fn greet() []const u8 {
    return greeting();
}

pub fn announce(greeter: Greeter) void {
    std.debug.print("{s}\n", .{greet()});
    _ = greeter.greet();
    report();
}

test "greets" {
    _ = greet();
}
