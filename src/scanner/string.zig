const std = @import("std");
const Scanner = @import("./types.zig").Scanner;
const Error = Scanner.Error;
const Token = Scanner.Token;

const testInput = @import("./types.zig").testInput;
const testing = std.testing;

pub const Delimiter = struct {
    char: u8,
    multiline: bool = false,
};

pub fn scanFromBeginning(s: *Scanner) Error!Token {
    s.string_delimiter = try parseOpeningDelimiter(s);
    return scan(s);
}

pub fn scan(s: *Scanner) Error!Token {
    const del = s.string_delimiter.?;
    s.source_accessor.startValueCapture();

    while (try s.scurrent()) |cx| {
        var c = cx;
        if (c == del.char) {
            if (del.multiline) {
                c = try s.mnext();
                if (c == del.char) {
                    c = try s.mnext();
                    if (c == del.char) {
                        const t = try s.source_accessor.popCapturedValue(3);
                        _ = try s.snext();
                        return Token{ .string = t };
                    }
                }
            } else {
                const t = try s.source_accessor.popCapturedValue(1);
                _ = try s.snext();
                return Token{ .string = t };
            }
        }
        switch (c) {
            '\r', '\n' => if (!del.multiline) return error.UnexpectedToken,
            '\\' => if (del.char == '\"') {
                const t = try s.source_accessor.popCapturedValue(1);
                s.state = Scanner.State.string_escaped;
                _ = try s.mnext();
                return Token{ .string_partial = t };
            },
            else => {},
        }
        _ = try s.mnext();
    }
    return error.UnexpectedEndOfInput;
}

pub fn scanEscaped(s: *Scanner) Error!Token {
    const c = try s.mcurrent();
    switch (c) {
        'u' => return scanUnicode(s, 4),
        'U' => return scanUnicode(s, 8),
        'b', 'f', 't', 'n', 'r', '\"', '\\' => {
            s.state = Scanner.State.string_continued;
            return Token{ .string_escaped = c };
        },
        '\r', '\n' => {
            if (s.string_delimiter.?.multiline) {
                s.state = Scanner.State.string_continued;
                return Token{ .string_escaped = c };
            } else {
                return error.UnexpectedToken;
            }
        },
        else => return error.UnexpectedToken,
    }
}

fn scanUnicode(s: *Scanner, size: u8) Error!Token {
    _ = try s.mnext();
    s.source_accessor.startValueCapture();
    var ix = size;
    while (ix > 0) : (ix -= 1) _ = try s.mnext();
    s.state = Scanner.State.string_continued;
    return Token{ .string_unicode = try s.source_accessor.popCapturedValue(1) };
}

pub fn parseOpeningDelimiter(scanner: *Scanner) Error!Delimiter {
    const c = try scanner.mcurrent();
    switch (c) {
        '\'', '\"' => {
            const c2 = try scanner.mnext();
            if (c2 == c) {
                const c3 = try scanner.mnext();
                if (c3 == c) {
                    _ = try scanner.mnext();
                    return Delimiter{ .char = c, .multiline = true };
                } else return error.UnexpectedToken;
            } else return Delimiter{ .char = c, .multiline = false };
        },
        else => return error.UnexpectedToken,
    }
}

test "simple string" {
    var s = testInput(Scanner.State.string,
        \\"hello"
    );
    const token = try scanFromBeginning(&s);
    try testing.expectEqualSlices(u8, "hello", token.string.content);
}

test "literal string" {
    var s = testInput(Scanner.State.string,
        \\'hello'
    );
    const token = try scanFromBeginning(&s);
    try testing.expectEqualSlices(u8, "hello", token.string.content);
}

test "multiline" {
    var s = testInput(Scanner.State.string,
        \\"""
        \\  hello"""
    );
    var token = try scanFromBeginning(&s);
    try testing.expectEqualSlices(u8, "\n  hello", token.string.content);

    s = testInput(Scanner.State.string,
        \\'''
        \\  hello'''
    );
    token = try scanFromBeginning(&s);
    try testing.expectEqualSlices(u8, "\n  hello", token.string.content);
}

test "partial string" {
    var s = testInput(Scanner.State.string,
        \\"abc\u1234"
    );
    var token = try scanFromBeginning(&s);
    try testing.expectEqualSlices(u8, "abc", token.string_partial.content);
    try testing.expectEqual(Scanner.State.string_escaped, s.state);

    token = try scanEscaped(&s);
    try testing.expectEqualSlices(u8, "1234", token.string_unicode.content);
    try testing.expectEqual(Scanner.State.string_continued, s.state);

    token = try scan(&s);
    try testing.expectEqualSlices(u8, "", token.string.content);
    // TODO check the following state
    // try testing.expectEqual(Scanner.State.string_continued, s.state);
}

test "escaped" {
    var s = testInput(Scanner.State.string_escaped, "n");
    const token = try scanEscaped(&s);
    try testing.expectEqual('n', token.string_escaped);
}
