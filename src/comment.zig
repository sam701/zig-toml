const std = @import("std");
const Context = @import("./parser.zig").Context;
const spaces = @import("./spaces.zig");
const testing = std.testing;

pub fn skip(ctx: *Context) void {
    while (ctx.input.len > 0) {
        spaces.skipSpacesAndLineBreaks(ctx);
        if (ctx.input.len == 0) return;
        if (ctx.input[0] != '#') return;
        gotoNextLine(ctx);
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
    var ctx = Context{
        .input = 
        \\  # comment # abc  
        \\    
        \\    # comment
        \\  a
        ,
        .alloc = testing.allocator,
    };
    skip(&ctx);
    try testing.expect(ctx.input[0] == 'a');
}
