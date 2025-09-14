const std = @import("std");
const Writer = std.Io.Writer;

const Source = @import("./source.zig").Source;
const testInput = @import("./testing.zig").testInput;
const Error = @import("./root.zig").Scanner.Error;
const TokenKind = @import("./root.zig").TokenKind;

pub fn scan(source: *Source, content_writer: *Writer) Error!TokenKind {
    while (try source.next()) |c| {
        switch (c) {
            'a'...'z', 'A'...'Z', '0'...'9', '_', '-' => {
                try content_writer.writeByte(c);
            },
            else => {
                source.prev();
                break;
            },
        }
    }
    return .bare_key;
}

test "bare_key" {
    try testInput("abc34.", &.{
        .{ .kind = .bare_key, .content = "abc34" },
        .{ .kind = .dot },
        .{ .kind = .end_of_document },
    }, null);
    try testInput("123.", &.{
        .{ .kind = .bare_key, .content = "123" },
        .{ .kind = .dot },
        .{ .kind = .end_of_document },
    }, null);
    try testInput("3-e_5.", &.{.{ .kind = .bare_key, .content = "3-e_5" }}, null);
}
