const std = @import("std");
const parser = @import("./parser.zig");
const testing = std.testing;

fn isIntChar(c: u8) bool {
    switch (c) {
        '0'...'9', '-', '+' => return true,
        else => return false,
    }
}

pub fn parse(ctx: *parser.Context) !?i64 {
    var txt = parser.takeWhile(ctx, isIntChar);
    if (txt.len == 0) return null;
    return try std.fmt.parseInt(i64, txt, 0);
}

test "int" {
    var ctx = parser.testInput("123");
    var int = try parse(&ctx);
    try testing.expect(int.? == 123);

    ctx = parser.testInput("-123");
    int = try parse(&ctx);
    try testing.expect(int.? == -123);

    ctx = parser.testInput("+123");
    int = try parse(&ctx);
    try testing.expect(int.? == 123);
}

// TODO: underscores in ints
// TODO: hex numbers
// TODO: octal numbers
// TODO: binary numbers
