const std = @import("std");
const testing = std.testing;

const Self = @This();

buffer: []const u8,
position: usize,

pub fn init(content: []const u8) Self {
    return .{
        .buffer = content,
        .position = 0,
    };
}

fn getCharAt(self: *const Self, pos: usize) !?u8 {
    if (pos < 0) {
        @panic("index out of range");
    }
    if (pos >= self.buffer.len) {
        return null;
    }
    return self.buffer[pos];
}

pub fn current(self: *const Self) !?u8 {
    return self.getCharAt(self.position);
}

pub fn next(self: *Self) !?u8 {
    self.position += 1;
    return self.current();
}

pub fn lookahead(self: *const Self, count: usize) !?u8 {
    return self.getCharAt(self.position + count);
}

fn skipAny(self: *Self, chars: []const u8) !void {
    while (true) {
        var cur = try self.current();
        if (cur == null) return;
        var found = false;
        for (chars) |c| {
            if (cur == c) {
                self.position += 1;
                found = true;
                break;
            }
        }
        if (!found) return;
    }
}

pub fn skipSpaces(self: *Self) !void {
    return self.skipAny(" \t");
}

pub fn skipSpacesAndLineBreaks(self: *Self) !void {
    return self.skipAny(" \t\r\n");
}

test "skip spaces" {
    var src = init("    \th ");
    try testing.expect((try src.current()).? == ' ');
    try src.skipSpaces();
    try testing.expect((try src.current()).? == 'h');
    try src.skipSpaces();
    try testing.expect((try src.current()).? == 'h');
    _ = try src.next();
    try src.skipSpaces();
    try testing.expect(try src.current() == null);
}

test "skip lines " {
    var src = init("    \t\n   \r\n  hello ");
    try testing.expect((try src.current()).? == ' ');
    try src.skipSpacesAndLineBreaks();
    try testing.expect((try src.current()).? == 'h');
}
