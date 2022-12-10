const std = @import("std");
const parser = @import("./parser.zig");
const testing = std.testing;

pub fn interpret(txt: []const u8) ?i64 {
    return std.fmt.parseInt(i64, txt, 0) catch return null;
}

fn testInt(str: []const u8, expected: i64) !void {
    var x = interpret(str).?;
    try testing.expect(x == expected);
}

test "int" {
    try testInt("123", 123);
    try testInt("+123", 123);
    try testInt("-123", -123);
    try testInt("1_123", 1123);
    try testInt("53_49_221", 53_49_221);
    try testInt("0xDEADBEEF", 0xDEADBEEF);
    try testInt("0xdeadbeef", 0xdeadbeef);
    try testInt("0xdead_beef", 0xdead_beef);
    try testInt("0o01234567", 0o01234567);
    try testInt("0b11010110", 0b11010110);
}
