//! Provider unit for the local-import fixture: the file namespace that
//! `@import("wire.zig")` in `session.zig` names.

pub fn writeText(text: []const u8) usize {
    return text.len;
}

fn hidden() void {}

pub fn twice() void {}

pub const twice = 2;

pub const Frame = struct {
    size: usize,

    pub fn encode(self: Frame) usize {
        return self.size;
    }
};
