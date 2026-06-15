const std = @import("std");
const Scanner = @import("./scanner/root.zig").Scanner;
const Token = @import("./scanner/root.zig").Token;
const TokenKind = @import("./scanner/root.zig").TokenKind;
const Reader = std.Io.Reader;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const SourceLocation = @import("./scanner/source.zig").SourceLocation;
const value = @import("./value.zig");
const datetime = @import("./datetime.zig");
const DefaultDateTypes = datetime.Simple;

pub const Parsed = std.json.Parsed;
pub const Error = Scanner.Error || std.fmt.ParseIntError || std.fmt.ParseFloatError || std.mem.Allocator.Error || datetime.Error || error{
    UnexpectedToken,
    NotStruct,
    InvalidValueType,
    DuplicateValue,
};

const debug = false;

// TODO: add options that can specify
// - how to treat missing fields,
// - how to treat non-existing fields
//
// TODO: set not-provided optional fields to null.

/// Parse TOML from a reader into type T.
/// Datetime values (date, datetime, datetime-local, time) are returned as strings.
pub fn parse(comptime T: type, reader: *Reader, alloc: Allocator) Error!Parsed(T) {
    return parseWith(T, reader, alloc, DefaultDateTypes);
}

/// Parse TOML from a reader into type T with a custom datetime parser.
///
/// The DateTypes type must provide the following functions:
/// - `parseDate(str: []const u8, alloc: Allocator) Error!TargetType`
/// - `parseDatetime(str: []const u8, alloc: Allocator) Error!TargetType`
/// - `parseDatetimeLocal(str: []const u8, alloc: Allocator) Error!TargetType`
/// - `parseTime(str: []const u8, alloc: Allocator) Error!TargetType`
///
/// Each function's return type (the error union payload) must match the target field type in T.
pub fn parseWith(comptime T: type, reader: *Reader, alloc: Allocator, comptime DateTypes: type) Error!Parsed(T) {
    var p = try Parser(DateTypes).init(reader, alloc);
    defer p.deinit();

    const table = try p.parseDocument();

    // if (T != value.Table(DateTypes)) unreachable;

    return Parsed(T){
        .arena = p.arena,
        .value = table,
    };
}

