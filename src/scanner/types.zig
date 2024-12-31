const std = @import("std");
const Allocator = std.mem.Allocator;
const Value = @import("./source.zig").Value;
const SourceAccessor = @import("./source.zig").SourceAccessor;
const Source = @import("./source.zig").Source;

const string = @import("./string.zig");

fn contains(c: u8, allowed: []const u8) bool {
    for (allowed) |a| {
        if (a == c) return true;
    }
    return false;
}

pub const Scanner = struct {
    state: State = .top,
    source_accessor: SourceAccessor,

    string_delimiter: ?string.Delimiter = null,

    const Self = @This();
    pub const Error = SourceAccessor.Error || error{ UnexpectedToken, UnexpectedEndOfInput };
    pub const Token = union(enum) {
        table_begin,
        table_end,
        array_of_tables_begin,
        array_of_tables_end,
        inline_table_begin,
        inline_table_end,
        array_begin,
        array_end,

        true,
        false,
        null,
        dot,

        key: Value,
        string: Value,
        string_partial: Value,
        string_escaped: u8,
        string_unicode: Value,
        integer: Value,
        float: Value,

        end_of_document,
    };
    pub const State = enum {
        top,
        key,
        key_inside_table,

        string,
        string_escaped,
        string_continued,
    };

    fn skipAny(self: *Self, chars: []const u8) Error!void {
        while (try self.source_accessor.current()) |c| {
            if (!contains(c, chars)) return;
            _ = try self.source_accessor.next();
        }
    }

    pub fn next(self: *Self) Error!Token {
        return switch (self.state) {
            .top => try self.scanTop(),
            .string => try string.scanFromBeginning(self),
            .string_escaped => try string.scanEscaped(self),
            .string_continued => try string.scan(self),
        };
    }

    fn skipSpaces(self: *Self) Error!void {
        try self.skipAny(" \t\r");
    }

    fn skipSpacesAndNewLines(self: *Self) Error!void {
        try self.skipAny(" \t\r\n");
    }

    fn scanTop(self: *Self) Error!Token {
        try self.skipSpacesAndNewLines();
        while (try self.source_accessor.current()) |c| {
            switch (c) {
                '#' => {
                    try self.skipUntilNewLine();
                    try self.skipSpacesAndNewLines();
                },
                '[' => {
                    self.state = State.key;
                    switch (try self.mnext()) {
                        '[' => return Token.array_of_tables_begin,
                        ' ', '\t' => return Token.table_begin,
                        _ => {
                            self.source_accessor.undoLastNext();
                            return Token.table_begin;
                        },
                    }
                },
                '"', '\'' => {
                    self.source_accessor.undoLastNext();
                    // TODO: implement me
                    unreachable;
                },
                'a'...'z', 'A'...'Z' => {
                    self.source_accessor.undoLastNext();
                    // TODO: implement me
                    unreachable;
                },
            }
        }
    }

    fn skipUntilNewLine(self: *Self) Error!void {
        while (try self.source_accessor.next()) |c| {
            if (c == '\n') {
                break;
            }
        }
    }

    /// Must next
    pub fn mnext(self: *Self) Error!u8 {
        return try self.source_accessor.next() orelse return error.UnexpectedEndOfInput;
    }
    pub fn snext(self: *Self) Error!?u8 {
        return try self.source_accessor.next();
    }
    pub fn scurrent(self: *Self) Error!?u8 {
        return try self.source_accessor.current();
    }
    /// Must current
    pub fn mcurrent(self: *Self) Error!u8 {
        return try self.source_accessor.current() orelse return error.UnexpectedEndOfInput;
    }
};

pub fn testInput(state: Scanner.State, txt: []const u8) Scanner {
    const source = Source{ .text = txt };
    return Scanner{
        .state = state,
        .source_accessor = SourceAccessor.init(source, std.testing.allocator, 4) catch unreachable,
    };
}
