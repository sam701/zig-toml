const std = @import("std");
const Scanner = @import("./scanner/root.zig").Scanner;
const Token = @import("./scanner/root.zig").Token;
const TokenKind = @import("./scanner/root.zig").TokenKind;
const Reader = std.Io.Reader;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const SourceLocation = @import("./scanner/source.zig").SourceLocation;

pub const Parsed = std.json.Parsed;
pub const Error = Scanner.Error || std.fmt.ParseIntError || std.fmt.ParseFloatError || std.mem.Allocator.Error || error{
    UnexpectedToken,
    NotStruct,
    InvalidValueType,
};

pub fn parse(comptime T: type, reader: *Reader, alloc: Allocator) Error!Parsed(T) {
    var p = try Parser.init(reader, alloc);
    defer p.deinit();
    return Parsed(T){
        .arena = p.arena,
        .value = try p.parseTopLevelStruct(T),
    };
}

const FieldMap = struct {
    inner: std.StringHashMap(FieldMap),

    fn init(alloc: Allocator) FieldMap {
        return .{ .inner = std.StringHashMap(FieldMap).init(alloc) };
    }

    fn deinit(self: *FieldMap) void {
        var it = self.inner.valueIterator();
        while (it.next()) |v| {
            v.deinit();
        }
        self.inner.deinit();
    }

    fn markFieldAsInitialized(self: *FieldMap, field_name: []const u8) error{OutOfMemory}!*FieldMap {
        if (!self.inner.contains(field_name)) {
            try self.inner.put(field_name, FieldMap.init(self.inner.allocator));
        }
        return self.inner.getPtr(field_name).?;
    }

    fn isInitialized(self: *const FieldMap, field_name: []const u8) bool {
        return self.inner.contains(field_name);
    }
};

