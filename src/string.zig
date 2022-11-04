const std = @import("std");
const parser = @import("./parser.zig");
const Context = parser.Context;
const testing = std.testing;

// Returned string is allocated
pub fn parse(ctx: *Context) !?[]const u8 {
    if (ctx.current()) |cur| {
        if (cur == '"') {
            var sctx = StringContext{ .output = std.ArrayList(u8).init(ctx.alloc), .escaped = false };
            while (ctx.next()) |c| {
                if (!try charTester(&sctx, c)) {
                    _ = ctx.next();
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

// Returns true if further chars can be consumed.
fn charTester(ctx: *StringContext, c: u8) !bool {
    if (ctx.escaped) {
        var cn = switch (c) {
            'b' => 0x08,
            'f' => 0x0c,
            't' => '\t',
            'n' => '\n',
            'r' => '\r',
            else => c,
        };
        try ctx.output.append(cn);
        ctx.escaped = false;
    } else {
        switch (c) {
            '"' => return false,
            '\\' => {
                ctx.escaped = true;
            },
            else => {
                try ctx.output.append(c);
            },
        }
    }
    return true;
}

test "simple" {
    var ctx = parser.testInput(
        \\"abc"=
    );
    var str = try parse(&ctx);
    try testing.expect(std.mem.eql(u8, str.?, "abc"));
    try testing.expect(ctx.current().? == '=');
    ctx.alloc.free(str.?);
}

test "empty" {
    var ctx = parser.testInput(
        \\abc"
    );
    var str = try parse(&ctx);
    try testing.expect(str == null);
}

test "escape" {
    var ctx = parser.testInput(
        \\"a\"bc"
    );
    var str = try parse(&ctx);
    try testing.expect(std.mem.eql(u8, str.?, "a\"bc"));
    try testing.expect(ctx.current() == null);
    ctx.alloc.free(str.?);
}

test "double escape" {
    var ctx = parser.testInput(
        \\"a\\"
    );
    var str = try parse(&ctx);
    try testing.expect(std.mem.eql(u8, str.?, "a\\"));
    try testing.expect(ctx.current() == null);
    ctx.alloc.free(str.?);
}

test "simple escape" {
    var ctx = parser.testInput("\"\\b\\t\\r\\n\\fa\"");
    var str = try parse(&ctx);
    try testing.expect(std.mem.eql(u8, str.?, "\x08\t\r\n\x0ca"));
    try testing.expect(ctx.current() == null);
    ctx.alloc.free(str.?);
}

// TODO: All other escape sequences not listed above are reserved; if they are used, TOML should produce an error.
// TODO: unicode escaping \u0000
// TODO: multi-line
// TODO: literal string 'abc'
// TODO: line ending backslash
// TODO: multi-line literal string '''aoeu'''
