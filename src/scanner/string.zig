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
    last_backslash_index: ?usize = null,

    fn scan(self: *StringScanner) Error!void {
        var utf8_verifier: Utf8Verifier = .{};

        // std.log.debug("current={}", .{self.source.current.?});
        var delimiter_counter: usize = 0;
        while (try self.source.next()) |c| {
            // std.debug.print("cx={c}, del={c}\n", .{ c, self.delimiter.char });

            // Skip leading line break
            if (self.delimiter.multiline and self.content_writer.end == 0 and c == '\n') continue;

            if (c == self.delimiter.char) {
                // Invalid escape
                if (self.last_backslash_index != null) return error.UnexpectedChar;

                delimiter_counter += 1;
                if (self.delimiter.multiline) {
                    if (delimiter_counter >= 6) return error.UnexpectedChar;
                } else {
                    try utf8_verifier.done();
                    return;
                }
            } else {
                if (delimiter_counter >= 3) {
                    self.source.prev();
                    self.content_writer.end -= 3;
                    try utf8_verifier.done();
                    return;
                }

                delimiter_counter = 0;
                switch (c) {
                    '\r', '\n' => {
                        if (self.delimiter.multiline) {
                            if (self.last_backslash_index) |ix| {
                                self.content_writer.end = ix;
                                self.last_backslash_index = null;
                                try self.skipSpacesAndLineBreaks();
                                continue;
                            }
                        } else return error.UnexpectedChar;
                    },
                    '\\' => if (self.delimiter.char == '"') {
                        // Invalid escape
                        if (self.last_backslash_index != null and !is_space(c)) return error.UnexpectedChar;

                        try self.scanEscaped();
                        continue;
                    },
                    else => {
                        // Invalid escape
                        if (self.last_backslash_index != null and !is_space(c)) return error.UnexpectedChar;
                    },
                }
            }

            try utf8_verifier.verify(c);
            try self.content_writer.writeByte(c);
        }

        if (delimiter_counter >= 3) {
            self.content_writer.end -= 3;
            return;
        }

        return error.UnexpectedEndOfStream;
    }

    fn scanEscaped(self: *StringScanner) Error!void {
        const c = try self.source.next() orelse return error.UnexpectedEndOfStream;
        var w = self.content_writer;
        switch (c) {
            'x' => return self.scanUnicode(2),
            'u' => return self.scanUnicode(4),
            'U' => return self.scanUnicode(8),
            'b' => try w.writeByte(0x08),
            'e' => try w.writeByte(0x1b),
            'f' => try w.writeByte(0x0c),
            't' => try w.writeByte('\t'),
            'n' => try w.writeByte('\n'),
            'r' => try w.writeByte('\r'),
            '\"' => try w.writeByte('\"'),
            '\\' => try w.writeByte('\\'),
            '\r', '\n' => {
                if (self.delimiter.multiline)
                    try self.skipSpacesAndLineBreaks()
                else
                    return error.UnexpectedChar;
            },
            else => {
                if (is_space(c)) {
                    self.last_backslash_index = self.content_writer.end;
                    try w.writeByte(c);
                } else return error.UnexpectedChar;
            },
        }
    }

    fn skipSpacesAndLineBreaks(self: *StringScanner) Error!void {
        while (try self.source.next()) |c| {
            if (!is_space(c)) {
                self.source.prev();
                break;
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

fn is_space(c: u8) bool {
    return switch (c) {
        ' ', '\t', '\r', '\n' => true,
        else => false,
    };
}

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
                    source.prev();
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
    , &.{.{ .kind = .string, .content = "hello" }}, null);
    try testInput(
        \\'hello'
    , &.{.{ .kind = .string, .content = "hello" }}, null);
    try testInput(
        \\"""
        \\  hello
        \\"""
    , &.{.{ .kind = .string_multiline, .content = "  hello\n" }}, null);
    try testInput(
        \\'''
        \\  hello
        \\'''
    , &.{.{ .kind = .string_multiline, .content = "  hello\n" }}, null);
    try testInput(
        \\""
    , &.{.{ .kind = .string, .content = "" }}, null);
    try testInput(
        \\"""a""b"""
    , &.{.{ .kind = .string_multiline, .content = "a\"\"b" }}, null);
    try testInput("\"\\b\\t\\r\\n\\fa\"", &.{.{ .kind = .string, .content = "\x08\t\r\n\x0ca" }}, null);
    try testInput(
        \\"a\"b"
    , &.{.{ .kind = .string, .content = "a\"b" }}, null);
    try testInput(
        \\"""ab\
        \\
        \\  cde"""
    , &.{.{ .kind = .string_multiline, .content = "abcde" }}, null);
    try testInput(
        \\'''ab\
        \\
        \\  cde'''
    , &.{.{ .kind = .string_multiline, .content = "ab\\\n\n  cde" }}, null);
    try testInput(
        \\"""
        \\  abc"""
    , &.{.{ .kind = .string_multiline, .content = "  abc" }}, null);
    try testInput(
        \\'''
        \\  abc'''
    , &.{.{ .kind = .string_multiline, .content = "  abc" }}, null);
    try testInput(
        \\'a\"b'
    , &.{.{ .kind = .string, .content = "a\\\"b" }}, null);
    try testInput(
        \\"b\u00E4c"
    , &.{.{ .kind = .string, .content = "bäc" }}, null);
    try testInput(
        \\"b\U0001f642c"
    , &.{.{ .kind = .string, .content = "b\u{1f642}c" }}, null);
    try testInput(
        \\"".
    , &.{
        .{ .kind = .string, .content = "" },
        .{ .kind = .dot, .content = "" },
    }, null);
}

pub const Utf8Verifier = struct {
    buf: [4]u8 = undefined,
    unicode_len: u8 = 0,
    yet_to_write: u8 = 0,

    pub fn verify(self: *Utf8Verifier, c: u8) error{InvalidUtf8}!void {
        if (self.yet_to_write == 0) {
            const utf8Len = std.unicode.utf8ByteSequenceLength(c) catch return error.InvalidUtf8;
            if (utf8Len == 1) return;
            self.buf[0] = c;
            self.unicode_len = utf8Len;
            self.yet_to_write = utf8Len - 1;
        } else {
            if (c < 0x80 or c > 0xBF) return error.InvalidUtf8;
            self.buf[self.unicode_len - self.yet_to_write] = c;
            self.yet_to_write -= 1;
            if (self.yet_to_write == 0) {
                _ = std.unicode.utf8Decode(self.buf[0..self.unicode_len]) catch return error.InvalidUtf8;
            }
        }
    }

    pub fn done(self: Utf8Verifier) error{InvalidUtf8}!void {
        if (self.yet_to_write > 0) return error.InvalidUtf8;
    }
};
