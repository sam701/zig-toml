const std = @import("std");
const parser = @import("./parser.zig");
const Context = parser.Context;
const testing = std.testing;

// Returned string is allocated
pub fn parse(ctx: *Context) !?[]const u8 {
    return parseSingleLine(ctx);
}

const Buffer = std.ArrayList(u8);

pub fn parseSingleLine(ctx: *Context) !?[]const u8 {
    var delimiter = parseStringStart(ctx) orelse return null;
    var output = Buffer.init(ctx.alloc);
    errdefer output.deinit();

    while (ctx.current()) |c| {
        switch (c) {
            '\'', '\"' => {
                if (delimiter.char == c) {
                    _ = ctx.next();
                    return output.toOwnedSlice();
                }
            },
            '\r', '\n' => return error.InvalidCharacter,
            '\\' => if (delimiter.char == '\"') {
                try parseEscaped(ctx, &output);
                continue;
            },
            else => {},
        }
        try output.append(c);
        _ = ctx.next();
    }
    return error.UnexpectedEOF;
}

fn parseEscaped(ctx: *Context, output: *Buffer) !void {
    var c = ctx.next() orelse return error.UnexpectedEOF;
    _ = ctx.next() orelse return error.UnexpectedEOF;
    switch (c) {
        'u' => try parseUnicode(ctx, 4, output),
        'U' => try parseUnicode(ctx, 8, output),
        'b' => try output.append(0x08),
        'f' => try output.append(0x0c),
        't' => try output.append('\t'),
        'n' => try output.append('\n'),
        'r' => try output.append('\r'),
        else => try output.append(c),
    }
}

fn parseUnicode(ctx: *Context, size: u8, output: *Buffer) !void {
    var unicode_buf: [8]u8 = undefined;
    var ub = unicode_buf[0..size];
    parser.takeBuffer(ctx, ub) catch return error.InvalidUnicode;

    var codepoint = std.fmt.parseInt(u21, ub, 16) catch return error.InvalidUnicode;

    var buf: [4]u8 = undefined;
    var len = try std.unicode.utf8Encode(codepoint, buf[0..]);
    try output.appendSlice(buf[0..len]);
}

fn parseStringStart(ctx: *Context) ?Delimiter {
    if (ctx.current()) |c| {
        if (c == '\'' or c == '\"') {
            _ = ctx.next();
            return Delimiter{ .char = c };
        }
    }
    return null;
}

const Delimiter = struct {
    char: u8,
    multiline: bool = false,
};

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

test "unicode 4" {
    var ctx = parser.testInput("\"b\\u00E4c\"");
    var str = try parse(&ctx);
    try testing.expect(std.mem.eql(u8, str.?, "bäc"));
    ctx.alloc.free(str.?);
}

test "unicode 8" {
    var ctx = parser.testInput("\"b\\U0001F642c\"");
    var str = try parse(&ctx);
    try testing.expect(std.mem.eql(u8, str.?, "b\u{1f642}c"));
    ctx.alloc.free(str.?);
}

test "invalid unicode 1" {
    var ctx = parser.testInput("\"b\\U0101F642c\"");
    try testing.expectError(error.InvalidUnicode, parse(&ctx));
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
// TODO: multi-line
// TODO: line ending backslash
// TODO: multi-line literal string '''aoeu'''
