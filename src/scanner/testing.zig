const std = @import("std");
const FixedInput = @import("./source.zig").FixedInput;
const TokenKind = @import("./root.zig").TokenKind;
const Scanner = @import("./root.zig").Scanner;
const SourceLocation = @import("./source.zig").SourceLocation;

pub const ExpectedToken = struct {
    kind: TokenKind,
    content: ?[]const u8 = null,
    location: ?SourceLocation = null,
};

pub fn testInput(input: []const u8, expected_tokens: []const ExpectedToken, hint: ?Scanner.Hint) !void {
    var in = std.Io.Reader.fixed(input);
    var s = try Scanner.init(&in, std.testing.allocator);
    defer s.deinit();

    for (expected_tokens) |expected| {
        const lt = try s.next(hint);
        try std.testing.expectEqual(expected.kind, lt.kind);
        if (expected.content) |ec|
            try std.testing.expectEqualStrings(ec, lt.content);
        if (expected.location) |el|
            try std.testing.expectEqual(el, lt.location);
    }
}