const Parser = struct {
    arena: *ArenaAllocator,
    scanner: Scanner,
    token_location: ?SourceLocation = null,
    current_token: ?Token = null,
    advance: bool = true,
    top_level_field_map: FieldMap,

    pub fn init(reader: *Reader, alloc: Allocator) error{OutOfMemory}!Parser {
        const arena = try alloc.create(ArenaAllocator);
        arena.* = ArenaAllocator.init(alloc);
        return .{
            .arena = arena,
            .scanner = try Scanner.init(reader, alloc),
            .top_level_field_map = FieldMap.init(alloc),
        };
    }

    pub fn deinit(self: *Parser) void {
        self.scanner.deinit();
        self.top_level_field_map.deinit();
    }

    fn nextToken(self: *Parser, hint: ?Scanner.Hint) Error!Token {
        if (!self.advance) {
            if (self.current_token) |ct| {
                self.advance = true;
                std.debug.print("token={any} (no advance) {s}\n", .{ ct.kind, ct.content });
                return ct;
            }
        }
        const t = try self.scanner.next(hint);
        self.current_token = t;
        self.token_location = t.location;
        std.debug.print("token={any} {s}\n", .{ t.kind, t.content });
        return t;
    }
    fn pushBack(self: *Parser) void {
        self.advance = false;
    }

    fn parseTopLevelStruct(self: *Parser, comptime T: type) Error!T {
        const ti = @typeInfo(T);
        if (ti != .@"struct") return error.NotStruct;

        var result: T = undefined;

        while (true) {
            const token = try self.nextToken(.top_level);

            switch (token.kind) {
                .bare_key, .string => {
                    try self.parseKey(T, &result, token.content, .equal, &self.top_level_field_map);
                },
                .left_bracket => try self.parseTableHeader(T, &result, .right_bracket, &self.top_level_field_map),
                .double_left_bracket => unreachable,
                .line_break => {},
                .end_of_document => break,
                else => return error.UnexpectedToken,
            }
        }

        return result;
    }

    fn parseTableHeader(self: *Parser, comptime T: type, dest: *T, expected_token: TokenKind, field_map: *FieldMap) Error!void {
        const token = try self.nextToken(null);
        switch (token.kind) {
            .bare_key, .string => {
                try self.parseKey(T, dest, token.content, expected_token, field_map);
            },
            else => return error.UnexpectedToken,
        }
    }

    fn parseTableContent(self: *Parser, comptime T: type, dest: *T, field_map: *FieldMap) Error!void {
        const ti = @typeInfo(T);
        if (ti != .@"struct") return error.NotStruct;

        while (true) {
            const token = try self.nextToken(.top_level);

            switch (token.kind) {
                .bare_key, .string => {
                    try self.parseKey(T, dest, token.content, .equal, field_map);
                },
                .left_bracket, .double_left_bracket, .end_of_document => {
                    self.pushBack();
                    break;
                },
                .line_break => {},
                else => return error.UnexpectedToken,
            }
        }
    }

    fn parseValue(self: *Parser, comptime T: type, field_map: *FieldMap) Error!T {
        const ti = @typeInfo(T);

        const token = try self.nextToken(.expect_value);
        // std.debug.print("kind = {}, context = {s} loc = {any}\n", .{ token.kind, token.content, token.location });
        switch (ti) {
            .int => {
                if (token.kind != .number) return error.InvalidValueType;
                return std.fmt.parseInt(T, token.content, 0);
            },
            .float => {
                if (token.kind != .number) return error.InvalidValueType;
                return std.fmt.parseFloat(T, token.content);
            },
            .bool => {
                switch (token.kind) {
                    .true => return true,
                    .false => return false,
                    else => return error.InvalidValueType,
                }
            },
            .pointer => |pi| {
                if (pi.size == .one) {
                    self.pushBack();
                    const result = try self.arena.allocator().create(pi.child);
                    result.* = try self.parseInnerTable(pi.child, field_map);
                    return result;
                }
                switch (pi.child) {
                    u8 => {
                        switch (token.kind) {
                            .string, .string_multiline => {
                                return self.arena.allocator().dupe(u8, token.content);
                            },
                            else => return error.InvalidValueType,
                        }
                    },
                    else => {
                        if (token.kind != .left_bracket) return error.UnexpectedToken;
                        return self.parseArrayValue(pi.child, field_map);
                    },
                }
            },
            .array => |ti2| {
                switch (ti2.child) {
                    u8 => {
                        switch (token.kind) {
                            .string, .string_multiline => {
                                var r: T = undefined;
                                if (r.len != token.content.len) return error.InvalidValueType;
                                @memcpy(&r, token.content);
                                return r;
                            },
                            else => return error.InvalidValueType,
                        }
                    },
                    else => unreachable,
                }
            },
            .@"struct" => {
                self.pushBack();
                return self.parseInnerTable(T, field_map);
            },

            else => {},
        }

        unreachable;
    }

    fn parseInnerTable(self: *Parser, comptime T: type, field_map: *FieldMap) Error!T {
        const ti = @typeInfo(T);
        if (ti != .@"struct") return error.NotStruct;

        var result: T = undefined;

        var token = try self.nextToken(null);
        if (token.kind != .left_brace) return error.UnexpectedToken;

        while (true) {
            token = try self.nextToken(null);
            switch (token.kind) {
                .bare_key, .string => {
                    try self.parseKey(T, &result, token.content, .equal, field_map);
                },
                else => return error.UnexpectedToken,
            }

            token = try self.nextToken(null);
            switch (token.kind) {
                .comma => {},
                .right_brace => break,
                else => return error.UnexpectedToken,
            }
        }

        return result;
    }

    fn parseArrayValue(self: *Parser, comptime T: type, field_map: *FieldMap) Error![]T {
        var ar = std.ArrayList(T).empty;
        while (true) {
            try self.skipLineBreaks(.expect_value);
            var token = try self.nextToken(.expect_value);
            if (token.kind == .right_bracket) break;
            self.pushBack();

            try ar.append(self.arena.allocator(), try self.parseValue(T, field_map));
            try self.skipLineBreaks(null);
            token = try self.nextToken(null);
            switch (token.kind) {
                .comma => {},
                .right_bracket => break,
                else => return error.UnexpectedToken,
            }
        }
        return ar.toOwnedSlice(self.arena.allocator());
    }

    fn skipLineBreaks(self: *Parser, hint: ?Scanner.Hint) Error!void {
        while (true) {
            const t = try self.nextToken(hint);
            if (t.kind != .line_break) {
                self.pushBack();
                break;
            }
        }
    }

    fn parseKey(self: *Parser, comptime T: type, dest: *T, key: []const u8, expected_token: TokenKind, field_map: *FieldMap) Error!void {
        const ti = @typeInfo(T);
        inline for (ti.@"struct".fields) |field| {
            if (std.mem.eql(u8, field.name, key)) {
                // TODO: allocate if the field is a pointer
                const child_map = try field_map.markFieldAsInitialized(field.name);
                try self.parseAfterKey(field.type, &@field(dest, field.name), expected_token, child_map);
                return;
            }
        }

        return error.UnexpectedToken;
    }

    fn parseAfterKey(self: *Parser, comptime T: type, dest: *T, expected_token: TokenKind, field_map: *FieldMap) Error!void {
        const token = try self.nextToken(null);
        if (token.kind == .dot) {
            try self.parseAfterDot(T, dest, expected_token, field_map);
        } else {
            if (token.kind != expected_token) return error.UnexpectedToken;
            if (token.kind == .equal) {
                dest.* = try self.parseValue(T, field_map);
            } else {
                try self.parseTableContent(T, dest, field_map);
            }
        }
    }

    fn parseAfterDot(self: *Parser, comptime T: type, dest: *T, expected_token: TokenKind, field_map: *FieldMap) Error!void {
        const token = try self.nextToken(null);
        if (token.kind != .bare_key and token.kind != .string) return error.UnexpectedToken;

        const ti = @typeInfo(T);
        if (ti != .@"struct") return error.UnexpectedToken;

        try self.parseKey(T, dest, token.content, expected_token, field_map);
    }
};
