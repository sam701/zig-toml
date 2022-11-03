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

fn getCharAt(self: *const Self, pos: usize) ?u8 {
    if (pos < 0) {
        @panic("index out of range");
    }
    if (pos >= self.buffer.len) {
        return null;
    }
    return self.buffer[pos];
}

pub inline fn current(self: *const Self) ?u8 {
    return self.getCharAt(self.position);
}

pub inline fn next(self: *Self) !?u8 {
    self.position += 1;
    return self.current();
}

pub fn lookahead(self: *const Self, count: usize) !?u8 {
    return self.getCharAt(self.position + count);
}

fn skipAny(self: *Self, chars: []const u8) !void {
    while (true) {
        var cur = self.current();
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

fn isSpace(x: u8) bool {
    return x == ' ' or x == '\t';
}

pub fn skipSpaces(self: *Self) !void {
    _ = try self.takeWhile(isSpace);
}

pub fn skipSpacesAndLineBreaks(self: *Self) !void {
    _ = try self.takeWhile(std.ascii.isWhitespace);
}

test "skip spaces" {
    var src = init("    \th ");
    try testing.expect(src.current().? == ' ');
    try src.skipSpaces();
    try testing.expect(src.current().? == 'h');
    try src.skipSpaces();
    try testing.expect(src.current().? == 'h');
    _ = try src.next();
    try src.skipSpaces();
    try testing.expect(src.current() == null);
}

test "skip lines " {
    var src = init("    \t\n   \r\n  hello ");
    try testing.expect(src.current().? == ' ');
    try src.skipSpacesAndLineBreaks();
    try testing.expect(src.current().? == 'h');
}

pub fn takeWhile(self: *Self, comptime tester: fn (u8) bool) ![]const u8 {
    var start = self.position;
    while (true) {
        if (self.current()) |cur| {
            if (tester(cur)) {
                self.position += 1;
            } else {
                break;
            }
        } else {
            break;
        }
    }
    return self.buffer[start..self.position];
}

fn isA(x: u8) bool {
    return x == 'a';
}

test "takeWhile 1" {
    var src = init("aaabc");
    var a3 = try src.takeWhile(isA);
    try testing.expect(std.mem.eql(u8, a3, "aaa"));
    try testing.expect(src.current().? == 'b');
}

test "takeWhile 2" {
    var src = init("aaa");
    var a3 = try src.takeWhile(isA);
    try testing.expect(std.mem.eql(u8, a3, "aaa"));
    try testing.expect(src.current() == null);
}
