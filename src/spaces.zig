const std = @import("std");
const testing = std.testing;
const Context = @import("./parser.zig").Context;

fn contains(c: u8, allowed: []const u8) bool {
    for (allowed) |a| {
        if (a == c) return true;
    }
    return false;
}

fn skipAny(ctx: *Context, chars: []const u8) void {
    while (ctx.input.len > 0) {
        var c = ctx.input[0];
        if (!contains(c, chars)) return;
        ctx.input = ctx.input[1..];
    }
}

pub fn skipSpaces(ctx: *Context) void {
    skipAny(ctx, " \t");
}

pub fn skipSpacesAndLineBreaks(ctx: *Context) void {
    skipAny(ctx, " \t\r\n");
}

test "skip spaces" {
    const txt = "    \th ";
    var ctx = Context{
        .input = txt,
        .alloc = testing.allocator,
    };

    skipSpaces(&ctx);
    try testing.expect(ctx.input[0] == 'h');
    skipSpaces(&ctx);
    try testing.expect(ctx.input[0] == 'h');
}

test "skip lines " {
    const txt = "    \t\n   \r\n  hello ";
    var ctx = Context{
        .input = txt,
        .alloc = testing.allocator,
    };

    skipSpacesAndLineBreaks(&ctx);
    try testing.expect(ctx.input[0] == 'h');
    skipSpacesAndLineBreaks(&ctx);
    try testing.expect(ctx.input[0] == 'h');
}
