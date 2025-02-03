const std = @import("std");
const parser = @import("parser");
const Context = parser.Context;
const spaces = @import("./spaces.zig");
const testing = std.testing;

pub fn skipSpacesAndComments(ctx: *Context) void {
    while (ctx.current()) |_| {
        spaces.skipSpacesAndLineBreaks(ctx);
        if (ctx.current()) |c| {
            if (c != '#') return;
            gotoNextLine(ctx);
        }
    }
}

fn gotoNextLine(ctx: *Context) void {
    while (ctx.current()) |c| {
        _ = ctx.next();
        if (c == '\n') {
            return;
        }
    }
}

test "skip" {
    var ctx = parser.testInput(
        \\  # comment # abc  
        \\    
        \\    # comment
        \\  a
    );
    skipSpacesAndComments(&ctx);
    try testing.expect(ctx.current().? == 'a');
}
