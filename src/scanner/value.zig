const std = @import("std");
const Writer = std.Io.Writer;

const Source = @import("./source.zig").Source;
const testInput = @import("./testing.zig").testInput;
const Error = @import("./root.zig").Scanner.Error;
const TokenKind = @import("./root.zig").TokenKind;

pub fn scan(source: *Source, content_writer: *Writer) Error!TokenKind {
    while (try source.next()) |c| {
        switch (c) {
            '0'...'9', 'a'...'z', 'A'...'Z', '+', '-', '_', '.', ':' => {},
            ' ' => {
                if (content_writer.end == 10 and content_writer.buffer[4] == '-') {
                    if (try source.next()) |c2| {
                        if (c2 >= '0' and c2 <= '9') {
                            try content_writer.writeByte(' ');
                            try content_writer.writeByte(c2);
                            continue;
                        }
                    }
                }
                source.prev();
                break;
            },
            else => {
                source.prev();
                break;
            },
        }
        try content_writer.writeByte(c);
    }

    const buf = content_writer.buffered();
    if (buf.len == 10 and buf[4] == '-') return .date;
    if (buf.len >= 8 and buf[2] == ':') return .time;
    if (buf.len >= 19 and (buf[10] == 'T' or buf[10] == ' ')) {
        const tz = buf[buf.len - 6];
        if (buf[buf.len - 1] == 'Z' or tz == '-' or tz == '+')
            return .datetime
        else
            return .datetime_local;
    }

    return .number;
}

test "numbers" {
    try testInput("123", &.{.{ .kind = .number, .content = "123" }}, .expect_value);
    try testInput("123e4", &.{.{ .kind = .number, .content = "123e4" }}, .expect_value);
    try testInput("123_4", &.{.{ .kind = .number, .content = "123_4" }}, .expect_value);
    try testInput(".7", &.{.{ .kind = .number, .content = ".7" }}, .expect_value);
    try testInput("+7", &.{.{ .kind = .number, .content = "+7" }}, .expect_value);
    try testInput("-inf", &.{.{ .kind = .number, .content = "-inf" }}, .expect_value);
    try testInput("nan", &.{.{ .kind = .number, .content = "nan" }}, .expect_value);
}

test "datetime" {
    try testInput("2025-08-27 ", &.{.{ .kind = .date, .content = "2025-08-27" }}, .expect_value);
    try testInput("08:03:04 ", &.{.{ .kind = .time, .content = "08:03:04" }}, .expect_value);
    try testInput("08:03:04.123 ", &.{.{ .kind = .time, .content = "08:03:04.123" }}, .expect_value);
    try testInput("2025-08-27T19:44:00Z ", &.{.{ .kind = .datetime, .content = "2025-08-27T19:44:00Z" }}, .expect_value);
    try testInput("2025-08-27 19:44:00.12345678Z ", &.{.{ .kind = .datetime, .content = "2025-08-27 19:44:00.12345678Z" }}, .expect_value);
    try testInput("2025-08-27T19:44:00+02:30 ", &.{.{ .kind = .datetime, .content = "2025-08-27T19:44:00+02:30" }}, .expect_value);
    try testInput("2025-08-27 19:44:00 ", &.{.{ .kind = .datetime_local, .content = "2025-08-27 19:44:00" }}, .expect_value);
}

pub fn ensure(source: *Source, pattern: []const u8, token_to_return: TokenKind) Error!TokenKind {
    for (pattern) |ec| {
        const c = try source.mustNext();
        if (c != ec) return error.UnexpectedChar;
    }

    return token_to_return;
}

test ensure {
    try testInput("true.", &.{.{ .kind = .true }}, .expect_value);
    try testInput("false.", &.{.{ .kind = .false }}, .expect_value);
    try testInput("null.", &.{.{ .kind = .null }}, .expect_value);
}
