const std = @import("std");
const parser = @import("./parser.zig");
const Context = parser.Context;
const testing = std.testing;

// Returned string is allocated
pub fn parse(ctx: *Context) !?[]const u8 {
    return parseSingleLine(ctx);
}

pub fn parseSingleLine(ctx: *Context) !?[]const u8 {
    var single_quote = false;
    parser.consumeString(ctx, "\"") catch {
        parser.consumeString(ctx, "'") catch return null;
        single_quote = true;
    };
    var sctx = StringContext{
        .output = std.ArrayList(u8).init(ctx.alloc),
        .single_quote = single_quote,
        .single_line = true,
    };
    errdefer sctx.output.deinit();

    while (ctx.current()) |c| {
        _ = ctx.next();
        if (!try charTester(&sctx, c)) {
            return sctx.output.toOwnedSlice();
        }
    }
    return error.UnexpectedEOF;
}

const StringContext = struct {
    output: std.ArrayList(u8),
    escaped: bool = false,
    single_quote: bool,
    single_line: bool,
};

// Returns true if further chars can be consumed.
fn charTester(ctx: *StringContext, c: u8) !bool {
    if (ctx.single_line) {
        if(c == '\r' or c == '\n') return error.InvalidCharacter;
    }
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
        if (ctx.single_quote) {
            if (c == '\'') return false;
            try ctx.output.append(c);
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
    }
    return true;
}

test "single quote" {
    var ctx = parser.testInput(
        \\'\ab'=
    );
    var str = try parse(&ctx);
    try testing.expect(std.mem.eql(u8, str.?, "\\ab"));
    try testing.expect(ctx.current().? == '=');
    ctx.alloc.free(str.?);
}

test "new lines in single line strings" {
    var ctx = parser.testInput("'abc\n'");
    try testing.expectError(error.InvalidCharacter, parse(&ctx));

    ctx = parser.testInput("\"abc\n\"");
    try testing.expectError(error.InvalidCharacter, parse(&ctx));
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
// TODO: line ending backslash
// TODO: multi-line literal string '''aoeu'''
