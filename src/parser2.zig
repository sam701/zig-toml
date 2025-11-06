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

const Value = union(enum) {
    object: ObjectInfo,
    array: ObjectArray,

    fn deinit(self: *Value) void {
        switch (self.*) {
            inline else => |*x| x.deinit(),
        }
    }
};

const ObjectArray = struct {
    alloc: Allocator,
    objects: std.ArrayList(Value),
    field_values_array_list: *anyopaque,

    fn init(alloc: Allocator, real_values_ptr: *anyopaque) ObjectArray {
        return .{
            .objects = std.ArrayList(Value).empty,
            .alloc = alloc,
            .field_values_array_list = real_values_ptr,
        };
    }

    fn deinit(self: *ObjectArray) void {
        for (self.objects.items) |*obj| {
            obj.deinit();
        }
        self.objects.deinit(self.alloc);
    }
};

const ObjectInfo = struct {
    fields: std.StringHashMap(Value),

    fn init(alloc: Allocator) ObjectInfo {
        return .{ .fields = std.StringHashMap(Value).init(alloc) };
    }

    fn deinit(self: *ObjectInfo) void {
        var it = self.fields.valueIterator();
        while (it.next()) |v| {
            v.deinit();
        }
        self.fields.deinit();
    }

    fn markAsObject(self: *ObjectInfo, field_name: []const u8) error{OutOfMemory}!*ObjectInfo {
        const result = try self.fields.getOrPut(field_name);
        if (!result.found_existing) {
            result.value_ptr.* = Value{ .object = ObjectInfo.init(self.fields.allocator) };
        }

        return &result.value_ptr.object;
    }

    fn markAsArray(self: *ObjectInfo, field_name: []const u8) error{OutOfMemory}!*ObjectArray {
        const result = try self.fields.getOrPut(field_name);
        if (!result.found_existing) {
            result.value_ptr.* = Value{ .array = ObjectArray.init(self.fields.allocator) };
        }

        return &result.value_ptr.array;
    }
};

