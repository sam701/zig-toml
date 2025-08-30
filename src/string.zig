const std = @import("std");
const parser = @import("./parser.zig");
const spaces = @import("./spaces.zig");
const Context = parser.Context;
const testing = std.testing;

// Returned string is allocated
pub fn parse(ctx: *Context) !?[]const u8 {
    var delimiter = parseOpeningDelimiter(ctx) orelse return null;
    return parseString(ctx, &delimiter);
}

const Buffer = std.ArrayListUnmanaged(u8);

pub fn parseSingleLine(ctx: *Context) !?[]const u8 {
    var ctx2 = ctx.*;
    var delimiter = parseOpeningDelimiter(&ctx2) orelse return null;
    if (delimiter.multiline) return error.UnexpectedMultilineString;

    ctx.* = ctx2;
    return parseString(ctx, &delimiter);
}

pub fn parseString(ctx: *Context, delimiter: *const Delimiter) !?[]const u8 {
    var output: Buffer = .{};
    errdefer output.deinit(ctx.alloc);

    while (ctx.current()) |c| {
        switch (c) {
            '\'', '\"' => {
                if (try parseClosingDelimiter(ctx, delimiter)) {
                    return try output.toOwnedSlice(ctx.alloc);
                }
            },
            '\r', '\n' => if (!delimiter.multiline) return error.InvalidCharacter,
            '\\' => if (delimiter.char == '\"') {
                try parseEscaped(ctx, delimiter, &output);
                continue;
            },
            else => {},
        }
        try output.append(ctx.alloc, c);
        _ = ctx.next();
    }
    return error.UnexpectedEOF;
}

fn parseClosingDelimiter(ctx: *Context, delimiter: *const Delimiter) !bool {
    const c = ctx.current() orelse unreachable;
    if (delimiter.char != c) return false;
    if (!delimiter.multiline) {
        _ = ctx.next();
        return true;
    }
    if (ctx.input.len < 3) return error.UnexpectedEOF;
    const success = ctx.input[1] == c and ctx.input[2] == c;
    if (success) {
        _ = ctx.next();
        _ = ctx.next();
        _ = ctx.next();
    }
    return success;
}

fn parseEscaped(ctx: *Context, delimiter: *const Delimiter, output: *Buffer) !void {
    const c = ctx.next() orelse return error.UnexpectedEOF;
    _ = ctx.next() orelse return error.UnexpectedEOF;
    switch (c) {
        'u' => try parseUnicode(ctx, 4, output),
        'U' => try parseUnicode(ctx, 8, output),
        'b' => try output.append(ctx.alloc, 0x08),
        'f' => try output.append(ctx.alloc, 0x0c),
        't' => try output.append(ctx.alloc, '\t'),
        'n' => try output.append(ctx.alloc, '\n'),
        'r' => try output.append(ctx.alloc, '\r'),
        '\"' => try output.append(ctx.alloc, '\"'),
        '\\' => try output.append(ctx.alloc, '\\'),
        '\r', '\n' => {
            if (delimiter.multiline) {
                spaces.skipSpacesAndLineBreaks(ctx);
            } else {
                return error.InvalidCharacter;
            }
        },
        else => return error.InvalidEscape,
    }
}

fn parseUnicode(ctx: *Context, size: u8, output: *Buffer) !void {
    var unicode_buf: [8]u8 = undefined;
    const ub = unicode_buf[0..size];
    parser.takeBuffer(ctx, ub) catch return error.InvalidUnicode;

    const codepoint = std.fmt.parseInt(u21, ub, 16) catch return error.InvalidUnicode;

    var buf: [4]u8 = undefined;
    const len = try std.unicode.utf8Encode(codepoint, buf[0..]);
    try output.appendSlice(ctx.alloc, buf[0..len]);
}

fn parseOpeningDelimiter(ctx: *Context) ?Delimiter {
    if (ctx.current()) |c| {
        if (c == '\'' or c == '\"') {
            _ = ctx.next();
            const ml = ctx.input.len >= 2 and ctx.input[0] == c and ctx.input[1] == c;
            if (ml) {
                _ = ctx.next();
                _ = ctx.next();
                if (c == '\"') skipNewLine(ctx);
            }
            return Delimiter{ .char = c, .multiline = ml };
        }
    }
    return null;
}

