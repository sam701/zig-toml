const std = @import("std");
const Scanner = @import("./scanner/root.zig").Scanner;
const Token = @import("./scanner/root.zig").Token;
const TokenKind = @import("./scanner/root.zig").TokenKind;
const Reader = std.Io.Reader;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const SourceLocation = @import("./scanner/source.zig").SourceLocation;
const allocation = @import("./allocation.zig");
const value = @import("./value2.zig");

pub const Parsed = std.json.Parsed;
pub const Error = Scanner.Error || std.fmt.ParseIntError || std.fmt.ParseFloatError || std.mem.Allocator.Error || value.Error || error{
    UnexpectedToken,
    NotStruct,
    InvalidValueType,
};

// TODO: add options that can specify
// - how to treat missing fields,
// - how to treat non-existing fields
//
// TODO: set not-provided optional fields to null.

/// Parse TOML from a reader into type T.
/// Datetime values (date, datetime, datetime-local, time) are returned as strings.
pub fn parse(comptime T: type, reader: *Reader, alloc: Allocator) Error!Parsed(T) {
    return parseWith(T, reader, alloc, value.DefaultDateTypes);
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
    return Parsed(T){
        .arena = p.arena,
        .value = try p.parseTopLevelStruct(T),
    };
}

const HashMapInfo = struct {
    is_hashmap: bool,
    value_type: ?type = null,
};

fn getHashMapInfo(comptime T: type) ?type {
    if (!@hasDecl(T, "put")) return null;
    const put_fn_info = @typeInfo(@TypeOf(T.put)).@"fn";
    if (put_fn_info.params.len != 4) return null;

    // Verify key type is []const u8 (param[2] is the key)
    const KeyType = put_fn_info.params[2].type.?;
    if (KeyType != []const u8) return null;

    return put_fn_info.params[3].type.?;
}

