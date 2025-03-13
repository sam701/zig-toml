const std = @import("std");
const testing = std.testing;
const AnyWriter = std.io.AnyWriter;
const Allocator = std.mem.Allocator;
const datetime = @import("../datetime.zig");
const Date = datetime.Date;
const Time = datetime.Time;
const DateTime = datetime.DateTime;
const StructField = std.builtin.Type.StructField;

const SerializerState = struct {
    allocator: Allocator,
    table_comp: std.ArrayList([]const u8),

    const Self = @This();

    fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .table_comp = std.ArrayList([]const u8).init(allocator),
        };
    }

    fn deinit(self: *Self) void {
        self.table_comp.deinit();
    }
};

pub fn serialize(allocator: Allocator, obj: anytype, writer: *AnyWriter) !void {
    const ttype = @TypeOf(obj);
    const tinfo = @typeInfo(ttype);
    var state = SerializerState.init(allocator);
    defer state.deinit();
    try serializeValue(&state, tinfo, obj, writer);
}

fn serializeStruct(state: *SerializerState, value: anytype, writer: *AnyWriter) !void {
    const ttype = @TypeOf(value);
    const tinfo = @typeInfo(ttype);
    if (tinfo != .@"struct") @panic("non struct type given to serialize");

    switch (@TypeOf(value)) {
        Date => {
            try writer.print("{d}-{d:02}-{d:02}", .{ value.year, value.month, value.day });
            return;
        },
        Time => {
            try writer.print("{d:02}:{d:02}:{d:02}", .{ value.hour, value.minute, value.second });
            if (value.nanosecond != 0)
                try writer.print(".{d}", .{value.nanosecond});
            return;
        },
        DateTime => {
            try serializeStruct(state, value.date, writer);
            try serializeStruct(state, value.time, writer);
            if (value.offset_minutes) |om| {
                if (om == 0) return;
                const mins: u16 = @intCast(@divFloor(om, 60));
                const secs: u16 = @intCast(@mod(om, 60));
                try writer.print("-{d:02}:{d:02}", .{ mins, secs });
            }
            return;
        },
        else => {
            if (isMapType(@TypeOf(value))) {
                return serializeMap(state, value, writer);
            }
        },
    }

    comptime var fields = tinfo.@"struct".fields[0..tinfo.@"struct".fields.len].*;
    comptime std.mem.sortUnstable(StructField, &fields, {}, cmpFields);

    inline for (fields) |field| {
        const ftype = @typeInfo(field.type);

        if (ftype != .@"struct" and comptime !isPointerToStruct(ftype)) {
            try writer.print("{s} = ", .{field.name});
            try serializeValue(state, ftype, @field(value, field.name), writer);
            _ = try writer.write("\n");
        }
    }

    inline for (fields) |field| {
        const ftype = @typeInfo(field.type);
        if (ftype != .@"struct" and comptime !isPointerToStruct(ftype)) continue;

        try state.table_comp.append(field.name);

        // Check if the struct comprises of fields which are basically other structs
        // If so, we don't write anything for this struct and instead write only the
        // structs that it holds.
        //
        // Also, since we treat pointer to structs same as normal structs, we also need
        // resolve the pointers to check if the current field is a struct.
        comptime var ftype2 = ftype;
        inline while (ftype2 == .pointer) ftype2 = @typeInfo(ftype2.pointer.child);
        var has_basic_field: bool = undefined;
        inline for (ftype2.@"struct".fields) |inner_field| {
            const iftype = @typeInfo(inner_field.type);
            if (iftype != .@"struct" and comptime !isPointerToStruct(iftype)) {
                has_basic_field = true;
                break;
            }
            has_basic_field = false;
        }

        if (has_basic_field) {
            try writer.writeByte('[');
            for (0..state.table_comp.items.len - 1) |i| {
                try writer.print("{s}.", .{state.table_comp.items[i]});
            }
            try writer.print("{s}]\n", .{field.name});
        }

        try serializeValue(state, ftype, @field(value, field.name), writer);
        _ = state.table_comp.pop();
    }
}

fn isPointerToStruct(t: std.builtin.Type) bool {
    if (t != .pointer) return false;

    var child = @typeInfo(t.pointer.child);
    while (child == .pointer) child = @typeInfo(child.pointer.child);

    return child == .@"struct";
}

