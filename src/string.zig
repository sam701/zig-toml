const std = @import("std");
const parser = @import("./parser.zig");
const testing = std.testing;

// Returned string is allocated
pub fn parse(ctx: *parser.Context) !?[]const u8 {
    if (ctx.src.current()) |cur| {
        if (cur == '"') {
            var sctx = StringContext{ .output = std.ArrayList(u8).init(ctx.alloc), .escaped = false };
            while (try ctx.src.next()) |c| {
                if (!try charTester(&sctx, c)) {
                    _ = try ctx.src.next();
                    return sctx.output.toOwnedSlice();
                }
            }
            return error.UnexpectedEOF;
        } else {
            return null;
        }
    } else {
        return null;
    }
}

const StringContext = struct {
    output: std.ArrayList(u8),
    escaped: bool,
};

fn charTester(ctx: *StringContext, c: u8) !bool {
    if (ctx.escaped) {
        try ctx.output.append(c);
        ctx.escaped = false;
        return true;
    }
    switch (c) {
        '"' => return false,
        '\\' => {
            ctx.escaped = true;
            return true;
        },
        else => {
            try ctx.output.append(c);
            return true;
        },
    }
}

test "simple" {
    var src = parser.Source.init(
        \\"abc"=
    );
    var ctx = parser.Context{
        .src = &src,
        .alloc = testing.allocator,
    };

    var str = try parse(&ctx);
    try testing.expect(std.mem.eql(u8, str.?, "abc"));
    try testing.expect(ctx.src.current().? == '=');
    ctx.alloc.free(str.?);
}

test "empty" {
    var src = parser.Source.init(
        \\abc"
    );
    var ctx = parser.Context{
        .src = &src,
        .alloc = testing.allocator,
    };

    var str = try parse(&ctx);
    try testing.expect(str == null);
}

test "escape" {
    var src = parser.Source.init(
        \\"a\"bc"
    );
    var ctx = parser.Context{
        .src = &src,
        .alloc = testing.allocator,
    };

    var str = try parse(&ctx);
    try testing.expect(std.mem.eql(u8, str.?, "a\"bc"));
    try testing.expect(ctx.src.current() == null);
    ctx.alloc.free(str.?);
}

test "double escape" {
    var src = parser.Source.init(
        \\"a\\"
    );
    var ctx = parser.Context{
        .src = &src,
        .alloc = testing.allocator,
    };

    var str = try parse(&ctx);
    try testing.expect(std.mem.eql(u8, str.?, "a\\"));
    try testing.expect(ctx.src.current() == null);
    ctx.alloc.free(str.?);
}

// TODO: escaping \t \n
// TODO: unicode escaping \u0000
// TODO: multi-line
// TODO: literal string 'abc'
// TODO: multi-line literal string '''aoeu'''
