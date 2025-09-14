const std = @import("std");
const Allocator = std.mem.Allocator;
const Reader = std.Io.Reader;
const Writer = std.Io.Writer;

const bare_key = @import("./bare_key.zig");
const value = @import("./value.zig");
const Source = @import("./source.zig").Source;
const SourceLocation = @import("./source.zig").SourceLocation;
const string = @import("./string.zig");
const testInput = @import("./testing.zig").testInput;
const testValueInput = @import("./testing.zig").testValueInput;

pub const TokenKind = enum {
    left_bracket,
    right_bracket,
    double_left_bracket,
    double_right_bracket,
    left_brace,
    right_brace,

    line_break,
    dot,
    comma,
    equal,
    null,
    true,
    false,

    bare_key,
    string,
    string_multiline,
    number,
    date,
    time,
    datetime,
    datetime_local, // without timezone

    end_of_document,
};

pub const Token = struct {
    kind: TokenKind,
    content: []const u8,
    location: SourceLocation,
};

pub const Scanner = struct {
    const Self = @This();

    pub const Hint = enum {
        top_level,
        after_double_bracket,
        expect_value,
    };

    content_buffer: Writer.Allocating,
    source: Source,

    pub const Error = Source.Error || error{ UnexpectedChar, InvalidUnicode };

    pub fn init(reader: *Reader, alloc: Allocator) error{OutOfMemory}!Self {
        return .{
            .content_buffer = try Writer.Allocating.initCapacity(alloc, 1024),
            .source = try Source.init(reader),
        };
    }

    pub fn deinit(self: *Self) void {
        self.content_buffer.deinit();
    }

    pub fn next(self: *Self, hint: ?Hint) Error!Token {
        try self.skipSpaces();

        const pos = self.source.location;
        var token_kind: ?TokenKind = null;
        self.content_buffer.clearRetainingCapacity();
        if (try self.source.next()) |c| {
            // std.debug.print("scan, c={c} {any}\n", .{ c, hint });

            switch (c) {
                '\n' => token_kind = .line_break,
                ',' => token_kind = .comma,
                '=' => token_kind = .equal,
                '{' => token_kind = .left_brace,
                '}' => token_kind = .right_brace, // empty inner table
                '[' => {
                    if (hint == .top_level) {
                        if (try self.source.mustNext() == '[') {
                            token_kind = .double_left_bracket;
                        } else {
                            self.source.prev();
                            token_kind = .left_bracket;
                        }
                    } else {
                        token_kind = .left_bracket;
                    }
                },
                ']' => {
                    if (hint == .after_double_bracket) {
                        if (try self.source.mustNext() == ']') {
                            token_kind = .double_right_bracket;
                        } else {
                            self.source.prev();
                            token_kind = .right_bracket;
                        }
                    } else {
                        token_kind = .right_bracket;
                    }
                },
                '"', '\'' => {
                    self.source.prev();
                    token_kind = try string.scan(&self.source, &self.content_buffer.writer);
                },
                '#' => {
                    try self.skipUntilNewLine();
                    return self.next(null);
                },

                else => {
                    if (hint == .expect_value) {
                        switch (c) {
                            '0'...'9', '.', '-', '+', 'i' => {
                                self.source.prev();
                                token_kind = try value.scan(&self.source, &self.content_buffer.writer);
                            },
                            't' => token_kind = try value.ensure(&self.source, "rue", .true),
                            'f' => token_kind = try value.ensure(&self.source, "alse", .false),
                            'n' => {
                                const c2 = try self.source.mustNext();
                                switch (c2) {
                                    'u' => token_kind = try value.ensure(&self.source, "ll", .null),
                                    'a' => {
                                        token_kind = try value.ensure(&self.source, "n", .number);
                                        try self.content_buffer.writer.writeAll("nan");
                                    },
                                    else => return error.UnexpectedChar,
                                }
                            },
                            else => return error.UnexpectedChar,
                        }
                    } else {
                        switch (c) {
                            'a'...'z', 'A'...'Z', '0'...'9', '_', '-' => {
                                self.source.prev();
                                token_kind = try bare_key.scan(&self.source, &self.content_buffer.writer);
                            },
                            '.' => token_kind = .dot,
                            else => return error.UnexpectedChar,
                        }
                    }
                },
            }
        }
        return Token{
            .kind = if (token_kind) |t| t else .end_of_document,
            .content = self.content_buffer.written(),
            .location = pos,
        };
    }

    fn skipSpaces(self: *Self) Error!void {
        while (try self.source.next()) |c| {
            switch (c) {
                ' ', '\t', '\r' => {},
                else => {
                    self.source.prev();
                    break;
                },
            }
        }
    }

    fn skipUntilNewLine(self: *Self) Error!void {
        while (try self.source.next()) |c| {
            if (c == '\n') {
                self.source.prev();
                break;
            }
        }
    }
};

comptime {
    _ = @import("./string.zig");
    _ = @import("./bare_key.zig");
    _ = @import("./value.zig");
}

test "comments" {
    try testInput(", # comment\n abc", &.{ .{ .kind = .comma }, .{ .kind = .line_break } }, null);
}

test "basic tokens" {
    try testInput(", ] \n = }", &.{
        .{ .kind = .comma },
        .{ .kind = .right_bracket },
        .{ .kind = .line_break },
        .{ .kind = .equal },
        .{ .kind = .right_brace },
    }, null);
    try testInput(" [[", &.{
        .{ .kind = .double_left_bracket },
    }, .top_level);
    try testInput(" ]]", &.{
        .{ .kind = .double_right_bracket },
    }, .after_double_bracket);
    try testInput("[ {", &.{
        .{ .kind = .left_bracket },
        .{ .kind = .left_brace },
    }, null);
}