fn Parser(comptime DateTypes: type) type {
    const TomlValue = value.Value(DateTypes);
    const TomlTable = value.Table(DateTypes);
    const TomlArray = value.Array(DateTypes);

    return struct {
        arena: *ArenaAllocator,
        scanner: Scanner,
        token_location: ?SourceLocation = null,
        current_token: ?Token = null,
        advance: bool = true,

        const Self = @This();

        pub fn init(reader: *Reader, alloc: Allocator) error{OutOfMemory}!Self {
            const arena = try alloc.create(ArenaAllocator);
            arena.* = ArenaAllocator.init(alloc);
            return .{
                .arena = arena,
                .scanner = try Scanner.init(reader, alloc),
            };
        }

        pub fn deinit(self: *Self) void {
            self.scanner.deinit();
        }

        fn nextToken(self: *Self, hint: ?Scanner.Hint) Error!Token {
            if (!self.advance) {
                if (self.current_token) |ct| {
                    self.advance = true;
                    if (debug) std.debug.print("token={any} (no advance) {s}\n", .{ ct.kind, ct.content });
                    return ct;
                }
            }
            const t = try self.scanner.next(hint);
            self.current_token = t;
            self.token_location = t.location;
            if (debug) std.debug.print("token={any} {s}\n", .{ t.kind, t.content });
            return t;
        }

        // Ungets the current token so it will be returned again on the next call to nextToken.
        fn ungetToken(self: *Self) void {
            self.advance = false;
        }

        fn peekNextTokenKind(self: *Self, expected_closing_token: TokenKind) Error!TokenKind {
            const hint: ?Scanner.Hint = if (expected_closing_token == .double_right_bracket) .after_double_bracket else null;
            const tt = try self.nextToken(hint);
            if (debug) std.debug.print("// tt = {any}, expected={any}\n", .{ tt.kind, expected_closing_token });
            self.ungetToken();
            return tt.kind;
        }

        fn skipLineBreaks(self: *Self, hint: ?Scanner.Hint) Error!void {
            while (true) {
                const t = try self.nextToken(hint);
                if (t.kind != .line_break) {
                    self.ungetToken();
                    break;
                }
            }
        }

        fn parseDocument(self: *Self) Error!TomlTable {
            var root_table = TomlTable.empty;
            var current_table = &root_table;

            while (true) {
                const token = try self.nextToken(.top_level);
                switch (token.kind) {
                    .bare_key, .string => {
                        self.ungetToken();
                        const result = try self.parseKeyChain(current_table, .equal);
                        result.value_ptr.* = try self.parseValue();
                    },
                    .left_bracket => current_table = try self.parseTableHeader(&root_table, .right_bracket),
                    .double_left_bracket => current_table = try self.parseTableHeader(&root_table, .double_right_bracket),
                    .line_break => {},
                    .end_of_document => break,
                    else => return error.UnexpectedToken,
                }
            }

            return root_table;
        }

        fn parseTableHeader(self: *Self, root_table: *TomlTable, expected_closing_token: TokenKind) Error!*TomlTable {
            const result = try self.parseKeyChain(root_table, expected_closing_token);

            switch (expected_closing_token) {
                .right_bracket => {
                    if (!result.found_existing) result.value_ptr.* = TomlValue{ .table = TomlTable.empty };
                    return &result.value_ptr.table;
                },
                .double_right_bracket => {
                    if (!result.found_existing) result.value_ptr.* = TomlValue{ .array = TomlArray.empty };
                    try result.value_ptr.array.append(self.arena.allocator(), TomlValue{ .table = TomlTable.empty });
                    return &result.value_ptr.array.last().?.table;
                },
                else => unreachable,
            }
        }

        fn parseValue(self: *Self) Error!TomlValue {
            const token = try self.nextToken(.expect_value);
            if (debug) std.debug.print("parseValue kind = {}, context = {s} loc = {any}\n", .{ token.kind, token.content, token.location });

            switch (token.kind) {
                .string, .string_multiline => return TomlValue{ .string = try self.arena.allocator().dupe(u8, token.content) },
                .integer => return TomlValue{ .integer = try std.fmt.parseInt(i64, token.content, 0) },
                .float => return TomlValue{ .float = try std.fmt.parseFloat(f64, token.content) },
                .true => return TomlValue{ .boolean = true },
                .false => return TomlValue{ .boolean = false },

                .left_bracket => return self.parseArrayValue(),
                .left_brace => return self.parseInlineTable(),

                .date => return TomlValue{ .date = try DateTypes.parseDate(token.content, self.arena.allocator()) },
                .time => return TomlValue{ .time = try DateTypes.parseTime(token.content, self.arena.allocator()) },
                .datetime => return TomlValue{ .datetime = try DateTypes.parseDatetime(token.content, self.arena.allocator()) },
                .datetime_local => return TomlValue{ .datetime_local = try DateTypes.parseDatetimeLocal(token.content, self.arena.allocator()) },

                else => return error.UnexpectedToken,
            }
        }

        fn parseInlineTable(self: *Self) Error!TomlValue {
            var table = TomlTable.empty;

            while (true) {
                try self.skipLineBreaks(null);

                var token = try self.nextToken(null);
                switch (token.kind) {
                    .bare_key, .string => {
                        self.ungetToken();
                        const result = try self.parseKeyChain(&table, .equal);
                        result.value_ptr.* = try self.parseValue();

                        try self.skipLineBreaks(null);
                        token = try self.nextToken(null);
                        switch (token.kind) {
                            .comma => {},
                            .right_brace => break,
                            else => return error.UnexpectedToken,
                        }
                    },
                    .right_brace => break,
                    else => return error.UnexpectedToken,
                }
            }
            return TomlValue{ .table = table };
        }

        fn parseArrayValue(self: *Self) Error!TomlValue {
            var ar = TomlArray.empty;
            while (true) {
                try self.skipLineBreaks(.expect_value);
                var token = try self.nextToken(.expect_value);
                if (token.kind == .right_bracket) break;
                self.ungetToken();

                try ar.append(self.arena.allocator(), try self.parseValue());
                try self.skipLineBreaks(null);
                token = try self.nextToken(null);
                switch (token.kind) {
                    .comma => {},
                    .right_bracket => break,
                    else => return error.UnexpectedToken,
                }
            }
            return TomlValue{ .array = ar };
        }

        fn parseKeyChain(self: *Self, table: *TomlTable, expected_closing_token: TokenKind) Error!TomlTable.GetOrPutResult {
            const alloc = self.arena.allocator();
            var token = try self.nextToken(null);
            if (token.kind != .string and token.kind != .bare_key) return error.UnexpectedToken;

            const key = token.content;
            const result = try table.getOrPut(alloc, key);
            if (!result.found_existing) result.key_ptr.* = try alloc.dupe(u8, key);

            const hint: ?Scanner.Hint = if (expected_closing_token == .double_right_bracket) .after_double_bracket else null;
            token = try self.nextToken(hint);

            switch (token.kind) {
                .dot => {
                    if (debug) std.debug.print("parseKeyChain.dot key={s} found_existing={any}\n", .{ key, result.found_existing });

                    if (!result.found_existing) {
                        result.value_ptr.* = TomlValue{ .table = TomlTable.empty };
                    }
                    switch (result.value_ptr.*) {
                        .table => |*tab| return self.parseKeyChain(tab, expected_closing_token),
                        .array => |ar| return self.parseKeyChain(&ar.last().?.table, expected_closing_token),
                        else => unreachable,
                    }
                },
                .equal, .right_bracket, .double_right_bracket => {},
                else => return error.UnexpectedToken,
            }

            return result;
        }
    };
}
