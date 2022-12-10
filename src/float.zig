const std = @import("std");
const parser = @import("./parser.zig");
const testing = std.testing;

pub fn interpret(txt: []const u8) ?f64 {
    return std.fmt.parseFloat(f64, txt) catch return null;
}

fn testFloat(str: []const u8, expected: f64) !void {
    var x = testParse(str);
    try testing.expect(x == expected);
}

inline fn testParse(str: []const u8) f64 {
    return interpret(str).?;
}

test "float" {
    try testFloat("+1.0", 1.0);
    try testFloat("-0.001", -0.001);
    try testFloat("3.1415", 3.1415);

    try testFloat("5e+3", 5000.0);
    try testFloat("1e06", 1000000.0);
    try testFloat("-2E-2", -0.02);
    try testFloat("6.626e-3", 0.006626);

    try testFloat("224_617.445_991_228", 224_617.445_991_228);

    try std.testing.expect(std.math.isPositiveInf(testParse("inf")));
    try std.testing.expect(std.math.isPositiveInf(testParse("+inf")));
    try std.testing.expect(std.math.isNegativeInf(testParse("-inf")));

    try std.testing.expect(std.math.isNan(testParse("nan")));
    try std.testing.expect(std.math.isNan(testParse("+nan")));
    try std.testing.expect(std.math.isNan(testParse("-nan")));

    var x = interpret("123e");
    try testing.expect(x == null);
}