const Parser = struct {
    arena: *ArenaAllocator,
    scanner: Scanner,
    token_location: ?SourceLocation = null,
    current_token: ?Token = null,
    advance: bool = true,
    top_level_object: ObjectInfo,

    pub fn init(reader: *Reader, alloc: Allocator) error{OutOfMemory}!Parser {
        const arena = try alloc.create(ArenaAllocator);
        arena.* = ArenaAllocator.init(alloc);
        return .{
            .arena = arena,
            .scanner = try Scanner.init(reader, alloc),
            .top_level_object = ObjectInfo.init(alloc),
        };
    }

    pub fn deinit(self: *Parser) void {
        self.scanner.deinit();
        self.top_level_object.deinit();
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

        // TODO: it can be a pointer to a struct.
        if (ti != .@"struct") return error.NotStruct;

        var result: T = undefined;

        while (true) {
            const token = try self.nextToken(.top_level);

            switch (token.kind) {
                .bare_key, .string => {
                    try self.parseKey(T, &result, token.content, .equal, &self.top_level_object);
                },
                .left_bracket => try self.parseTableHeader(T, &result, .right_bracket, &self.top_level_object),
                .double_left_bracket => try self.parseTableHeader(T, &result, .double_right_bracket, &self.top_level_object),
                .line_break => {},
                .end_of_document => break,
                else => return error.UnexpectedToken,
            }
        }

        return result;
    }

    fn parseTableHeader(self: *Parser, comptime T: type, dest: *T, expected_token: TokenKind, object_info: *ObjectInfo) Error!void {
        const token = try self.nextToken(null);
        switch (token.kind) {
            .bare_key, .string => {
                try self.parseKey(T, dest, token.content, expected_token, object_info);
            },
            else => return error.UnexpectedToken,
        }
    }

    fn parseTableContent(self: *Parser, comptime T: type, dest: *T, object_info: *ObjectInfo) Error!void {
        const ti = @typeInfo(T);
        if (ti != .@"struct") return error.NotStruct;

        while (true) {
            const token = try self.nextToken(.top_level);

            switch (token.kind) {
                .bare_key, .string => try self.parseKey(T, dest, token.content, .equal, object_info),
                .left_bracket, .double_left_bracket, .end_of_document => {
                    self.pushBack();
                    break;
                },
                .line_break => {},
                else => return error.UnexpectedToken,
            }
        }
    }

    fn parseValue(self: *Parser, comptime T: type, object_info: *ObjectInfo) Error!T {
        const ti = @typeInfo(T);

        const token = try self.nextToken(.expect_value);
        std.debug.print("parseValue kind = {}, context = {s} loc = {any}\n", .{ token.kind, token.content, token.location });
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
                    result.* = try self.parseInnerTable(pi.child, object_info);
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
                        return self.parseArrayValue(pi.child, object_info);
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
                return self.parseInnerTable(T, object_info);
            },

            else => {},
        }

        unreachable;
    }

    fn parseInnerTable(self: *Parser, comptime T: type, object_info: *ObjectInfo) Error!T {
        const ti = @typeInfo(T);
        if (ti != .@"struct") return error.NotStruct;

        var result: T = undefined;

        var token = try self.nextToken(null);
        if (token.kind != .left_brace) return error.UnexpectedToken;

        while (true) {
            token = try self.nextToken(null);
            switch (token.kind) {
                .bare_key, .string => {
                    try self.parseKey(T, &result, token.content, .equal, object_info);
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

    fn parseArrayValue(self: *Parser, comptime T: type, object_info: *ObjectInfo) Error![]T {
        var ar = std.ArrayList(T).empty;
        while (true) {
            try self.skipLineBreaks(.expect_value);
            var token = try self.nextToken(.expect_value);
            if (token.kind == .right_bracket) break;
            self.pushBack();

            try ar.append(self.arena.allocator(), try self.parseValue(T, object_info));
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

    fn processPointerToOne(self: *Parser, comptime T: type, dest: *T, comptime FieldType: type, comptime field_name: []const u8, expected_token: TokenKind, object_info: *ObjectInfo) Error!void {
        const result = try object_info.fields.getOrPut(field_name);
        if (!result.found_existing) {
            std.debug.print("== initializing .one {s}\n", .{field_name});
            @field(dest, field_name) = try self.arena.allocator().create(FieldType);

            result.value_ptr.* = Value{ .object = ObjectInfo.init(self.arena.allocator()) };
        }

        try self.parseAfterKey(FieldType, @field(dest, field_name), expected_token, &result.value_ptr.object);
    }

    fn processPointerToMany(self: *Parser, comptime T: type, dest: *T, comptime FieldType: type, comptime field_name: []const u8, expected_token: TokenKind, object_info: *ObjectInfo) Error!void {
        const FieldValueArrayList = std.ArrayList(FieldType);
        const result = try object_info.fields.getOrPut(field_name);
        if (!result.found_existing) {
            std.debug.print("== initializing .slice {s}\n", .{field_name});

            const list = try self.arena.allocator().create(FieldValueArrayList);
            list.* = .{};

            result.value_ptr.* = Value{ .array = ObjectArray.init(self.arena.allocator(), @ptrCast(list)) };
        }

        var ar: *FieldValueArrayList = @ptrCast(@alignCast(result.value_ptr.array.field_values_array_list));
        const value_ptr = try ar.addOne(self.arena.allocator());
        @field(dest, field_name) = ar.items;

        try result.value_ptr.array.objects.append(self.arena.allocator(), Value{ .object = ObjectInfo.init(self.arena.allocator()) });

        try self.parseAfterKey(FieldType, value_ptr, expected_token, &result.value_ptr.array.objects.items[result.value_ptr.array.objects.items.len - 1].object);
    }

    fn peekNextTokenKind(self: *Parser, expected_token: TokenKind) Error!TokenKind {
        const hint: ?Scanner.Hint = if (expected_token == .double_right_bracket) .after_double_bracket else null;
        const tt = try self.nextToken(hint);
        std.debug.print("// tt = {any}, expected={any}\n", .{ tt.kind, expected_token });
        self.pushBack();
        return tt.kind;
    }

    fn parseKey(self: *Parser, comptime T: type, dest: *T, key: []const u8, expected_token: TokenKind, object_info: *ObjectInfo) Error!void {
        const ti = @typeInfo(T);

        inline for (ti.@"struct".fields) |field| {
            if (std.mem.eql(u8, field.name, key)) {
                const fti = @typeInfo(field.type);
                if (fti == .pointer) {
                    switch (fti.pointer.size) {
                        .one => return self.processPointerToOne(T, dest, fti.pointer.child, field.name, expected_token, object_info),
                        .slice => {},
                        else => unreachable,
                    }
                    switch (fti.pointer.child) {
                        u8 => {},
                        else => {
                            if (try self.peekNextTokenKind(expected_token) != .equal) {
                                return self.processPointerToMany(T, dest, fti.pointer.child, field.name, expected_token, object_info);
                            }
                        },
                    }
                }

                const obj_info = try object_info.markAsObject(field.name);
                return self.parseAfterKey(field.type, &@field(dest, field.name), expected_token, obj_info);
            }
        }

        return error.UnexpectedToken;
    }

    fn parseAfterKey(self: *Parser, comptime T: type, dest: *T, expected_token: TokenKind, object_info: *ObjectInfo) Error!void {
        const token = try self.nextToken(null);
        if (token.kind == .dot) {
            try self.parseAfterDot(T, dest, expected_token, object_info);
        } else {
            if (token.kind != expected_token) return error.UnexpectedToken;
            if (token.kind == .equal) {
                dest.* = try self.parseValue(T, object_info);
            } else {
                try self.parseTableContent(T, dest, object_info);
            }
        }
    }

    fn parseAfterDot(self: *Parser, comptime T: type, dest: *T, expected_token: TokenKind, object_info: *ObjectInfo) Error!void {
        const token = try self.nextToken(null);
        if (token.kind != .bare_key and token.kind != .string) return error.UnexpectedToken;

        const ti = @typeInfo(T);
        if (ti != .@"struct") return error.UnexpectedToken;

        try self.parseKey(T, dest, token.content, expected_token, object_info);
    }
};
