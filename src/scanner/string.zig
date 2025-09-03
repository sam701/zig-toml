const std = @import("std");
const testing = std.testing;
const Writer = std.Io.Writer;

const Error = @import("./root.zig").Scanner.Error;
const TokenKind = @import("./root.zig").TokenKind;
const FixedInput = @import("./source.zig").FixedInput;
const Source = @import("./source.zig").Source;
const testInput = @import("./testing.zig").testInput;

const Delimiter = struct {
    char: u8,
    multiline: bool = false,
};

pub fn scan(source: *Source, content_buffer: *Writer) Error!TokenKind {
    const del = try parseOpeningDelimiter(source) orelse return .string;

    var ss = StringScanner{
        .source = source,
        .content_writer = content_buffer,
        .delimiter = del,
    };
    try ss.scan();
    return if (del.multiline) .string_multiline else .string;
}

const StringScanner = struct {
    source: *Source,
    delimiter: Delimiter,
    content_writer: *Writer,

    fn scan(self: *StringScanner) Error!void {
        // std.debug.print("current={c}\n", .{self.source.current.?});
        var delimiter_counter: usize = 0;
        while (try self.source.next()) |c| {
            // std.debug.print("cx={c}, del={c}\n", .{ c, self.delimiter.char });

            // Skip leading line break
            if (self.content_writer.end == 0 and c == '\n') continue;

            if (c == self.delimiter.char) {
                delimiter_counter += 1;
                if (self.delimiter.multiline) {
                    if (delimiter_counter == 3) {
                        self.content_writer.end -= 2;
                        return;
                    }
                } else {
                    return;
                }
            } else {
                delimiter_counter = 0;
                switch (c) {
                    '\r', '\n' => if (!self.delimiter.multiline) return error.UnexpectedChar,
                    '\\' => if (self.delimiter.char == '"') {
                        try self.scanEscaped();
                        continue;
                    },
                    else => {},
                }
            }

            try self.content_writer.writeByte(c);
        }
        return error.UnexpectedEndOfStream;
    }

    fn scanEscaped(self: *StringScanner) Error!void {
        const c = try self.source.next() orelse return error.UnexpectedEndOfStream;
        var w = self.content_writer;
        switch (c) {
            'u' => return self.scanUnicode(4),
            'U' => return self.scanUnicode(8),
            'b' => try w.writeByte(0x08),
            'f' => try w.writeByte(0x0c),
            't' => try w.writeByte('\t'),
            'n' => try w.writeByte('\n'),
            'r' => try w.writeByte('\r'),
            '\"' => try w.writeByte('\"'),
            '\\' => try w.writeByte('\\'),
            '\r', '\n' => {
                if (self.delimiter.multiline) {
                    try self.skipSpacesAndLineBreaks();
                } else {
                    return error.UnexpectedChar;
                }
            },
            else => return error.UnexpectedChar,
        }
    }

    fn skipSpacesAndLineBreaks(self: *StringScanner) Error!void {
        while (try self.source.next()) |c| {
            switch (c) {
                ' ', '\t', '\r', '\n' => {},
                else => {
                    self.source.prev();
                    break;
                },
            }
        }
    }

    fn scanUnicode(self: *StringScanner, size: u8) Error!void {
        var unicode_buf: [8]u8 = undefined;
        const ub = unicode_buf[0..size];
        for (0..size) |ix| {
            ub[ix] = try self.source.next() orelse return error.UnexpectedEndOfStream;
        }

        const codepoint = std.fmt.parseInt(u21, ub, 16) catch return error.InvalidUnicode;

        var buf: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(codepoint, buf[0..]) catch return error.InvalidUnicode;
        try self.content_writer.writeAll(buf[0..len]);
    }
};

fn parseOpeningDelimiter(source: *Source) Error!?Delimiter {
    const c = try source.mustNext();
    switch (c) {
        '\'', '\"' => {
            const c2 = try source.mustNext();
            if (c2 == c) {
                const c3 = source.next() catch |err| {
                    switch (err) {
                        error.UnexpectedEndOfStream => return null,
                        else => return err,
                    }
                };
                if (c3 == c) {
                    return Delimiter{ .char = c, .multiline = true };
                } else {
                    // Empty string
                    return null;
                }
            } else {
                source.prev();
                return Delimiter{ .char = c, .multiline = false };
            }
        },
        else => return error.UnexpectedChar,
    }
}

test parseOpeningDelimiter {
    var in = FixedInput.init("\"a");
    var r = try parseOpeningDelimiter(&in.source);
    try testing.expectEqual(Delimiter{ .char = '"', .multiline = false }, r);
    try testing.expectEqual('a', in.source.current.?);
    in.deinit();

    in = FixedInput.init("'a");
    r = try parseOpeningDelimiter(&in.source);
    try testing.expectEqual(Delimiter{ .char = '\'', .multiline = false }, r);
    try testing.expectEqual('a', in.source.current.?);
    in.deinit();

    in = FixedInput.init("\"\"\"a");
    r = try parseOpeningDelimiter(&in.source);
    try testing.expectEqual(Delimiter{ .char = '"', .multiline = true }, r);
    try testing.expectEqual('a', try in.source.next());
    in.deinit();
}

test scan {
    try testInput(
        \\"hello"
    , &.{.{ .kind = .string, .content = "hello" }});
    try testInput(
        \\'hello'
    , &.{.{ .kind = .string, .content = "hello" }});
    try testInput(
        \\"""
        \\  hello
        \\"""
    , &.{.{ .kind = .string_multiline, .content = "  hello\n" }});
    try testInput(
        \\'''
        \\  hello
        \\'''
    , &.{.{ .kind = .string_multiline, .content = "  hello\n" }});
    try testInput(
        \\""
    , &.{.{ .kind = .string, .content = "" }});
    try testInput(
        \\"""a""b"""
    , &.{.{ .kind = .string_multiline, .content = "a\"\"b" }});
    try testInput("\"\\b\\t\\r\\n\\fa\"", &.{.{ .kind = .string, .content = "\x08\t\r\n\x0ca" }});
    try testInput(
        \\"a\"b"
    , &.{.{ .kind = .string, .content = "a\"b" }});
    try testInput(
        \\"""ab\
        \\
        \\  cde"""
    , &.{.{ .kind = .string_multiline, .content = "abcde" }});
    try testInput(
        \\'''ab\
        \\
        \\  cde'''
    , &.{.{ .kind = .string_multiline, .content = "ab\\\n\n  cde" }});
    try testInput(
        \\"""
        \\  abc"""
    , &.{.{ .kind = .string_multiline, .content = "  abc" }});
    try testInput(
        \\'''
        \\  abc'''
    , &.{.{ .kind = .string_multiline, .content = "  abc" }});
    try testInput(
        \\'a\"b'
    , &.{.{ .kind = .string, .content = "a\\\"b" }});
    try testInput(
        \\"b\u00E4c"
    , &.{.{ .kind = .string, .content = "bäc" }});
    try testInput(
        \\"b\U0001f642c"
    , &.{.{ .kind = .string, .content = "b\u{1f642}c" }});
}
