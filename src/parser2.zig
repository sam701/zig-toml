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

const NoOpDateTimeParser = struct {
    pub fn parseDate(str: []const u8, alloc: Allocator) Error![]const u8 {
        return alloc.dupe(u8, str);
    }
    pub fn parseDatetime(str: []const u8, alloc: Allocator) Error![]const u8 {
        return alloc.dupe(u8, str);
    }
    pub fn parseDatetimeLocal(str: []const u8, alloc: Allocator) Error![]const u8 {
        return alloc.dupe(u8, str);
    }
    pub fn parseTime(str: []const u8, alloc: Allocator) Error![]const u8 {
        return alloc.dupe(u8, str);
    }
};

/// Parse TOML from a reader into type T.
/// Datetime values (date, datetime, datetime-local, time) are returned as strings.
pub fn parse(comptime T: type, reader: *Reader, alloc: Allocator) Error!Parsed(T) {
    return parseWith(T, reader, alloc, NoOpDateTimeParser);
}

/// Parse TOML from a reader into type T with a custom datetime parser.
///
/// The DatetimeParser type must provide the following functions:
/// - `parseDate(str: []const u8, alloc: Allocator) Error!TargetType`
/// - `parseDatetime(str: []const u8, alloc: Allocator) Error!TargetType`
/// - `parseDatetimeLocal(str: []const u8, alloc: Allocator) Error!TargetType`
/// - `parseTime(str: []const u8, alloc: Allocator) Error!TargetType`
///
/// Each function's return type (the error union payload) must match the target field type in T.
pub fn parseWith(comptime T: type, reader: *Reader, alloc: Allocator, comptime DatetimeParser: type) Error!Parsed(T) {
    var p = try Parser(DatetimeParser).init(reader, alloc);
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
        while (it.next()) |v| v.deinit();

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

const SliceFinalizer = struct {
    finalize_fn: *const fn (ctx: *anyopaque, Allocator) void,
    context: *anyopaque,

    fn init(
        comptime T: type,
        comptime FieldType: type,
        comptime field_name: []const u8,
        dest: *T,
        array_list_ptr: *anyopaque,
        allocator: Allocator,
    ) error{OutOfMemory}!SliceFinalizer {
        const FieldValueArrayList = std.ArrayList(FieldType);

        const FinalizerCtx = struct {
            array_list: *FieldValueArrayList,
            dest: *T,

            fn finalize(ctx: *anyopaque, alloc: Allocator) void {
                const self_ctx: *@This() = @ptrCast(@alignCast(ctx));
                @field(self_ctx.dest, field_name) = self_ctx.array_list.toOwnedSlice(alloc) catch unreachable;
            }
        };

        const finalizer_ctx = try allocator.create(FinalizerCtx);
        finalizer_ctx.* = .{
            .array_list = @ptrCast(@alignCast(array_list_ptr)),
            .dest = dest,
        };

        return .{
            .finalize_fn = FinalizerCtx.finalize,
            .context = @ptrCast(finalizer_ctx),
        };
    }
};

fn Parser(comptime DateTimeParser: type) type {
    return struct {
        arena: *ArenaAllocator,
        scanner: Scanner,
        token_location: ?SourceLocation = null,
        current_token: ?Token = null,
        advance: bool = true,
        top_level_object: ObjectInfo,
        slice_finalizers: std.ArrayList(SliceFinalizer) = .empty,

        const Self = @This();

        pub fn init(reader: *Reader, alloc: Allocator) error{OutOfMemory}!Self {
            const arena = try alloc.create(ArenaAllocator);
            arena.* = ArenaAllocator.init(alloc);
            return .{
                .arena = arena,
                .scanner = try Scanner.init(reader, alloc),
                .top_level_object = ObjectInfo.init(alloc),
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

        fn parseTableHeader(self: *Self, comptime T: type, dest: *T, expected_token: TokenKind, object_info: *ObjectInfo) Error!void {
            const token = try self.nextToken(null);
            switch (token.kind) {
                .bare_key, .string => {
                    try self.parseKey(T, dest, token.content, expected_token, object_info);
                },
                else => return error.UnexpectedToken,
            }
        }

        fn parseTableContent(self: *Self, comptime T: type, dest: *T, object_info: *ObjectInfo) Error!void {
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

        fn parseValue(self: *Self, comptime T: type, object_info: *ObjectInfo) Error!T {
            const ti = @typeInfo(T);

            const token = try self.nextToken(.expect_value);
            std.debug.print("parseValue kind = {}, context = {s} loc = {any}\n", .{ token.kind, token.content, token.location });

            switch (token.kind) {
                .date => return self.parseDatetime(T, DateTimeParser.parseDate, token.content),
                .datetime => return self.parseDatetime(T, DateTimeParser.parseDatetime, token.content),
                .datetime_local => return self.parseDatetime(T, DateTimeParser.parseDatetimeLocal, token.content),
                .time => return self.parseDatetime(T, DateTimeParser.parseTime, token.content),
                else => {},
            }

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
                        self.ungetToken();
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
                    self.ungetToken();
                    return self.parseInnerTable(T, object_info);
                },

                else => {},
            }

            unreachable;
        }

        fn parseInnerTable(self: *Self, comptime T: type, object_info: *ObjectInfo) Error!T {
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

        fn parseArrayValue(self: *Self, comptime T: type, object_info: *ObjectInfo) Error![]T {
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

        fn skipLineBreaks(self: *Self, hint: ?Scanner.Hint) Error!void {
            while (true) {
                const t = try self.nextToken(hint);
                if (t.kind != .line_break) {
                    self.ungetToken();
                    break;
                }
            }
        }

        fn processPointerToOne(self: *Self, comptime T: type, dest: *T, comptime FieldType: type, comptime field_name: []const u8, expected_token: TokenKind, object_info: *ObjectInfo) Error!void {
            const result = try object_info.fields.getOrPut(field_name);
            if (!result.found_existing) {
                std.debug.print("== initializing .one {s}\n", .{field_name});
                @field(dest, field_name) = try self.arena.allocator().create(FieldType);

                result.value_ptr.* = Value{ .object = ObjectInfo.init(self.arena.allocator()) };
            }

            try self.parseAfterKey(FieldType, @field(dest, field_name), expected_token, &result.value_ptr.object);
        }

        fn processPointerToMany(self: *Self, comptime T: type, dest: *T, comptime FieldType: type, comptime field_name: []const u8, expected_token: TokenKind, object_info: *ObjectInfo) Error!void {
            const FieldValueArrayList = std.ArrayList(FieldType);
            const result = try object_info.fields.getOrPut(field_name);
            if (!result.found_existing) {
                std.debug.print("== initializing .slice {s}\n", .{field_name});

                const list = try self.arena.allocator().create(FieldValueArrayList);
                list.* = .{};

                result.value_ptr.* = Value{ .array = ObjectArray.init(self.arena.allocator(), @ptrCast(list)) };

                // Register finalizer to set dest field to toOwnedSlice
                const finalizer = try SliceFinalizer.init(
                    T,
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

            try result.value_ptr.array.objects.append(self.arena.allocator(), Value{ .object = ObjectInfo.init(self.arena.allocator()) });

            try self.parseAfterKey(FieldType, value_ptr, expected_token, &result.value_ptr.array.objects.items[result.value_ptr.array.objects.items.len - 1].object);
        }

        fn peekNextTokenKind(self: *Self, expected_token: TokenKind) Error!TokenKind {
            const hint: ?Scanner.Hint = if (expected_token == .double_right_bracket) .after_double_bracket else null;
            const tt = try self.nextToken(hint);
            std.debug.print("// tt = {any}, expected={any}\n", .{ tt.kind, expected_token });
            self.ungetToken();
            return tt.kind;
        }

        fn parseKey(self: *Self, comptime T: type, dest: *T, key: []const u8, expected_token: TokenKind, object_info: *ObjectInfo) Error!void {
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

        fn parseAfterKey(self: *Self, comptime T: type, dest: *T, expected_token: TokenKind, object_info: *ObjectInfo) Error!void {
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

        fn parseAfterDot(self: *Self, comptime T: type, dest: *T, expected_token: TokenKind, object_info: *ObjectInfo) Error!void {
            const token = try self.nextToken(null);
            if (token.kind != .bare_key and token.kind != .string) return error.UnexpectedToken;

            const ti = @typeInfo(T);
            if (ti != .@"struct") return error.UnexpectedToken;

            try self.parseKey(T, dest, token.content, expected_token, object_info);
        }
    };
}