fn serializeValue(state: *SerializerState, t: std.builtin.Type, value: anytype, writer: *AnyWriter) !void {
    switch (t) {
        .int, .float, .comptime_int, .comptime_float => {
            if (t == .float) {
                if (value == std.math.inf(@TypeOf(value))) {
                    try writer.print("inf", .{});
                    return;
                } else if (value == -std.math.inf(@TypeOf(value))) {
                    try writer.print("-inf", .{});
                    return;
                }
            }
            try writer.print("{d}", .{value});
        },
        .bool => if (value) try writer.print("true", .{}) else try writer.print("false", .{}),
        .pointer => {
            if (hasStringType(t)) {
                _ = try writer.writeByte('"');
                const string = value;

                var curr_pos: usize = 0;
                while (curr_pos <= string.len) {
                    const new_pos = std.mem.indexOfAnyPos(u8, string, curr_pos, &.{ '"', '\n', '\t', '\r', '\\', 0x0C, 0x08 }) orelse string.len;
                    try writer.print("{s}", .{string[curr_pos..new_pos]});
                    if (new_pos != string.len) {
                        _ = try writer.writeByte('\\');
                        switch (string[new_pos]) {
                            '"' => _ = try writer.writeByte('"'),
                            '\n' => _ = try writer.writeByte('n'),
                            '\t' => _ = try writer.writeByte('t'),
                            '\r' => _ = try writer.writeByte('r'),
                            '\\' => _ = try writer.writeByte('\\'),
                            0x0C => _ = try writer.writeByte('f'),
                            0x08 => _ = try writer.writeByte('b'),
                            else => unreachable,
                        }
                    }
                    curr_pos = new_pos + 1;
                }
                _ = try writer.writeByte('"');
            } else {
                try serializeValue(state, @typeInfo(t.pointer.child), value.*, writer);
            }
        },
        .array => {
            try writer.print("[ ", .{});
            if (t.array.len != 0) {
                var i: usize = 0;
                while (i < t.array.len - 1) {
                    const elm = value[i];
                    try serializeValue(state, @typeInfo(t.array.child), elm, writer);
                    try writer.print(", ", .{});
                    i += 1;
                }
            }
            const elm = value[t.array.len - 1];
            try serializeValue(state, @typeInfo(t.array.child), elm, writer);
            try writer.print(" ]", .{});
        },
        .@"struct" => try serializeStruct(state, value, writer),
        .@"enum" => try writer.print("\"{s}\"", .{@tagName(value)}),
        .@"union" => {
            switch (value) {
                inline else => |s| try serializeValue(state, @typeInfo(@TypeOf(s)), s, writer),
            }
        },
        .optional => {
            if (value) |v| {
                try serializeValue(state, @typeInfo(@TypeOf(v)), v, writer);
            }
        },
        else => {},
    }
}

fn serializeMap(state: *SerializerState, value: anytype, writer: *std.io.AnyWriter) !void {
    {
        var key_iter = value.keyIterator();
        const key_type = @typeInfo(@TypeOf(key_iter.next().?.*));
        if (!hasStringType(key_type)) @panic("Maps with non-string compatible types cannot be serialized");
    }

    var value_iter = value.valueIterator();
    const value_type = @TypeOf(value_iter.next().?.*);
    const value_tinfo = @typeInfo(value_type);

    var fields = try state.allocator.alloc([]const u8, value.count());
    defer state.allocator.free(fields);
    var key_iter = value.keyIterator();

    var counter: u32 = 0;
    while (key_iter.next()) |key| {
        fields[counter] = key.*;
        counter += 1;
    }
    std.mem.sortUnstable([]const u8, fields, {}, cmpStrings);

    if (value_tinfo != .@"struct" and comptime !isPointerToStruct(value_tinfo)) {
        for (fields) |field| {
            try writer.print("{s} = ", .{field});
            try serializeValue(state, value_tinfo, value.get(field).?, writer);
            _ = try writer.write("\n");
        }
    } else if (isMapType(value_type)) {
        for (fields) |field| {
            try state.table_comp.append(field);
            try writer.writeByte('[');
            for (0..state.table_comp.items.len - 1) |i| {
                try writer.print("{s}.", .{state.table_comp.items[i]});
            }
            try writer.print("{s}]\n", .{field});
            try serializeMap(state, value.get(field).?, writer);
            _ = state.table_comp.pop();
        }
    } else {
        for (fields) |field| {
            try state.table_comp.append(field);
            try writer.writeByte('[');
            for (0..state.table_comp.items.len - 1) |i| {
                try writer.print("{s}.", .{state.table_comp.items[i]});
            }
            try writer.print("{s}]\n", .{field});
            try serializeStruct(state, value.get(field).?, writer);
            _ = state.table_comp.pop();
        }
    }
}

inline fn hasStringType(t: std.builtin.Type) bool {
    return ((t.pointer.child == u8 and t.pointer.size == .slice) or (@typeInfo(t.pointer.child) == .array and @typeInfo(t.pointer.child).array.child == u8) and t.pointer.is_const);
}

inline fn isMapType(val_t: type) bool {
    return @hasDecl(val_t, "keyIterator") and @hasDecl(val_t, "valueIterator") and @hasDecl(val_t, "iterator");
}

fn cmpFields(_: void, lhs: StructField, rhs: StructField) bool {
    return std.mem.order(u8, lhs.name, rhs.name) == .lt;
}

fn cmpStrings(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.order(u8, lhs, rhs) == .lt;
}