fn skipNewLine(ctx: *Context) void {
    while (ctx.current()) |c| {
        if (c != '\n' and c != '\r') break;
        _ = ctx.next();
    }
}

const Delimiter = struct {
    char: u8,
    multiline: bool = false,
};

test "leading new line" {
    var ctx = parser.testInput(
        \\"""
        \\  hello"""
    );
    var str = try parse(&ctx);
    try testing.expect(std.mem.eql(u8, str.?, "  hello"));
    ctx.alloc.free(str.?);

    ctx = parser.testInput(
        \\'''
        \\  hello'''
    );
    str = try parse(&ctx);
    try testing.expect(std.mem.eql(u8, str.?, "\n  hello"));
    ctx.alloc.free(str.?);
}

test "single quote" {
    var ctx = parser.testInput(
        \\'\ab'=
    );
    const str = try parse(&ctx);
    try testing.expect(std.mem.eql(u8, str.?, "\\ab"));
    try testing.expect(ctx.current().? == '=');
    ctx.alloc.free(str.?);
}

test "trailing backslash" {
    var ctx = parser.testInput(
        \\"""\
        \\  hello"""
    );
    var str = try parse(&ctx);
    try testing.expect(std.mem.eql(u8, str.?, "hello"));
    ctx.alloc.free(str.?);

    ctx = parser.testInput(
        \\'''\
        \\  hello'''
    );
    str = try parse(&ctx);
    try testing.expect(std.mem.eql(u8, str.?, "\\\n  hello"));
    ctx.alloc.free(str.?);

    ctx = parser.testInput(
        \\"\
        \\  hello"
    );
    try testing.expectError(error.InvalidCharacter, parse(&ctx));
}

test "invalid escape" {
    var ctx = parser.testInput(
        \\"\ab"=
    );
    try testing.expectError(error.InvalidEscape, parse(&ctx));
}

test "multiline" {
    var ctx = parser.testInput(
        \\"""
        \\  hello
        \\"nice"
        \\"""
    );
    const str = try parse(&ctx);
    try testing.expect(std.mem.eql(u8, str.?, "  hello\n\"nice\"\n"));
    ctx.alloc.free(str.?);
}

test "multiline literal" {
    var ctx = parser.testInput(
        \\'''
        \\  hello
        \\nice
        \\'''
    );
    const str = try parse(&ctx);
    try testing.expect(std.mem.eql(u8, str.?, "\n  hello\nnice\n"));
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
    const str = try parse(&ctx);
    try testing.expect(std.mem.eql(u8, str.?, "abc"));
    try testing.expect(ctx.current().? == '=');
    ctx.alloc.free(str.?);
}

test "unicode 4" {
    var ctx = parser.testInput("\"b\\u00E4c\"");
    const str = try parse(&ctx);
    try testing.expect(std.mem.eql(u8, str.?, "bäc"));
    ctx.alloc.free(str.?);
}

test "unicode 8" {
    var ctx = parser.testInput("\"b\\U0001F642c\"");
    const str = try parse(&ctx);
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
    const str = try parse(&ctx);
    try testing.expect(str == null);
}

test "escape" {
    var ctx = parser.testInput(
        \\"a\"bc"
    );
    const str = try parse(&ctx);
    try testing.expect(std.mem.eql(u8, str.?, "a\"bc"));
    try testing.expect(ctx.current() == null);
    ctx.alloc.free(str.?);
}

test "double escape" {
    var ctx = parser.testInput(
        \\"a\\"
    );
    const str = try parse(&ctx);
    try testing.expect(std.mem.eql(u8, str.?, "a\\"));
    try testing.expect(ctx.current() == null);
    ctx.alloc.free(str.?);
}

test "simple escape" {
    var ctx = parser.testInput("\"\\b\\t\\r\\n\\fa\"");
    const str = try parse(&ctx);
    try testing.expect(std.mem.eql(u8, str.?, "\x08\t\r\n\x0ca"));
    try testing.expect(ctx.current() == null);
    ctx.alloc.free(str.?);
}

// TODO: line ending backslash
// TODO: multi-line opening trimming