fn Parser(comptime DateTypes: type) type {
    const TomlValue = value.Value(DateTypes);

    return struct {
        arena: *ArenaAllocator,
        scanner: Scanner,
        token_location: ?SourceLocation = null,
        current_token: ?Token = null,
        advance: bool = true,
        top_level_object: allocation.StructField,
        slice_finalizers: std.ArrayList(allocation.SliceFinalizer) = .empty,

        const Self = @This();

        pub fn init(reader: *Reader, alloc: Allocator) error{OutOfMemory}!Self {
            const arena = try alloc.create(ArenaAllocator);
            arena.* = ArenaAllocator.init(alloc);
            return .{
                .arena = arena,
                .scanner = try Scanner.init(reader, alloc),
                .top_level_object = allocation.StructField.init(alloc),
            };
        }

        pub fn deinit(self: *Self) void {
            self.scanner.deinit();
            self.top_level_object.deinit();
            self.slice_finalizers.deinit(self.arena.allocator());
        }

        fn nextToken(self: *Self, hint: ?Scanner.Hint) Error!Token {
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

        // Ungets the current token so it will be returned again on the next call to nextToken.
        fn ungetToken(self: *Self) void {
            self.advance = false;
        }

        fn peekNextTokenKind(self: *Self, expected_closing_token: TokenKind) Error!TokenKind {
            const hint: ?Scanner.Hint = if (expected_closing_token == .double_right_bracket) .after_double_bracket else null;
            const tt = try self.nextToken(hint);
            std.debug.print("// tt = {any}, expected={any}\n", .{ tt.kind, expected_closing_token });
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

        fn parseTopLevelStruct(self: *Self, comptime T: type) Error!T {
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

            // Run all finalizers
            for (self.slice_finalizers.items) |finalizer| {
                finalizer.finalize_fn(finalizer.context, self.arena.allocator());
            }

            return result;
        }

        fn parseTableHeader(self: *Self, comptime T: type, dest: *T, expected_closing_token: TokenKind, object_info: *allocation.StructField) Error!void {
            const token = try self.nextToken(null);
            switch (token.kind) {
                .bare_key, .string => {
                    try self.parseKey(T, dest, token.content, expected_closing_token, object_info);
                },
                else => return error.UnexpectedToken,
            }
        }

        fn parseTableContent(self: *Self, comptime T: type, dest: *T, object_info: *allocation.StructField) Error!void {
            const ti = @typeInfo(T);
            if (ti != .@"struct") return error.NotStruct;

            while (true) {
                const token = try self.nextToken(.top_level);

                switch (token.kind) {
                    .bare_key, .string => try self.parseKey(T, dest, token.content, .equal, object_info),
                    .left_bracket, .double_left_bracket, .end_of_document => {
                        self.ungetToken();
                        break;
                    },
                    .line_break => {},
                    else => return error.UnexpectedToken,
                }
            }
        }

        fn parseDatetime(
            self: *Self,
            comptime T: type,
            comptime parseFn: anytype,
            content: []const u8,
        ) Error!T {
            const ParseReturnType = @typeInfo(@TypeOf(parseFn)).@"fn".return_type.?;
            const return_type_info = @typeInfo(ParseReturnType);

            if (return_type_info == .error_union and return_type_info.error_union.payload == T) {
                return parseFn(content, self.arena.allocator());
            }

            return error.InvalidValueType;
        }

        fn parseValue(self: *Self, comptime ValueType: type, struct_allocation_info: *allocation.StructField) Error!ValueType {
            const ti = @typeInfo(ValueType);

            const token = try self.nextToken(.expect_value);
            std.debug.print("parseValue kind = {}, context = {s} loc = {any}\n", .{ token.kind, token.content, token.location });

            if (ValueType == TomlValue) {
                self.ungetToken();
                switch (token.kind) {
                    .string, .string_multiline => return TomlValue{ .string = try self.parseValue([]const u8, struct_allocation_info) },
                    .number => return TomlValue{ .number = try self.parseValue(f64, struct_allocation_info) },
                    .true, .false => return TomlValue{ .boolean = try self.parseValue(bool, struct_allocation_info) },

                    .left_bracket => return TomlValue{ .array = try self.parseValue([]const TomlValue, struct_allocation_info) },
                    .left_brace => return TomlValue{ .table = try self.parseValue(std.StringHashMapUnmanaged(TomlValue), struct_allocation_info) },

                    .date => return TomlValue{ .date = try self.parseValue(DateTypes.Date, struct_allocation_info) },
                    .time => return TomlValue{ .time = try self.parseValue(DateTypes.Time, struct_allocation_info) },
                    .datetime => return TomlValue{ .datetime = try self.parseValue(DateTypes.DateTime, struct_allocation_info) },
                    .datetime_local => return TomlValue{ .datetime_local = try self.parseValue(DateTypes.DateTimeLocal, struct_allocation_info) },

                    else => return error.UnexpectedToken,
                }
            }

            switch (token.kind) {
                .date => return self.parseDatetime(ValueType, DateTypes.parseDate, token.content),
                .datetime => return self.parseDatetime(ValueType, DateTypes.parseDatetime, token.content),
                .datetime_local => return self.parseDatetime(ValueType, DateTypes.parseDatetimeLocal, token.content),
                .time => return self.parseDatetime(ValueType, DateTypes.parseTime, token.content),
                else => {},
            }

            switch (ti) {
                .int => {
                    if (token.kind != .number) return error.InvalidValueType;
                    return std.fmt.parseInt(ValueType, token.content, 0);
                },
                .float => {
                    if (token.kind != .number) return error.InvalidValueType;
                    return std.fmt.parseFloat(ValueType, token.content);
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
                        self.ungetToken();
                        const result = try self.arena.allocator().create(pi.child);
                        result.* = try self.parseInnerTable(pi.child, struct_allocation_info);
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
                            return self.parseArrayValue(pi.child, struct_allocation_info);
                        },
                    }
                },
                .array => |ti2| {
                    switch (ti2.child) {
                        u8 => {
                            switch (token.kind) {
                                .string, .string_multiline => {
                                    var r: ValueType = undefined;
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
                    self.ungetToken();
                    return self.parseInnerTable(ValueType, struct_allocation_info);
                },
                .optional => |tinfo| {
                    if (token.kind == .null)
                        return @as(ValueType, null);

                    self.ungetToken();
                    return @as(ValueType, try self.parseValue(tinfo.child, struct_allocation_info));
                },
                .@"enum" => {
                    switch (token.kind) {
                        .string => {
                            return std.meta.stringToEnum(ValueType, token.content) orelse return error.InvalidValueType;
                        },
                        else => return error.InvalidValueType,
                    }
                },
                .@"union" => return self.parseUnionValue(ValueType, token, struct_allocation_info),

                else => {},
            }

            unreachable;
        }

        fn parseInnerTable(self: *Self, comptime InnerTableType: type, object_info: *allocation.StructField) Error!InnerTableType {
            const ti = @typeInfo(InnerTableType);
            if (ti != .@"struct") return error.NotStruct;

            var result: InnerTableType = undefined;

            // TODO: needs review
            if (getHashMapInfo(InnerTableType) != null) result = .{};

            var token = try self.nextToken(null);
            if (token.kind != .left_brace) return error.UnexpectedToken;

            while (true) {
                token = try self.nextToken(null);
                switch (token.kind) {
                    .bare_key, .string => {
                        try self.parseKey(InnerTableType, &result, token.content, .equal, object_info);
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

        fn parseArrayValue(self: *Self, comptime T: type, object_info: *allocation.StructField) Error![]T {
            var ar = std.ArrayList(T).empty;
            while (true) {
                try self.skipLineBreaks(.expect_value);
                var token = try self.nextToken(.expect_value);
                if (token.kind == .right_bracket) break;
                self.ungetToken();

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

        fn processPointerToOne(
            self: *Self,
            comptime ObjectType: type,
            dest: *ObjectType,
            comptime FieldType: type,
            comptime field_name: []const u8,
            expected_closing_token: TokenKind,
            object_info: *allocation.StructField,
        ) Error!void {
            const result = try object_info.fields.getOrPut(field_name);
            if (!result.found_existing) {
                std.debug.print("== initializing .one {s}\n", .{field_name});
                @field(dest, field_name) = try self.arena.allocator().create(FieldType);

                result.value_ptr.* = allocation.AllocatedStructField{ .object = allocation.StructField.init(self.arena.allocator()) };
            }

            try self.parseAfterKey(FieldType, @field(dest, field_name), expected_closing_token, &result.value_ptr.object);
        }

        fn processPointerToMany(
            self: *Self,
            comptime ObjectType: type,
            dest: *ObjectType,
            comptime FieldType: type,
            comptime field_name: []const u8,
            expected_closing_token: TokenKind,
            object_info: *allocation.StructField,
        ) Error!void {
            const FieldValueArrayList = std.ArrayList(FieldType);
            const result = try object_info.fields.getOrPut(field_name);
            if (!result.found_existing) {
                const list = try self.arena.allocator().create(FieldValueArrayList);
                list.* = .{};

                result.value_ptr.* = allocation.AllocatedStructField{ .array = allocation.ArrayField.init(self.arena.allocator(), @ptrCast(list)) };

                // Register finalizer to set dest field to toOwnedSlice
                const finalizer = try allocation.SliceFinalizer.init(
                    ObjectType,
                    FieldType,
                    field_name,
                    dest,
                    result.value_ptr.array.field_values_array_list,
                    self.arena.allocator(),
                );

                try self.slice_finalizers.append(self.arena.allocator(), finalizer);
            }

            var ar: *FieldValueArrayList = @ptrCast(@alignCast(result.value_ptr.array.field_values_array_list));
            const value_ptr = try ar.addOne(self.arena.allocator());

            // TODO: how do we know that it's AllocatedStructField? It can be another array.
            try result.value_ptr.array.objects.append(self.arena.allocator(), allocation.AllocatedStructField{ .object = allocation.StructField.init(self.arena.allocator()) });

            try self.parseAfterKey(FieldType, value_ptr, expected_closing_token, &result.value_ptr.array.objects.items[result.value_ptr.array.objects.items.len - 1].object);
        }

        fn parseUnionValue(
            self: *Self,
            comptime ObjectType: type,
            token: Token,
            object_info: *allocation.StructField,
        ) Error!ObjectType {
            const union_info = @typeInfo(ObjectType).@"union";

            switch (token.kind) {
                // For void-payload unions, accept a string as the tag name
                .string => {
                    inline for (union_info.fields) |field| {
                        if (std.mem.eql(u8, field.name, token.content)) {
                            if (field.type == void) {
                                return @unionInit(ObjectType, field.name, {});
                            } else break;
                        }
                    }
                },
                // For non-void payload unions, parse as inline table with single field
                .left_brace => {
                    const key_token = try self.nextToken(null);
                    if (key_token.kind != .bare_key and key_token.kind != .string) return error.UnexpectedToken;

                    inline for (union_info.fields) |field| {
                        if (std.mem.eql(u8, field.name, key_token.content)) {
                            const eq_token = try self.nextToken(null);
                            if (eq_token.kind != .equal) return error.UnexpectedToken;

                            const val = try self.parseValue(field.type, object_info);

                            const close_token = try self.nextToken(null);
                            if (close_token.kind != .right_brace) return error.UnexpectedToken;

                            return @unionInit(ObjectType, field.name, val);
                        }
                    }
                },
                else => {},
            }
            return error.InvalidValueType;
        }

        fn parseUnionTagKey(
            self: *Self,
            comptime ObjectType: type,
            dest: *ObjectType,
            comptime UnionType: type,
            comptime field_name: []const u8,
            expected_closing_token: TokenKind,
            object_info: *allocation.StructField,
        ) Error!void {
            const union_info = @typeInfo(UnionType).@"union";

            const union_tag_token = try self.nextToken(null);
            if (union_tag_token.kind != .bare_key and union_tag_token.kind != .string) {
                return error.UnexpectedToken;
            }

            inline for (union_info.fields) |union_field| {
                if (std.mem.eql(u8, union_field.name, union_tag_token.content)) {
                    const tag_name = union_tag_token.content;

                    if (object_info.fields.contains(field_name)) {
                        // Assert it's the same tag as before
                        const active_tag_name = @tagName(std.meta.activeTag(@field(dest, field_name)));
                        if (!std.mem.eql(u8, active_tag_name, tag_name)) return error.InvalidValueType;
                    } else {
                        // Set the union to the correct tag if not already set
                        @field(dest, field_name) = @unionInit(UnionType, union_field.name, undefined);
                    }

                    const obj_info = try object_info.markAsObject(field_name);
                    return self.parseAfterKey(
                        union_field.type,
                        &@field(@field(dest, field_name), union_field.name),
                        expected_closing_token,
                        obj_info,
                    );
                }
            }
            return error.UnexpectedToken;
        }

        fn parseKey(
            self: *Self,
            comptime ObjectType: type,
            object: *ObjectType,
            key: []const u8,
            expected_closing_token: TokenKind,
            object_info: *allocation.StructField,
        ) Error!void {
            // Handle types with a put method (like StringHashMapUnmanaged)
            if (getHashMapInfo(ObjectType)) |ValueType| {
                var val: ValueType = undefined;
                const obj_info = try object_info.markAsObject(key);
                const key_copy = try self.arena.allocator().dupe(u8, key);
                try self.parseAfterKey(ValueType, &val, expected_closing_token, obj_info);
                std.debug.print("== type = {s}, key = {s}, val = {any}\n", .{ @typeName(ValueType), key_copy, val });
                try object.put(self.arena.allocator(), key_copy, val);

                return;
            }
            const dest_type_info = @typeInfo(ObjectType);
            inline for (dest_type_info.@"struct".fields) |field| {
                if (std.mem.eql(u8, field.name, key))
                    return self.parseKeyMatchedField(ObjectType, object, field, expected_closing_token, object_info);
            }

            return error.UnexpectedToken;
        }

        fn parseKeyMatchedField(
            self: *Self,
            comptime ObjectType: type,
            object: *ObjectType,
            field: std.builtin.Type.StructField,
            expected_closing_token: TokenKind,
            alloc_info: *allocation.StructField,
        ) Error!void {
            const field_type_info = @typeInfo(field.type);
            switch (field_type_info) {
                .pointer => {
                    switch (field_type_info.pointer.size) {
                        .one => return self.processPointerToOne(ObjectType, object, field_type_info.pointer.child, field.name, expected_closing_token, alloc_info),
                        .slice => {},
                        else => unreachable,
                    }
                    switch (field_type_info.pointer.child) {
                        u8 => {},
                        else => {
                            if (try self.peekNextTokenKind(expected_closing_token) != .equal) {
                                return self.processPointerToMany(ObjectType, object, field_type_info.pointer.child, field.name, expected_closing_token, alloc_info);
                            }
                        },
                    }
                },
                // Handle union types with dotted notation (e.g., union1.tag_name = 42)
                .@"union" => {
                    const next_token = try self.nextToken(null);
                    if (next_token.kind == .dot) {
                        return self.parseUnionTagKey(ObjectType, object, field.type, field.name, expected_closing_token, alloc_info);
                    } else {
                        self.ungetToken();
                    }
                },
                else => {},
            }

            const obj_info = try alloc_info.markAsObject(field.name);
            return self.parseAfterKey(field.type, &@field(object, field.name), expected_closing_token, obj_info);
        }

        fn parseAfterKey(self: *Self, comptime ValueType: type, value_ptr: *ValueType, expected_closing_token: TokenKind, object_info: *allocation.StructField) Error!void {
            const token = try self.nextToken(null);
            if (token.kind == .dot) {
                const after_dot_token = try self.nextToken(null);
                if (after_dot_token.kind != .bare_key and after_dot_token.kind != .string) return error.UnexpectedToken;

                const ti = @typeInfo(ValueType);
                if (ti != .@"struct") return error.UnexpectedToken;

                try self.parseKey(ValueType, value_ptr, after_dot_token.content, expected_closing_token, object_info);
            } else {
                if (token.kind != expected_closing_token) return error.UnexpectedToken;
                if (token.kind == .equal) {
                    value_ptr.* = try self.parseValue(ValueType, object_info);
                } else {
                    try self.parseTableContent(ValueType, value_ptr, object_info);
                }
            }
        }
    };
}
