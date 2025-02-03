const std = @import("std");
const testing = std.testing;
const parser = @import("parser");
const Context = parser.Context;

fn contains(c: u8, allowed: []const u8) bool {
    for (allowed) |a| {
        if (a == c) return true;
    }
    return false;
}

fn skipAny(ctx: *Context, chars: []const u8) void {
    while (ctx.current()) |c| {
        if (!contains(c, chars)) return;
        _ = ctx.next();
    }
}

pub fn skipSpaces(ctx: *Context) void {
    skipAny(ctx, " \t");
}

pub fn skipSpacesAndLineBreaks(ctx: *Context) void {
    skipAny(ctx, " \t\r\n");
}

pub fn consumeNewLine(ctx: *Context) !void {
    var cnt: usize = 0;
    while (ctx.current()) |cur| {
        switch (cur) {
            '\r' => {
                if (cnt > 0) return error.UnexpectedToken;
                _ = ctx.next();
                cnt += 1;
            },
            '\n' => return,
            else => return error.UnexpectedToken,
        }
    }
    return error.UnexpectedToken;
}

test "new line" {
    var ctx = parser.testInput("\r\n");
    try consumeNewLine(&ctx);

    ctx = parser.testInput("\n");
    try consumeNewLine(&ctx);

    ctx = parser.testInput("\r\r");
    try testing.expectError(error.UnexpectedToken, consumeNewLine(&ctx));

    ctx = parser.testInput("");
    try testing.expectError(error.UnexpectedToken, consumeNewLine(&ctx));
}

test "skip spaces" {
    var ctx = parser.testInput("    \th ");

    skipSpaces(&ctx);
    try testing.expect(ctx.current().? == 'h');
    skipSpaces(&ctx);
    try testing.expect(ctx.current().? == 'h');
}

test "skip lines " {
    var ctx = parser.testInput("    \t\n   \r\n  hello ");

    skipSpacesAndLineBreaks(&ctx);
    try testing.expect(ctx.current().? == 'h');
    skipSpacesAndLineBreaks(&ctx);
    try testing.expect(ctx.current().? == 'h');
}
